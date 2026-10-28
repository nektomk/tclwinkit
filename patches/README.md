# Патчи вендорных исходников

Все патчи применяются **in-place** к распакованным деревьям в
`build/msvc/ext/` и `build/mingw/ext/` (обе копии идентичны, если не оговорено
иное). Здесь лежат контрольные копии пропатченных файлов — при пересоздании
деревьев из вендорных тарболов скопируйте их поверх оригиналов.

Общий объём правок на пакет — десятки строк; семантика пакетов не меняется,
правки решают только проблемы порта на Tcl 9 / MSVC / статический кит.

## Пометки и лицензии

Правки **не** меняют лицензию исходника: модифицированный файл распространяется
под лицензией оригинала, отдельных прав мы на них не заявляем. Поэтому
клауза лицензии Tcl («modifications … need not follow the licensing terms
described here, provided that the new terms are clearly indicated on the first
page of each file where they apply») не применяется — новых терминов нет.

Шапки copyright изменённых файлов не удаляются. Где их не было у апстрима
(`rl_json.c`, `rl_jsonInt.h`, `names.c`, `scopedobject.itcl`), мы не добавляем
их и не выдумываем держателя.

Комментарий `WINKIT:` ставится только там, где правка меняет **логику теста**
(три файла в разделе iwidgets ниже) — то есть там, где читатель теста не
сможет вывести изменение из самого диффа. В C/Tcl-исходниках сборки маркеров
нет: изменения локальны и очевидны (`#ifdef _MSC_VER`, `case` → `switch`),
а индекс изменений — эта таблица.

Сводная атрибуция бандла — в [`THIRD-PARTY-NOTICES.md`](../THIRD-PARTY-NOTICES.md)
(раздел «Modifications and pruning»), тексты лицензий — в
[`LICENSES/`](../LICENSES/).

## TWAPI 5.2.0 (бинарная замена, контрольных копий нет)

Правок в исходниках TWAPI нет. Есть одна замена **бинарников**, которую
выполняет сама сборочная цепочка: TWAPI поставляет предсобранные
библиотеки dyncall (MSVC, динамическая CRT `/MD`), а наш кит собирается со
статической CRT, поэтому эти три файла перезаписываются нашими:

| файл | апстрим, B | msvc, B | mingw, B |
|---|---|---|---|
| `dyncall/dyncall-0.9/lib/release_amd64/libdyncall_s.lib` | 23 406 | 27 984 | 22 404 |
| `dyncall/dyncall-0.9/lib/release_amd64/libdyncallback_s.lib` | 7 988 | 7 646 | 8 378 |
| `dyncall/dyncall-0.9/lib/release_amd64/libdynload_s.lib` | 3 304 | 3 534 | 3 446 |

Кто делает: `scripts/build-msvc-ext.bat` L17-20 и
`scripts/build-mingw-ext.sh` L19-22 (источник замены — наш же пересобранный
dyncall 0.9 из `build/<цепочка>/ext/dyncall-0.9`).

`release_x86/*.lib` не трогаются и остаются байт-в-байт апстримными:
x64 — единственная цель. Ни один `.lib` из дерева TWAPI в образ не попадает
(промер 2026-10-27: в `build/msvc/kit/stage/` ноль файлов `*.lib`),
линкуется только наш пересобранный dyncall, так что отгружаемые ассеты этой
заменой не затронуты.

Контрольных копий в `twapi/` намеренно нет: это не дифф исходника, а
артефакт сборки, и его нельзя «скопировать поверх оригинала» — он
воспроизводится самой цепочкой при каждом прогоне. Лицензия dyncall
(ISC-подобная, требует сохранить текст авторства) — в
[`LICENSES/dyncall/LICENSE`](../LICENSES/dyncall/LICENSE); она относится к
нашему пересобранному коду, а не к перезаписанным бинарникам.

Провенанс апстримных бинарников: [`docs/SOURCES.md`](../docs/SOURCES.md),
разбор пофайлового сравнения — в нём же.

## rl_json 0.17.8 (`rl_json/`)

