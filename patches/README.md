# Патчи вендорных исходников

Здесь лежит **описание** правок, а не их результат. Результат живёт в
распакованных деревьях `build/<цепочка>/ext/…` и `build/common/…` и получается
скриптом:

```
scripts\unpack-vendor.ps1     # архивы vendor/  -> pristine-деревья (шаг 1)
scripts\apply-patches.ps1     # pristine-деревья -> пропатченные  (шаг 2)
```

Единственный источник истины — [`patches.json`](patches.json): 24 записи по пяти
компонентам. Каждая объявляет операции над одним файлом (нормализация EOL,
переименование идентификатора по словам целого, unified-дифф, переименование
файла) и хранит SHA-256 **исходного** (`from_sha256`) и **конечного** (`sha256`)
состояния. Апликатор сверяет оба: патч, который лёг чисто, но дал не те байты,
валится так же верно, как патч, который не лёг.

Файлы `*.patch` рядом — **производные**. `scripts\make-patches.ps1` пересчитывает
их байты и оба хеша с двух деревьев (pristine и эталонное), поэтому ни один хунк
не пишется руками, а `-Check` валит манифест, разошедшийся с исходниками. Править
`.patch` вручную бессмысленно: следующее `-Write` перезапишет его с деревьев.

Всего: **22 патча, 614 строк, 34 хунка, 21 030 байта, +228 −32, ноль CR, ноль
BOM**. Объявленных операций 25 на 24 записях (22 диффа + 2 `rename_token` +
1 `rename_file`): расхождение в одну запись даёт `rl_json/generic/rl_json.c`,
который несёт и токен, и дифф.

## Как читать это дерево

| что | где |
|---|---|
| что изменено и почему | `patches.json` → поле `note` (по-русски, на каждую запись) |
| сам дифф | `patches/<component>/<rel>.patch`, применяется `-p1` |
| порядок операций внутри записи | EOL → `rename_token` → `patch` → `rename_file` |
| какая цепочка | отсутствие `chains` = обе; `chains:["msvc"]` = только MSVC, mingw сохраняет апстримовые байты |
| контроль результата | `scripts\apply-patches.ps1 -VerifyOnly` |
| пересчёт диффов | `scripts\make-patches.ps1 -PristineRoot <pristine> [-Write|-Check]` |

Пути `file`/`patch` относительны дерева компонента из
[`scripts/vendor-layout.json`](../scripts/vendor-layout.json); сам манифест пути
дерева не повторяет — layout отвечает за «куда», `fetch-vendor.ps1` за «откуда».

Патч применяется только к дереву, которое `unpack-vendor.ps1 -VerifyOnly`
признал распакованным, и только к файлу в pristine-состоянии или уже в конечном.
Промежуточного не бывает: все изменения сначала сталятся в одноразовый каталог
вне любых репозиториев, и в дерево не попадает ничего, если хоть одна запись не
сошлась. Отказ поэтому не оставляет гибридного дерева — того единственного
состояния, которое следующий прогон не смог бы отличить от ручной правки.

## Пометки и лицензии

Правки **не** меняют лицензию исходника: модифицированный файл распространяется
под лицензией оригинала, отдельных прав мы на них не заявляем. Поэтому клауза
лицензии Tcl («modifications … need not follow the licensing terms described
here, provided that the new terms are clearly indicated on the first page of each
file where they apply») не применяется — новых терминов нет.

Шапки copyright изменённых файлов не удаляются. Где их не было у апстрима
(`rl_json.c`, `rl_jsonInt.h`, `names.c`, `scopedobject.itcl`), мы не добавляем их
и не выдумываем держателя.

