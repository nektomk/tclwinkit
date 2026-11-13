<#
publish-release.ps1 -- publish the release artifacts as a GitHub Release.

Pipeline (each step logs one fixed-width line):
  1. read the kit version from src\kit\vfs\lib\kit_init.tcl -- that is the single
     source of truth: it is also the version compiled into the exe and the name
     of every published archive, so a release cannot drift from the binaries;
  2. hash the artifacts and render SHA256SUMS.txt. What ships is one archive per
     toolchain -- scripts\build-release-archives.ps1 writes those into
     build\release-stage\ -- plus the docs archive from dist\. Inside an archive
     the executables carry short chain-agnostic names (tclwin.exe, tkwin.exe),
     so the toolchain and the version are named by the archive and by its single
     top-level directory, not by each file;
  3. render the release notes from src\docs\release-notes.md by substituting
     {{PLACEHOLDER}} tokens -- the notes live in the repo (reviewable, diffable)
     instead of hiding inside this script;
  4. require a clean tree, push HEAD if it is ahead, create and push an annotated
     tag v<ver>;
  5. create the release through the REST API, upload the four assets, then verify
     each came back state=uploaded with the local byte size.

Credentials: no gh CLI and no manually stored token. Git Credential Manager
already holds the OAuth token that `git push` uses, so this script asks for it
via `git credential fill` with GCM_INTERACTIVE=Never and never prints it. The
token needs the `repo` scope to release on a private repository; that is checked
against X-OAuth-Scopes before anything is written.

Re-runs: if a release for the tag already exists the script stops, because
uploading again would duplicate assets. -Force reuses that release and replaces
same-named assets first. -DryRun does every local step and prints what the
remote steps would do, without touching GitHub.

  powershell -File scripts\publish-release.ps1 [-DryRun] [-Force]
             [-Version 0.1] [-Repo nektomk/tclwinkit] [-Branch main]
