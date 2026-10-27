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

## rl_json 0.17.8 (`rl_json/`)

| Файл | Правка |
|---|---|
| `rl_jsonInt.h` | `__has_c_attribute(clang::suppress)` спрятан в `#if defined(__clang__)` (MSVC парсит токены даже за `&&`-guard) |
| `rl_json.c` | `#if defined(_MSC_VER)`-заглушка `mkstemp` (нет в MSVC CRT; используется только debug-командой `checkmem`) |
| `names.c` | teabase: `unistd.h`/`clock_gettime`/`srandom`/`random` заменены Win32-эквивалентами под `#ifdef _WIN32` |
| `makefile.vc` | (1) `echo ... \>>` вместо `\>` — апстрим-баг: `>` обрезал файл и стирал ITCL_DIR-подобные строки, здесь TK_DIR/TK_DOTVERSION; (2) `PRJ_INCLUDES = -I"..\teabase"`, в PRJ_OBJS добавлены `names.obj` (teabase) и `rl_jsonBuildInfo.obj`; (3) `PRJ_DEFINES`: конфиг-макросы `/DENSEMBLE=0 /DDEDUP=1 /DDEBUG=0 /DUNLOAD=0 /DRL_JSON_LIBRARY_PATH_INSTALL=... /DRL_JSON_LIBRARY=... /DRL_JSON_STUBLIB=... /DRL_JSON_HEADER=...` и `/Zc:preprocessor` (без него вариативный макрос CHECK_ARGS_LABEL раскрывается неверно → C4003/C2065) |
| все `generic/*.c` | `\bfinally\b` → `finally_label` (256 меток goto: `finally` — ключевое слово SEH в MSVC) |
| — | в `generic/` скопирован сгенерированный configure `rl_jsonUuid.h` (в тарболе только `.h.in`; MinGW генерирует сам, MSVC-сборке кладём вручную) |

`rl_jsonInt.h.orig` / `makefile.vc.orig` — исходники для diff.

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