Маркер `WINKIT:` (заглавами) ставится только там, где правка меняет **логику
теста** — то есть там, где читатель теста не выведет изменение из самого диффа.
Замер 2026-10-30: ровно три файла, `iwidgets/tests/{hierarchy,scrolledhtml,
scrolledtext}`. В остальном коде маркеров нет, но там, где изменение не очевидно
из диффа, в патч включён обычный комментарий строчным `winkit` — четыре файла
(`mpexpr/generic/{mpiface.c,mpparse.c}`, `rl_json/generic/rl_json.c`,
`tktreectrl/win/tkWinTree.c`), и два makefile объясняют свою правку прямо в
теле диффа. Индекс изменений — таблица ниже.

Сводная атрибуция бандла — в [`THIRD-PARTY-NOTICES.md`](../THIRD-PARTY-NOTICES.md)
(раздел «Modifications and pruning»), тексты лицензий — в [`LICENSES/`](../LICENSES/).

## rl_json 0.17.8

| файл | цепочка | правка |
|---|---|---|
| все `generic/*.c` | обе | `\bfinally\b` → `finally_label`: 256 меток goto (`finally` — ключевое слово SEH в MSVC). Объявлено операцией `rename_token`, а не диффом: 191 совпадение в `rl_json.c`, 65 в `api.c`, `remaining: 0` в обоих. Счётчики **проверяются при применении**, поэтому апстрим, который позже переименует или уберёт идентификатор, валит прогон, а не латается молча |
| `generic/rl_json.c` | обе | `#if defined(_MSC_VER)`-заглушка `mkstemp` (нет в MSVC CRT; используется только debug-командой `checkmem`) |
| `generic/rl_jsonInt.h` | обе | `__has_c_attribute(clang::suppress)` спрятан в `#if defined(__clang__)` (MSVC парсит токены даже за `&&`-guard) |
| `teabase/names.c` | обе | `unistd.h`/`clock_gettime`/`srandom`/`random` заменены Win32-эквивалентами под `#ifdef _WIN32` |
| `win/makefile.vc` | **msvc** | (1) `echo ... \>>` вместо `\>` — апстрим-баг: `>` обрезал файл и стирал TK_DIR/TK_DOTVERSION; (2) `PRJ_INCLUDES = -I"..\teabase"`, в `PRJ_OBJS` добавлены `names.obj` (teabase) и `rl_jsonBuildInfo.obj`; (3) в `PRJ_DEFINES` — конфиг-макросы (`/DENSEMBLE=0 /DDEDUP=1 /DDEBUG=0 /DUNLOAD=0`, `RL_JSON_*_INSTALL`, `RL_JSON_LIBRARY`, `RL_JSON_STUBLIB`, `RL_JSON_HEADER`) и `/Zc:preprocessor` (без него вариативный макрос `CHECK_ARGS_LABEL` раскрывается неверно → C4003/C2065); (4) объявлена зависимость `rl_jsonBuildInfo.obj: ..\generic\rl_jsonUuid.h` — у апстрима она есть в `Makefile.in`, в nmake-файле её никогда не было, поэтому nmake переиспользовал объектник и библиотека носила UUID предыдущей сборки |

`api.c` раньше не имел отдельной контрольной копии «намеренно»: правило
«все `generic/*.c`» проверялось сравнением дерева с апстримным тарболом. Теперь
он объявлен записью манифеста со своим `from_sha256`/`sha256`, то есть тем же
способом, что и остальные 23 файла, — проверка наличия файла заменена проверкой
байт.

## mpexpr 1.2