| Файл | Правка |
|---|---|
| `rl_jsonInt.h` | `__has_c_attribute(clang::suppress)` спрятан в `#if defined(__clang__)` (MSVC парсит токены даже за `&&`-guard) |
| `rl_json.c` | `#if defined(_MSC_VER)`-заглушка `mkstemp` (нет в MSVC CRT; используется только debug-командой `checkmem`) |
| `names.c` | teabase: `unistd.h`/`clock_gettime`/`srandom`/`random` заменены Win32-эквивалентами под `#ifdef _WIN32` |
| `makefile.vc` | (1) `echo ... \>>` вместо `\>` — апстрим-баг: `>` обрезал файл и стирал ITCL_DIR-подобные строки, здесь TK_DIR/TK_DOTVERSION; (2) `PRJ_INCLUDES = -I"..\teabase"`, в PRJ_OBJS добавлены `names.obj` (teabase) и `rl_jsonBuildInfo.obj`; (3) `PRJ_DEFINES`: конфиг-макросы `/DENSEMBLE=0 /DDEDUP=1 /DDEBUG=0 /DUNLOAD=0 /DRL_JSON_LIBRARY_PATH_INSTALL=... /DRL_JSON_LIBRARY=... /DRL_JSON_STUBLIB=... /DRL_JSON_HEADER=...` и `/Zc:preprocessor` (без него вариативный макрос CHECK_ARGS_LABEL раскрывается неверно → C4003/C2065); (4) объявлена зависимость `$(TMP_DIR)\rl_jsonBuildInfo.obj: ..\generic\rl_jsonUuid.h` — у апстрима она есть в `Makefile.in` (`rl_jsonBuildInfo.$(OBJEXT): rl_jsonUuid.h`), в nmake-файле её никогда не было, поэтому nmake переиспользовал старый объектник и библиотека носила UUID предыдущей сборки |
| все `generic/*.c` | `\bfinally\b` → `finally_label` (256 меток goto: `finally` — ключевое слово SEH в MSVC) |
| — | `generic/rl_jsonUuid.h` кладётся сборкой (`build-msvc-ext2.bat`) со значением `unknown`, а не копируется из-под configure — см. «UUID вендора» ниже |

`rl_jsonInt.h.orig` / `makefile.vc.orig` — исходники для diff. Контрольных
копий `api.c` нет намеренно: строка «все `generic/*.c`» покрывает его то же
правило, что и `rl_json.c` (65 вхождений из 256, остальные 191 — в
`rl_json.c`), и проверяется оно не наличием файла, а сравнением дерева с
апстримным тарболом: после одной только замены `\bfinally\b` апстримный
`api.c` совпадает с нашим байт-в-байт (48152 B, дельта ровно 65 × 6 = 390).
Разбор — в [`docs/SOURCES.md`](../docs/SOURCES.md).

## mpexpr 1.2 (`mpexpr/`)

| Файл | Правка |
|---|---|
| `mpexpr.h` | легаси-макросы Tcl 8.x: `_ANSI_ARGS_(x) → x`, `TCL_VARARGS_DEF(type,name) → (type name, ...)`, `TCL_VARARGS_START(type,name,ap) → (va_start(ap,name), name)`; guard'ы CONST/CONST84 |
| `mpparse.c` | (1) `(VOID *)` → `(void *)`; (2) шим `MpBackslash` (~80 строк) + `#define Tcl_Backslash MpBackslash` под `TCL_MAJOR_VERSION > 8` — в Tcl 9 публичный `Tcl_Backslash` удалён |
| `zmath.h` | guard'ы `CONST`/`CONST84` (файлы zmod.c и др. включают только zmath.h, не mpexpr.h) |