#>
[CmdletBinding()]
param(
    [string]$Version = '',
    [string]$Repo = 'nektomk/tclwinkit',
    [string]$Branch = 'main',
    [string]$Dist = '',
    [switch]$DryRun,
    [switch]$Force
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'      # the PS 5.1 progress bar costs minutes
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$Root = Split-Path -Parent $PSScriptRoot
if (-not $Dist) { $Dist = Join-Path $Root 'dist' }
$Stage = Join-Path $Root 'build\release-stage'
$Utf8 = [System.Text.UTF8Encoding]::new($false)

# Everything this script writes leaves the machine as a release asset, so it is
# UTF-8 without BOM with LF endings. Do NOT use [IO.File]::WriteAllLines here:
# it joins with Environment.NewLine, which is CRLF on Windows, and a CRLF
# SHA256SUMS.txt makes the documented `sha256sum -c SHA256SUMS.txt` fail on
# every non-Windows box ("'a.txt'$'\r': No such file or directory", exit 1).
function Put-LfText([string]$Path, [string[]]$Lines) {
    [System.IO.File]::WriteAllText($Path, (($Lines -join "`n") + "`n"), $script:Utf8)
}

$Tick = [string][char]96                       # markdown code span delimiter

function Say { param([string]$Label, [string]$Text) '{0,-14}{1}' -f ($Label + ':'), $Text }
function Skip($what, $detail) { Say $what ('SKIPPED (dry run) ' + $detail) }

# ------------------------------------------------------------- 1. version ---
if (-not $Version) {
    $m = Select-String -Path (Join-Path $Root 'src\kit\vfs\lib\kit_init.tcl') `
                       -Pattern '^\s*variable\s+version\s+([0-9][^ \t]*)' | Select-Object -First 1
    if (-not $m) { throw 'cannot read the version from src\kit\vfs\lib\kit_init.tcl' }
    $Version = $m.Matches[0].Groups[1].Value
}
$Tag = 'v' + $Version
$head = ((git rev-parse HEAD) -join '')      # also referenced by the notes template
Say '=== PUBLISH' ($Repo + ' ' + $Tag + ' (from ' + $Branch + ')')
Say 'version' $Version

# ------------------------------------------------- 2. artifacts and digests ---
# published asset name -> where that file lives + the label shown in the
# release UI. The key IS the asset name now: since 0.3 the release ships the
# archives themselves, so there is no longer a separate short working name to
# map from, and the two families live in different directories (exe archives in
# build\release-stage\, the docs archive in dist\).
$Plan = [ordered]@{}
$Plan[('tclwinkit-msvc-{0}.zip' -f $Version)] = @{
    path  = (Join-Path $Stage ('tclwinkit-msvc-{0}.zip' -f $Version))
    label = 'MSVC x64, static CRT: tclwin.exe (console) + tkwin.exe (GUI)'
}
$Plan[('tclwinkit-mingw-{0}.zip' -f $Version)] = @{
    path  = (Join-Path $Stage ('tclwinkit-mingw-{0}.zip' -f $Version))
    label = 'MinGW-w64 x64, UCRT: tclwin.exe (console) + tkwin.exe (GUI)'
}
$Plan[('tclwinkit-docs-{0}.zip' -f $Version)] = @{
    path  = (Join-Path $Dist ('tclwinkit-docs-{0}.zip' -f $Version))
    label = 'Documentation, man pages, demos, licenses'
}

$rows = @()
foreach ($asset in $Plan.Keys) {
    $p = $Plan[$asset].path
    if (-not (Test-Path -LiteralPath $p)) {
        throw ("missing artifact: $p -- run scripts\build-release-archives.ps1 " +
               '(exe archives) and scripts\build-docs-artifact.ps1 (docs) first')
    }
    $fi = Get-Item -LiteralPath $p
    $rows += [pscustomobject]@{
        path = $p; asset = $asset; label = $Plan[$asset].label
        bytes = $fi.Length
        sha256 = (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLower()
    }
}
foreach ($r in $rows) { Say 'asset' ('{0,-42} {1,10} B  {2}' -f $r.asset, $r.bytes, $r.sha256) }
$total = ($rows | Measure-Object bytes -Sum).Sum
Say 'total' ('{0:N2} MB over {1} files' -f ($total / 1MB), $rows.Count)

# Fail fast on a malformed plan rather than at upload time. Since 0.3 the
# published asset name IS the file name, so a plan entry whose key disagrees with
# the base name of its path means $Plan and the builders have drifted apart --
# and without this check the drift surfaces as an opaque REST error AFTER the
# annotated tag has already been pushed. Exercised by -DryRun, which stops at the
# clean-tree check in step 4 and never reaches the upload loop.
foreach ($r in $rows) {
    $base = [System.IO.Path]::GetFileName($r.path)
    if ($base -ne $r.asset) {
        throw ('asset name ' + $r.asset + ' does not match its file ' + $base)
    }
    if (-not $r.label) { throw ('asset ' + $r.asset + ' has no release label') }
    if ($r.bytes -le 0) { throw ('asset ' + $r.asset + ' is empty') }
}
Say 'plan' ("$($rows.Count) asset(s): name==filename, labelled, non-empty")

# SHA256SUMS.txt lists the asset names, so `sha256sum -c` works in whatever
# directory the user downloaded into. Leading '#' comment lines are accepted by
# GNU coreutils; a BLANK line is not -- it counts as an improperly formatted
# line, which is a warning under plain -c and a hard exit 1 under --strict
# (both measured). So the header runs straight into the checksums.
New-Item -ItemType Directory -Force $Stage | Out-Null
# Each -f operand needs its OWN parentheses inside a comma list: the format
# operator binds looser than the list separator, so
#   @('...{0}...' -f $Version, 'next line', 'third line')
# parses as ONE format call with three arguments ('...{0}...' -f @($Version,
# 'next line', 'third line')). The extra arguments are silently discarded
# because the template has no {1}/{2}, so the array has one element and two
# header lines vanish WITHOUT ANY ERROR. Measured on 2026-10-28: the rendered
# SHA256SUMS.txt was 536 B / 6 lines instead of 620 B / 8 lines, i.e. the
# `sha256sum -c` and `certutil` hints documented in docs/CONVENTIONS.md 4.2
# were never shipped. The published file (630 B, 9 CRLF lines) still predates
# both that bug and the fix, so it carries the CRLF and blank-line defects
# described in 4.1 and 4.2 until the release is re-issued.
$sums = @(('# tclwinkit {0} -- SHA-256 of the release assets' -f $Version),
          '# verify:  sha256sum -c SHA256SUMS.txt',
          '#      or:  certutil -hashfile <file> SHA256')
$sums += $rows | ForEach-Object { '{0} *{1}' -f $_.sha256, $_.asset }
$sumsPath = Join-Path $Stage 'SHA256SUMS.txt'
Put-LfText $sumsPath $sums
$sumBytes = (Get-Item -LiteralPath $sumsPath).Length
Say 'sums' ('{0} ({1} B)' -f $sumsPath, $sumBytes)

# ------------------------------------------------------ 3. release notes ---
$tplPath = Join-Path $Root 'src\docs\release-notes.md'
if (-not (Test-Path -LiteralPath $tplPath)) { throw "notes template missing: $tplPath" }
$tbl = @('| Asset | What it is |', '|---|---|')
foreach ($r in $rows) {
    $tbl += ('| {0}{1}{0} | {2} |' -f $Tick, $r.asset, $r.label)
}
$tbl += ('| {0}SHA256SUMS.txt{0} | checksums of all of the above |' -f $Tick)
$notes = [System.IO.File]::ReadAllText($tplPath, $Utf8)
$subst = [ordered]@{
    '{{ASSET_TABLE}}' = ($tbl -join "`n")
    '{{VERSION}}' = $Version
    '{{HEAD}}' = $head
    # These are substituted BARE: the template owns any markdown code spans, so
    # the same placeholder stays correct inside a ``` fence (where a `code span`
    # would render as literal backticks) and in prose.
    '{{TAG}}' = $Tag
    # The archive names only: inside an archive the executables carry short,
    # chain-agnostic names (tclwin.exe, tkwin.exe), and the release notes spell
    # those out literally, so there is no per-exe placeholder left to feed.
    '{{MSVC_ZIP}}' = ('tclwinkit-msvc-{0}.zip' -f $Version)
    '{{MINGW_ZIP}}' = ('tclwinkit-mingw-{0}.zip' -f $Version)
    '{{DOCS_ZIP}}' = ('tclwinkit-docs-{0}.zip' -f $Version)
}
foreach ($k in $subst.Keys) { $notes = $notes.Replace($k, $subst[$k]) }
$left = [regex]::Matches($notes, '\{\{[A-Z_]+\}\}') | ForEach-Object { $_.Value } | Select-Object -Unique
if ($left) { throw ("unsubstituted placeholder(s) in release-notes.md: " + ($left -join ', ')) }
$notesPath = Join-Path $Stage 'release-body.md'
[System.IO.File]::WriteAllText($notesPath, $notes, $Utf8)
Say 'notes' ('{0} ({1} B, from src\docs\release-notes.md)' -f $notesPath, (Get-Item -LiteralPath $notesPath).Length)

# --------------------------------------------------- 4. git prerequisites ---
Say 'HEAD' $head
if (@(git status --porcelain).Count) { throw 'working tree is not clean; commit first' }
git fetch origin $Branch --quiet | Out-Null
$behind = ((git rev-list --count "HEAD..origin/$Branch") -join '')
$ahead = ((git rev-list --count "origin/$Branch..HEAD") -join '')
if ($behind -ne '0') { throw ('origin/' + $Branch + ' is ' + $behind + ' commit(s) ahead of HEAD; pull first') }
if ($ahead -ne '0') {
    if ($DryRun) { Skip 'push' ("$ahead commit(s) ahead") }
    else { Say 'push' ("pushing $ahead commit(s) to origin/$Branch"); git push origin ("HEAD:" + $Branch) }
} else { Say 'push' 'origin already up to date' }

# Tag handling. Rules:
#  - the tag must point at the commit whose binaries we are publishing;
#  - a dry run changes NOTHING, local state included;
#  - for an annotated tag `git ls-remote --tags` prints the TAG OBJECT sha, so
#    the remote comparison uses the peeled ref  v1^{}  (GitHub advertises peels).
$localTagCommit = ((git rev-parse -q --verify ('refs/tags/' + $Tag + '^{commit}')) -join '')
$peeled = ((git ls-remote origin ('refs/tags/' + $Tag + '^{}')) -join '')
$rawRemote = ((git ls-remote --tags origin ('refs/tags/' + $Tag)) -join '')
$remoteSha = if ($peeled) { ($peeled -split "`t")[0] } elseif ($rawRemote) { ($rawRemote -split "`t")[0] } else { '' }
if ($remoteSha -and $remoteSha -ne $head) {
    throw ("remote tag $Tag exists at commit $remoteSha but HEAD is $head; " +
           'a tag of a published release must not be moved -- bump the version instead')
}
if ($localTagCommit) {
    Say 'tag' ("local $Tag -> $localTagCommit")
    if ($localTagCommit -ne $head) {
        # a stale LOCAL tag carries no published artifacts, recreating is safe
        Say 'tag' "$Tag is not on HEAD -> the local tag will be recreated at $head"
        if (-not $DryRun) {
            git tag -d $Tag | Out-Null
            $localTagCommit = ''
        }
    }
}
if (-not $localTagCommit) {
    $tagMsgPath = Join-Path $Stage 'tag-message.txt'
    Put-LfText $tagMsgPath @(
        ('tclwinkit ' + $Version), '',
        'Portable single-file Tcl 9.0.4 / Tk 9.0.4 distribution for Windows x64.',
        'Four kit executables plus the documentation archive.')
    if ($DryRun) {
        Skip 'tag' ("would create annotated $Tag -> $head and push it")
    } else {
        git tag -a $Tag -F $tagMsgPath
        Say 'tag' ("created $Tag -> $head")
        git push origin $Tag
        Say 'tag push' 'ok'
    }
}

# ---------------------------------------------------------- 5. API session ---
$env:GCM_INTERACTIVE = 'Never'          # never pop a UI from a script
$cred = $("protocol=https`nhost=github.com`n`n") | git credential fill 2>$null
$token = ($cred | Where-Object { $_ -like 'password=*' } | Select-Object -First 1) -replace '^password=', ''
if (-not $token) { throw 'no cached github credential (run an interactive git push once)' }
$user = ($cred | Where-Object { $_ -like 'username=*' } | Select-Object -First 1) -replace '^username=', ''
Say 'auth' ("user $user, token length $($token.Length) (value not printed)")
$h = @{
    Authorization = ('Bearer ' + $token)
    Accept = 'application/vnd.github+json'
    'X-GitHub-Api-Version' = '2022-11-28'
    'User-Agent' = 'tclwinkit-publish-release'
}
$api = 'https://api.github.com/repos/' + $Repo
$probe = Invoke-WebRequest -Uri $api -Headers $h -UseBasicParsing -TimeoutSec 60
$scopes = (($probe.Headers['X-OAuth-Scopes']) -join '')
Say 'details' ("HTTP $($probe.StatusCode), scopes [$scopes]")
$repoJson = $probe.Content | ConvertFrom-Json
# Two token shapes reach this script, and only one of them advertises its grants
# in X-OAuth-Scopes. A classic PAT (ghp_...) or an OAuth token does; a
# fine-grained PAT (github_pat_...) does not -- that header is simply absent,
# because its grants are per repository rather than account-wide. So a
# scopes-only test rejects a fine-grained token that can in fact push and
# release. Measured on this machine against this private repository: HTTP 200,
# permissions admin/push/pull all true, X-OAuth-Scopes absent -- and the old
# check threw "token lacks the 'repo' scope".
# Ask for the capability the rest of the script needs instead: either the
# classic 'repo' scope, or push access to this repository as the API reports it
# for the authenticated token. Both are refusals when they are really absent.
$canPush = [bool]($repoJson.permissions -and $repoJson.permissions.push)
if (($scopes -notmatch '(^|, )repo(,|$)') -and (-not $canPush)) {
    throw ("token can neither show the 'repo' scope nor push to $Repo " +
           "(scopes: $scopes; permissions.push: $canPush)")
}
Say 'authz' ("scopes [$scopes], permissions.push=$canPush -- accepted")
Say 'repo' ("$($repoJson.full_name) private=$($repoJson.private) default=$($repoJson.default_branch)")

# ------------------------------------------------------- 6. create release ---
$notesText = [System.IO.File]::ReadAllText($notesPath, $Utf8)
$rel = $null
try {
    $rel = Invoke-RestMethod -Uri ($api + '/releases/tags/' + $Tag) -Headers $h -TimeoutSec 60
} catch {
    if (-not ($_.Exception.Response -and [int]$_.Exception.Response.StatusCode -eq 404)) { throw }
}
if ($rel) {
    if (-not $Force) {
        throw ('release already published: ' + $rel.html_url + ' -- rerun with -Force to replace its assets')
    }
    Say 'release' ("reusing existing id $($rel.id)")
    $names = @($rows | ForEach-Object { $_.asset }) + @('SHA256SUMS.txt')
    foreach ($n in $names) {
        foreach ($d in @($rel.assets | Where-Object { $_.name -eq $n })) {
            if ($DryRun) { Skip 'delete' $d.name }
            else {
                Invoke-RestMethod -Method Delete -Uri $d.url -Headers $h -TimeoutSec 60 | Out-Null
                Say 'deleted' $d.name
            }
        }
    }
} elseif ($DryRun) {
    Skip 'release' 'would POST /releases (published, not a prerelease)'
} else {
    $payload = @{
        tag_name = $Tag; target_commitish = $Branch; name = ('tclwinkit ' + $Version)
        body = $notesText; draft = $false; prerelease = $false
    } | ConvertTo-Json -Depth 5 -Compress
    $rel = Invoke-RestMethod -Method Post -Uri ($api + '/releases') -Headers $h `
            -ContentType 'application/json; charset=utf-8' `
            -Body $Utf8.GetBytes($payload) -TimeoutSec 120
    Say 'release' ("CREATED id $($rel.id) -> $($rel.html_url)")
}

# ------------------------------------------------------------ 7. uploads ---
if ($rel) { $uploadBase = $rel.upload_url -replace '\{[^}]*\}$', '' }
else { $uploadBase = ('https://uploads.github.com/repos/{0}/releases/0/assets' -f $Repo) }
$files = @{}
foreach ($asset in $Plan.Keys) { $files[$asset] = $Plan[$asset].path }
$files['SHA256SUMS.txt'] = $sumsPath
$sizes = @{}
foreach ($r in $rows) { $sizes[$r.asset] = $r.bytes }
$sizes['SHA256SUMS.txt'] = $sumBytes
$all = @($rows | ForEach-Object { $_.asset }) + @('SHA256SUMS.txt')
foreach ($name in $all) {
    if ($DryRun) { Skip 'upload' $name; continue }
    $qs = '?name=' + [Uri]::EscapeDataString($name)
    # SHA256SUMS.txt is not in $Plan, so the label lookup has to tolerate a miss.
    if ($Plan.Keys -contains $name) {
        $qs += '&label=' + [Uri]::EscapeDataString($Plan[$name].label)
    }
    $up = Invoke-RestMethod -Method Put -Uri ($uploadBase + $qs) -Headers $h `
            -ContentType 'application/octet-stream' -InFile $files[$name] -TimeoutSec 900
    if ($up.state -ne 'uploaded' -or $up.size -ne $sizes[$name]) {
        throw ('upload failed for ' + $name + ": state=$($up.state) size=$($up.size) expected=$($sizes[$name])")
    }
    Say 'upload' ('{0,-42} uploaded {1,10} B (size ok)' -f $up.name, $up.size)
}

# ------------------------------------------------------------- 8. verify ---
if ($DryRun) { Say '===' 'DRY RUN DONE (nothing written to GitHub)'; return }
Start-Sleep -Seconds 3
$fin = Invoke-RestMethod -Uri ($api + '/releases/tags/' + $Tag) -Headers $h -TimeoutSec 60
Say '===' 'VERIFY'
Say 'release' $fin.html_url
Say 'status' ("tag=$($fin.tag_name) draft=$($fin.draft) prerelease=$($fin.prerelease) published=$($fin.published_at)")
$problems = @()
foreach ($name in $all) {
    $a = @($fin.assets | Where-Object { $_.name -eq $name })
    if ($a.Count -ne 1) { $problems += ('{0}: {1} asset(s)' -f $name, $a.Count); continue }
    if ($a[0].size -ne $sizes[$name]) {
        $problems += ('{0}: size {1} != local {2}' -f $name, $a[0].size, $sizes[$name])
    }
    if ($a[0].state -ne 'uploaded') { $problems += ('{0}: state {1}' -f $name, $a[0].state) }
}
Say 'assets' ("$($fin.assets.Count) present, expected $($all.Count)")
if ($problems.Count) {
    foreach ($p in $problems) { Say 'MISMATCH' $p }
    throw ("verification failed ($($problems.Count) problem(s))")
}
Say 'verified' ("all $($all.Count) assets match the local byte sizes, state=uploaded")
Say 'downloads' (($fin.assets | ForEach-Object { $_.download_count }) -join ', ')
Say '===' ("RELEASE PUBLISHED: $($fin.html_url)")