| файл | цепочка | правка |
|---|---|---|
| `generic/mpexpr.h` | обе | легаси-макросы Tcl 8.x: `_ANSI_ARGS_(x) → x`, `TCL_VARARGS_DEF(type,name) → (type name, ...)`, `TCL_VARARGS_START(type,name,ap) → (va_start(ap,name), name)`; guard'ы `CONST`/`CONST84` |
| `generic/mpparse.c` | обе | (1) `(VOID *)` → `(void *)`; (2) шим `MpBackslash` (~80 строк) + `#define Tcl_Backslash MpBackslash` под `TCL_MAJOR_VERSION > 8` — в Tcl 9 публичный `Tcl_Backslash` удалён. Блок встроен в начало файла (L25-114 пропатченного `mpparse.c`), отдельным файлом в дерево он не кладётся |
| `generic/mpiface.c` | обе | `Tcl_InitStubs` просит `"9.0"` под `TCL_MAJOR_VERSION >= 9` и `"8.6"` иначе (апстрим просил `"8.5"`); redundant `Tcl_PkgRequire(interp,"Tcl","8.5",0)` убран guard'ом `TCL_MAJOR_VERSION < 9` — на Tcl 9 он всегда падал с `version conflict for package Tcl: have 9.x, need 8.5`, а версию ядра `Tcl_InitStubs` уже гарантирует. **Этой правки не было в прежнем индексе** — запись закрывает пробел |
| `generic/zmath.h` | обе | guard'ы `CONST`/`CONST84` (zmod.c и другие включают только zmath.h, не mpexpr.h) |