Замечание: `VOID` НЕ определяется (`#define VOID void` ломает `winnt.h` — там
`#ifndef VOID` скрывает typedef'ы CHAR/SHORT).

MinGW: сборка кастомным gcc-циклом в `scripts/build-mingw-ext2.sh`
(`-fpermissive` против implicit-declaration в GCC 14+), `ar rcs bld-mingw/libmpexpr.a`.

## itk 4.2.7 (`itk-makefile.vc.patched`)

- `win/rules.vc` переименован в `rules.vc.own`: itk несёт rules.vc 1.19, но
  БЕЗ targets.vc → U1052; fallback на tcl'овский rules.vc 1.16 работает.
- `win/makefile.vc`: `echo TK_DIR = \> nmakehlp.out` → `\>>` (тот же апстрим-баг
  обрезания, что в rl_json; стирал ITCL_DIR), аналогично для TK_DOTVERSION.

## tktreectrl 2.5.2 (`tktreectrl/tkWinTree.c.patched`)

- `DllMain` обёрнут в `#ifndef STATIC_BUILD`: в статическом ките DllMain уже
  определяет twapi → LNK2005/multiple definition. `thisModule` (HMODULE для
  `GetModuleFileNameA`) остаётся NULL — GetModuleFileNameA(NULL) возвращает
  путь exe, что для кита корректно.

## tkdnd 2.9.5

Патчей нет. C++-файл `TkDND_OleDND.cpp` уже имеет `extern "C"` у `Tkdnd_Init`;
при линковке gcc (не g++) добавлен `-lstdc++`.

## Iwidgets 4.1.1 (`iwidgets/`)

Pure-Tcl пакет (копируется в `kit.vfs/lib/iwidgets4.1.1/` на этапе assemble),
поэтому правки применяются к дереву `build/common/iwidgets-4.1.1/` — оно одно на
обе сборки. Контрольные копии: `iwidgets/generic/` (runtime) и `iwidgets/tests/`
(тестовые наборы). После фикса статики в дочерних interp (`pkgIndex.tcl`) и
Tk-ресурсов курсоров оставалось 135 падений; все устранены, **3308/3308**.

### Runtime (`generic/`) — реальные баги под Tcl/Tk 9

| Файл | Правка |
|---|---|
| `colors.itcl` | `case $i \` → `switch -- $i \` (команда `case` удалена в Tcl 9). Один вызов в `hsbToRgb` → каскад давал падения во всех виджетах, использующих `iwidgets::colors::bottomShadow/topShadow` (tabnotebook, usual, …) |
| `canvasprintbox.itk` | два `case $x in {` → `switch -- $x {` (`ezPaperInfo`: размеры бумаги + ориентация). Каскад: canvasprintbox 31 F, canvasprintdialog 52 F, usual c3/c4 |
| `radiobox.itk` | `trace variable … w` → `trace add variable … write`, `trace vdelete … w` → `trace remove variable … write`. Синтаксис `trace variable` удалён в Tcl 9 → 33 F radiobox + usual c32 |
| `scopedobject.itcl` | то же в конструкторе/деструкторе (`trace add/remove variable … undef`). Scopedobject — базовый класс, поэтому починка сняла большую часть точечных падений (checkbox, combobox, hierarchy, menubar, toolbar, scrolledhtml, scrolledtext, extbutton, …) |
| `checkbox.itk`, `radiobox.itk` | `flash` теперь явно `return`: в Tk 9 `button flash` оставляет в результате имя индикаторного изображения (`::tk::icons::indicator16_…`), а документированный результат метода — пустая строка |

Порядок аргументов важен: `trace add variable NAME op CMD`, а не `trace add NAME op CMD`
(первая попытка дала `bad option "::itcl::internal::variables::…": must be execution,
command, or variable`).

### Тесты (`tests/`) — легаси-ожидания, несовместимые с Tk 9 / Windows

| Файл | Правка |
|---|---|
| `combobox.test` | `bad screen distance "bogus"` → `expected screen distance but got "bogus"` (Tk 9 переформулировал сообщение; 4 F) |
| `extbutton.test` | `image "bogus" doesn't exist` → `does not exist` (1 F) |
| `menubar.test`, `toolbar.test` | `-underline -1` → ожидаемый `{}`: Tk 9 хранит «нет подчёркивания» как пустое значение, а не `-1` (3 F) |
| `hierarchy.test` | `glob $env(HOME)/*` на Windows даёт пустой список (обратные слеши — экранирование), отсюда `the node doesn't exist` в Hierarchy-3.9…3.12; введён `set homedir [string map {\\ /} $env(HOME)]`, `get_files` использует ту же переменную, чтобы UID узлов совпадали байт-в-байт (4 F) |
| `scrolledtext.test`, `scrolledhtml.test` | жёстко зашитый Unix-путь `/tmp/…` в `export` → `$::iwtmp` = `[string map {\\ /} $env(TEMP)]` (2 F) |

Комментарием `WINKIT:` помечены правки именно этого раздела — там, где меняется
логика теста и дифф сам по себе не объясняет, что ожидал апстрим. В
C/Tcl-исходниках сборки таких маркеров нет (см. «Пометки и лицензии» выше).

## Демо iwidgets в docs-архиве — правило упаковки, не патч

Демо-скрипты (`demos/extbutton`, `hyperhelp`, `mainwindow`, `scrolledhtml`,
`scrolledtext`, `toolbar`) берут картинки/справку из
`$iwidgets::library/demos/...`. В ките эта переменная указывает внутрь zipfs
(`//zipfs:/app/lib/iwidgets4.1.1`), где демо намеренно нет, поэтому в
распакованном виде они нерабочие.

`scripts/build-docs-artifact.ps1` при сборке архива подменяет эти пути на
`$::iwdemo_dir` (каталог самого демо) и вставляет
`set ::iwdemo_dir [file dirname [info script]]` после `package require
Iwidgets`. Операция над **копией** в staging-дереве архива:
`build/common/iwidgets-4.1.1/demos/` не меняется, контрольные копии не нужны.
Правило и покрытые им шаблоны перечислены в `$IwRepoint`; функция
`Fix-IwidgetsDemoPaths` сверяет результат и предупреждает, если осталось
неперевязанное упоминание `iwidgets::library`.

Зачем это вообще: kit содержит только рантайм (см. `scripts/kit-prune.ps1`),
а демо публикуются пятым артефактом — значит, именно архив обязан делать их
запускаемыми.

## UUID вендора в собранных образах — правка двух makefile и одной сборки

Касается `itk` и `rl_json`; у `Img` и всех pkgs Tcl/Tk той же проблемы нет.

Оба апстрима выводят свой `*_VERSION_UUID` так:

```
printf "git-" > manifest.uuid
(cd $(srcdir); git rev-parse HEAD >> manifest.uuid || (svn …) || printf "unknown" > manifest.uuid)
```

Наше дерево вендора лежит **внутри** нашего же чекаута, поэтому `git` из
`$(srcdir)` показывает не апстрим, а **наш** коммит. Замер 2026-10-27 на
отгруженных тогда сборках: `ITK_VERSION_UUID` и `RL_JSON_VERSION_UUID` =
`git-20c39a8d…` — коммит, которого нет ни в `tcltk/itk`, ни в
`core.tcl-lang.org/itcl` (HTTP 422), и значение которого менялось бы с каждым
нашим коммитом. То есть состояние машины-сборщика попадало в публичный
бинарник.

Это не только байты в `.rdata`: строка достижима из образа. `rl_json.c`
регистрирует `rl_json::build-info`, `itkBase.c` L222-224 одалживает objProc у
`::tcl::build-info` и отдаёт свой clientData, поэтому обе команды отвечают на
`commit`:

```
tclwinkit-msvc.exe> rl_json::build-info commit
git-20c39a8de1bf9607c7d879d0e6d17f2ba35351c8      <- до правки
unknown                                            <- после
```

Лечится одной величиной: **`unknown`**. Это не наш вымысл — ровно то, что
апстримовское правило пишет, когда ни git, ни svn нет, а мы и есть такой
случай (сборка из тарбола). Плюс это делает обе цепи согласованными: до
правки msvc-itk нёс `git-20c39a8d…` (73 B заголовок), а mingw-itk — пустое
`git-` (32 B), потому что в том шелле `git` не было в PATH; две сборки
«одного и того же кита» расходились в поле, которое должно идентифицировать
вендор.

Что изменено:

| где | что |
|---|---|
| `itk-makefile.vc.patched` L145-146 | правило `$(ROOT)\manifest.uuid` вместо `copy gitmanifest.in` + `git rev-parse HEAD` пишет `echo unknown>` |
| `itk-makefile.vc.patched` L149 | `copy` на склейке заголовка получил `/b`: в текстовом режиме `copy` дописывает Ctrl-Z, и MSVC ругался `warning C5298: игнорируется некорректный символ "U+1A"` (было и до этой правки — апстримовский текст правила) |
| `rl_json/makefile.vc.patched` L55 | объявлена зависимость `rl_jsonBuildInfo.obj: ..\generic\rl_jsonUuid.h` (у апстрима в `Makefile.in` L324 она есть, в nmake-файле никогда не было — без неё nmake переиспользовал объектник и библиотека носила UUID предыдущей сборки) |
| `scripts/build-msvc-ext2.bat` L14-40 | сеет `generic/rl_jsonUuid.h` со значением `unknown` и удаляет устаревший `itk\manifest.uuid` до `nmake`; обе проверки падают сборку, если сид не сработал |
| `scripts/build-mingw-ext2.sh` L13-29 | сеет `manifest.uuid` до `make`; апстримовское правило без предпосылок его не перетирает, поэтому файлы вендора не редактируются |

Замер после правки (обе цепи, полные пересборки): `itkUuid.h` 36 B и
`rl_jsonUuid.h` 40/41 B с `unknown`, `+unknown` в склейке
(`4.2.7+unknown`, `0.17.8+unknown`), ноль вхождений нашего хэша и ноль
`git-` во всех четырёх exe, `rl_json::build-info commit` → `unknown` на всех
четырёх, `itk::build-info commit` → `unknown` на двух GUI. Апстримные UUID
при этом на месте: Tcl `ee6cca96…`, itcl `b3e5201f…`, thread `8c0237b0…`,
sqlite `0838ecb5…`, tdbc `2b9a5995…`, tdbcOdbc `4ced1c94…`, Img `988` — они
приходят внутри тарбола, и сборка их не трогает.

Провенанс и остальные следы: [`docs/SOURCES.md`](../docs/SOURCES.md),
раздел «manifest.uuid: что он на самом деле означает».