Замечание: `VOID` НЕ определяется (`#define VOID void` ломает `winnt.h` — там
`#ifndef VOID` скрывает typedef'ы `CHAR`/`SHORT`).

MinGW: сборка кастомным gcc-циклом в `scripts/build-mingw-ext2.sh`
(`-fpermissive` против implicit-declaration в GCC 14+), `ar rcs bld-mingw/libmpexpr.a`.

## itk 4.2.7

| файл | цепочка | правка |
|---|---|---|
| `win/makefile.vc` | **msvc** | (1) `echo TK_DIR = \>>` и `echo TK_DOTVERSION = \>>` вместо `\>` — тот же апстрим-баг обрезания, что у rl_json (стирал ITCL_DIR); (2) правило `$(ROOT)\manifest.uuid` пишет `unknown` вместо `copy gitmanifest.in` + `git rev-parse HEAD` — см. «UUID вендора» ниже; (3) `copy` склейки заголовка получил `/b`: в текстовом режиме `copy` дописывает Ctrl-Z, и MSVC ругался `warning C5298` (было и до этой правки — апстримовский текст правила) |
| `win/rules.vc` → `win/rules.vc.own` | **msvc** | переименование файла (операция `rename_file`, не дифф): itk несёт `rules.vc` 1.19, но **без** `targets.vc` → U1052; переименованный, он не находится, и включается fallback на tcl'овский `rules.vc` 1.16. Содержимое 100 % апстримное (65 289 B) |

У mingw-дерева обратная картина: там есть `rules.vc` и нет `rules.vc.own`,
поэтому обе записи помечены `chains:["msvc"]` — mingw сохраняет апстримовые
байты. Проме́р (LF-хеши, как их считает манифест): `win/makefile.vc`
`a138f75d…` (pristine) → `11be6218…` (msvc), а `rules.vc` даёт `630639d5…`
одинаково в обеих цепочках — msvc его только переименовал, байт не менял.

## tktreectrl 2.5.1 (в образе — 2.5.2)

| файл | цепочка | правка |
|---|---|---|
| `win/tkWinTree.c` | обе | `DllMain` обёрнут в `#ifndef STATIC_BUILD`: в статическом ките `DllMain` уже определяет twapi → LNK2005/multiple definition. `thisModule` (HMODULE для `GetModuleFileNameA`) остаётся NULL — `GetModuleFileNameA(NULL)` возвращает путь exe, что для кита корректно |

Версия в образе `2.5.2`, потому что дерево берётся с ветки `main`, а не с тега;
это свойство архива, а не патча (см. `docs/SOURCES.md` о movable-формах).

## Iwidgets 4.1.1

Pure-Tcl пакет (копируется в `kit.vfs/lib/iwidgets4.1.1/` на этапе assemble),
поэтому правки применяются к дереву `build/common/iwidgets-4.1.1/` — оно одно на
обе сборки. 12 файлов: 5 runtime + 7 тестов. После фикса статики в дочерних
interp (`pkgIndex.tcl`) и Tk-ресурсов курсоров оставалось 135 падений; все
устранены, **3308/3308**.

### Runtime (`generic/`) — реальные баги под Tcl/Tk 9

| файл | правка |
|---|---|
| `colors.itcl` | `case $i \` → `switch -- $i \` (команда `case` удалена в Tcl 9). Один вызов в `hsbToRgb` → каскад давал падения во всех виджетах, использующих `iwidgets::colors::bottomShadow/topShadow` (tabnotebook, usual, …) |
| `canvasprintbox.itk` | два `case $x in {` → `switch -- $x {` (`ezPaperInfo`: размеры бумаги + ориентация). Каскад: canvasprintbox 31 F, canvasprintdialog 52 F, usual c3/c4 |
| `radiobox.itk` | `trace variable … w` → `trace add variable … write`, `trace vdelete … w` → `trace remove variable … write`. Синтаксис `trace variable` удалён в Tcl 9 → 33 F radiobox + usual c32 |
| `scopedobject.itcl` | то же в конструкторе/деструкторе (`trace add/remove variable … undef`). Scopedobject — базовый класс, поэтому починка сняла большую часть точечных падений (checkbox, combobox, hierarchy, menubar, toolbar, scrolledhtml, scrolledtext, extbutton, …) |
| `checkbox.itk`, `radiobox.itk` | `flash` теперь явно `return`: в Tk 9 `button flash` оставляет в результате имя индикаторного изображения (`::tk::icons::indicator16_…`), а документированный результат метода — пустая строка |

Порядок аргументов важен: `trace add variable NAME op CMD`, а не
`trace add NAME op CMD` (первая попытка дала `bad option
"::itcl::internal::variables::…": must be execution, command, or variable`).

### Тесты (`tests/`) — легаси-ожидания, несовместимые с Tk 9 / Windows

| файл | правка |
|---|---|
| `combobox.test` | `bad screen distance "bogus"` → `expected screen distance but got "bogus"` (Tk 9 переформулировал сообщение; 4 F) |
| `extbutton.test` | `image "bogus" doesn't exist` → `does not exist` (1 F) |
| `menubar.test`, `toolbar.test` | `-underline -1` → ожидаемый `{}`: Tk 9 хранит «нет подчёркивания» как пустое значение, а не `-1` (3 F) |
| `hierarchy.test` | `glob $env(HOME)/*` на Windows даёт пустой список (обратные слеши — экранирование), отсюда `the node doesn't exist` в Hierarchy-3.9…3.12; введён `set homedir [string map {\\ /} $env(HOME)]`, `get_files` использует ту же переменную, чтобы UID узлов совпадали байт-в-байт (4 F) |
| `scrolledtext.test`, `scrolledhtml.test` | жёстко зашитый Unix-путь `/tmp/…` в `export` → `$::iwtmp` = `[string map {\\ /} $env(TEMP)]` (2 F) |

## tkdnd 2.9.5

Патчей нет. C++-файл `TkDND_OleDND.cpp` уже имеет `extern "C"` у `Tkdnd_Init`;
при линковке gcc (не g++) добавлен `-lstdc++`. В манифесте tkdnd отсутствует —
так и должно быть: запись в индексе есть только там, где есть дифф.

## Вне манифеста: три вещи, которые делает сборка

Ниже — правки, которые **сознательно не** объявлены в `patches.json`: это
свойства сборки, а не вендорного исходника, и воспроизводятся они самой
цепочкой при каждом прогоне, а не диффом. Все три промерены в
[`docs/SOURCES.md`](../docs/SOURCES.md).

### TWAPI 5.2.0 — бинарная замена dyncall

Правок в исходниках TWAPI нет. TWAPI поставляет предсобранные библиотеки
dyncall (MSVC, динамическая CRT `/MD`), а наш кит собирается со статической CRT,
поэтому три файла перезаписываются нашими:

| файл | апстрим, B | msvc, B | mingw, B |
|---|---|---|---|
| `dyncall/dyncall-0.9/lib/release_amd64/libdyncall_s.lib` | 23 406 | 27 984 | 22 404 |
| `dyncall/dyncall-0.9/lib/release_amd64/libdyncallback_s.lib` | 7 988 | 7 646 | 8 378 |
| `dyncall/dyncall-0.9/lib/release_amd64/libdynload_s.lib` | 3 304 | 3 534 | 3 446 |

Кто делает: `scripts/build-msvc-ext.bat` L17-20 и `scripts/build-mingw-ext.sh`
L19-22 (источник замены — наш же пересобранный dyncall 0.9 из
`build/<цепочка>/ext/dyncall-0.9`). `release_x86/*.lib` не трогаются и остаются
байт-в-байт апстримными: x64 — единственная цель. Ни один `.lib` из дерева TWAPI
в образ не попадает (промер 2026-10-27: в `build/msvc/kit/stage/` ноль файлов
`*.lib`).

Лицензия dyncall (ISC-подобная, требует сохранить текст авторства) — в
[`LICENSES/dyncall/LICENSE`](../LICENSES/dyncall/LICENSE); она относится к
нашему пересобранному коду, а не к перезаписанным бинарникам.

### UUID вендора в собранных образах

Касается `itk` и `rl_json`; у `Img` и всех pkgs Tcl/Tk той же проблемы нет. Оба
апстрима выводят свой `*_VERSION_UUID` так:

```
printf "git-" > manifest.uuid
(cd $(srcdir); git rev-parse HEAD >> manifest.uuid || (svn …) || printf "unknown" > manifest.uuid)
```

Наше дерево вендора лежит **внутри** нашего же чекаута, поэтому `git` из
`$(srcdir)` показывает не апстрим, а **наш** коммит. Замер 2026-10-27 на
отгруженных тогда сборках: `ITK_VERSION_UUID` и `RL_JSON_VERSION_UUID` =
`git-20c39a8d…` — коммит, которого нет ни в `tcltk/itk`, ни в
`core.tcl-lang.org/itcl` (HTTP 422), и значение которого менялось бы с каждым
нашим коммитом. То есть состояние машины-сборщика попадало в публичный бинарник.
Это не только байты в `.rdata`: строка достижима из образа — `rl_json.c`
регистрирует `rl_json::build-info`, `itkBase.c` L222-224 одалживает objProc у
`::tcl::build-info`, поэтому обе команды отвечают на `commit`.

Лечится одной величиной: **`unknown`**. Это не наш вымысел — ровно то, что
апстримовское правило пишет, когда ни git, ни svn нет, а мы и есть такой случай
(сборка из тарбола). Плюс это делает обе цепи согласованными: до правки
msvc-itk нёс `git-20c39a8d…` (73 B заголовок), а mingw-itk — пустое `git-`
(32 B), потому что в том шелле `git` не было в PATH.

| где | что |
|---|---|
| `patches/itk/win/makefile.vc.patch` | правило `$(ROOT)\manifest.uuid` пишет `echo unknown>` вместо `copy gitmanifest.in` + `git rev-parse HEAD` (это уже патч вендора, а не действие сборки) |
| `scripts/build-msvc-ext2.bat` L14-40 | сеет `generic/rl_jsonUuid.h` со значением `unknown` и удаляет устаревший `itk\manifest.uuid` до `nmake`; обе проверки падают сборку, если сид не сработал |
| `scripts/build-mingw-ext2.sh` L13-29 | сеет `manifest.uuid` до `make`; апстримовское правило без предпосылок его не перетирает, поэтому файлы вендора не редактируются |

Замер после правки (обе цепи, полные пересборки): `itkUuid.h` 36 B и
`rl_jsonUuid.h` 40/41 B с `unknown`, `+unknown` в склейке (`4.2.7+unknown`,
`0.17.8+unknown`), ноль вхождений нашего хэша и ноль `git-` во всех четырёх exe,
`rl_json::build-info commit` → `unknown` на всех четырёх, `itk::build-info
commit` → `unknown` на двух GUI. Апстримные UUID при этом на месте: Tcl
`ee6cca96…`, itcl `b3e5201f…`, thread `8c0237b0…`, sqlite `0838ecb5…`, tdbc
`2b9a5995…`, tdbcOdbc `4ced1c94…`, Img `988` — они приходят внутри тарбола, и
сборка их не трогает. Провенанс и остальные следы —
[`docs/SOURCES.md`](../docs/SOURCES.md), раздел «manifest.uuid: что он на самом
деле означает».

### Демо iwidgets в docs-архиве

Демо-скрипты (`demos/extbutton`, `hyperhelp`, `mainwindow`, `scrolledhtml`,
`scrolledtext`, `toolbar`) берут картинки/справку из
`$iwidgets::library/demos/...`. В ките эта переменная указывает внутрь zipfs
(`//zipfs:/app/lib/iwidgets4.1.1`), где демо намеренно нет, поэтому в
распакованном виде они нерабочие. `scripts/build-docs-artifact.ps1` при сборке
архива подменяет эти пути на `$::iwdemo_dir` (каталог самого демо) и вставляет
`set ::iwdemo_dir [file dirname [info script]]` после `package require Iwidgets`.
Операция над **копией** в staging-дереве архива:
`build/common/iwidgets-4.1.1/demos/` не меняется. Правило и покрытые им шаблоны
перечислены в `$IwRepoint`; функция `Fix-IwidgetsDemoPaths` сверяет результат и
предупреждает, если осталось неперевязанное упоминание `iwidgets::library`.

Зачем это вообще: kit содержит только рантайм (см. `scripts/kit-prune.ps1`), а
демо публикуются пятым артефактом — значит, именно архив обязан делать их
запускаемыми.

## Чего здесь больше нет

Раньше в `patches/` лежали **контрольные копии** пропатченных файлов — 25 файлов
чужих исходников с нашими правками (10 `*.patched`, 2 `*.orig`, 12 файлов
iwidgets без расширения и мёртвый `mpexpr/backslash-shim.c`; 486 644 байта,
475,2 КиБ). Идея была «при пересоздании деревьев скопируйте их поверх
оригиналов». От этого отказались в пользу диффов, и не ради экономии места:

- **нельзя было увидеть, что изменено.** 25 файлов исходников не отвечали на
  вопрос «какая правка и зачем», а `patches/README.md` был единственным индексом
  и расходился с ними;
- **нельзя было проверить применение.** Копия либо лежит поверх оригинала, либо
  нет; промежуточное состояние и частично скопированное дерево выглядели
  нормально. Теперь каждое состояние проверяется хешем, а отказ апликатора не
  пишет в дерево ничего;
- **копии сохраняли дефекты.** Из 24 снапшотов, соответствующих записям
  манифеста, 22 побайтово равны тому, что манифест вычисляет с деревьев сегодня.
  Два — `rl_json.c.patched` и `rl_jsonInt.h.patched` — не равны: в них лежал
  mojibake, 56 апстримовых UTF-8 байт, прогнанных через машинную ANSI-кодстр.
  Дифф, снятый с этих копий, заморозил бы повреждение в git как эталон. Мёртвый
  `backslash-shim.c` — третий случай: его содержимое (~80 строк шима
  `MpBackslash`) встроено в `mpparse.c`, потребителей у отдельного файла не было
  ни в одной цепочке (промер 2026-10-30: 0 упоминаний в 34/32 файлах дерева,
  0 в скриптах сборки).

Pristine-байты для диффа берёт не каталог `patches/`, а `vendor/` через
`unpack-vendor.ps1 -Force`: сохранённая копия оригинала была вторым,
непроверяемым источником истины. Именно поэтому `-Force` обязан пересобирать и
**помеченное** дерево — в шаге 1 он этого не делал (early-skip шёл до проверки
флага), и без этой правки шаг 2 был нерабочим: обратно в pristine состояние
попасть было нельзя. Исправлено в `7f85dd2`. `CHANGELOG.md` этого не касается:
он про образы и команды, а не про сборочную цепочку.
