# tclwinkit

Portable single-file Tcl 9 distribution for Windows x64.

Один исполняемый файл = интерпретатор **Tcl 9.0.4** (+ **Tk 9.0.4** в GUI-варианте)
+ бинарные расширения, статически влинкованные в exe, + pure-Tcl библиотеки
(tcllib, tklib, Tcl-части смешанных пакетов), прицепленные к exe ZIP-архивом
через встроенный **zipfs** (монтируется при старте в `//zipfs:/app`).
Никаких DLL beside exe, никаких установщиков — скопировал файл и работаешь.

## Готовые файлы (`dist/`)

| Файл | Тулчейн | Подсистема | Размер |
|---|---|---|---|
| `tclwinkit-msvc.exe` | MSVC 19.51 (static CRT) | console | ~10.8 МБ |
| `winkitwish-msvc.exe` | MSVC 19.51 (static CRT) | GUI | ~15.9 МБ |
| `tclwinkit-mingw.exe` | MinGW-w64 GCC 16.1 (UCRT) | console | ~11.6 МБ |
| `winkitwish-mingw.exe` | MinGW-w64 GCC 16.1 (UCRT) | GUI | ~17.9 МБ |
| `tclwinkit-docs-<вер>.zip` | — | документация, маны, демо | ~13.4 МБ |

Консольный exe = drop-in замена `tclsh` (те же семантики аргументов, pipe-режима
и кодов возврата) + интерактивный REPL с редактированием строки, историей и
дополнением. GUI exe = drop-in замена `wish` (сток-поведение, Tk console widget).

В киты сознательно не кладётся ничего, кроме рантайма: справочные страницы,
HTML-документация, демонстрационные программы и тестовые наборы пакетов вырезаны
из staging-образа (`scripts\kit-prune.ps1`) и публикуются пятым артефактом —
`dist\tclwinkit-docs-<вер>.zip` (`scripts\build-docs-artifact.ps1`). Внутри —
`man/` (nroff-страницы по пакетам), `html/` (tcllib/tklib/twapi/cawt/…),
`demos/` (Tk, iwidgets, itk, treectrl, tkdnd, cawt), `docs/`, `licenses/`,
`tools/` (рендер ман без groff и обёртка для iwidgets-дем) плюс `VERSIONS.txt`
и `MANIFEST.txt`. Распаковав архив, демо запускаются теми же exe:

```
winkitwish-msvc.exe demos\tk\widget           # браузер демо Tk
winkitwish-msvc.exe demos\iwidgets\catalog    # браузер демо iwidgets
tclwinkit-msvc.exe  tools\man.tcl man\tcl\subst.n
```


## Состав

| Компонент | Версия | Как подключён |
|---|---|---|
| Tcl core | 9.0.4 | статически |
| Tk | 9.0.4 | статически (GUI-exe) |
| registry / dde | 1.3.7 / 1.4.6 | статически (часть ядра) |
| Itcl | 4.3.8 | статически + `itcl4.3.8/itcl.tcl` в zip |
| Itk | 4.2.7 | статически + `itk4.2.7/` в zip (GUI-exe) |
| Iwidgets | 4.1.1 | pure Tcl (zipfs, GUI-exe) |
| Thread | 3.0.6 | статически + `thread_library/ttrace.tcl` |
| tdbc | 1.1.13 | статически + `lib/tdbc/tdbc.tcl` |
| sqlite3 | 3.53.0 | статически |
| tdbc::sqlite3 | 1.1.13 | pure Tcl (zipfs) |
| tdbc::odbc | 1.1.13 | статически + `lib/tdbc/tdbcodbc.tcl` |
| TWAPI | 5.2.0 | статически (+ dyncall 0.9) + Tcl-часть в zipfs |
| Img (tkimg) | 2.1.2 | статически: base, zlibtcl 1.3.2, pngtcl 1.6.58, jpegtcl 10.0.0, tifftcl 4.7.2, 19 форматов |
| rl_json | 0.17.8 | статически (обе сборки; `rl_json::json get/set/...`) |
| mpexpr | 1.2 | статически (обе сборки; команды `mpexpr`, `mpformat`) |
| tkdnd | 2.9.5 | статически + Tcl-часть в zipfs (GUI-exe; drag-and-drop) |
| Treectrl | 2.5.2 | статически + `lib/treectrl2.5.2/` в zipfs (GUI-exe) |
| tcllib | 2.0 | pure Tcl (zipfs) |
| tklib | 0.9 | pure Tcl (zipfs, GUI-exe) |
| CAWT | 3.1.1 | pure Tcl (zipfs) |
| TclReadLine | 1.1 | pure Tcl (zipfs) + Win32-shim |

## Использование

```tcl
tclwinkit-msvc.exe script.tcl arg1 arg2   ;# как tclsh
type cmds.tcl | tclwinkit-msvc.exe        ;# stdin-режим (как tclsh)
tclwinkit-msvc.exe                        ;# интерактивный REPL
winkitwish-msvc.exe app.tcl               ;# как wish
winkitwish-msvc.exe                       ;# GUI + Tk console widget
```

### Иконка в трее (свернуть приложение)

winico в кит не входит — его полностью покрывает TWAPI:

```tcl
package require twapi
wm withdraw .                                   ;# спрятать главное окно
set hico [twapi::load_icon_from_file myapp.ico] ;# свой .ico -> HICON
# системная иконка: HICON_SHARED, нужен каст и без free_icon:
# set hico [twapi::cast_handle [twapi::load_icon_from_system INFORMATION] HICON]
set id [twapi::systemtray::addicon $hico [list show]]
twapi::systemtray::modifyicon $id -tip "Моё приложение"
proc show {args} { wm deiconify . }             ;# клик по иконке — показать окно
# twapi::systemtray::modifyicon $id -balloon "Готово" -balloontitle "Статус"
# twapi::systemtray::removeicon $id             ;# убрать иконку
# twapi::free_icon $hico                        ;# только для load_icon_from_file
```


### REPL (консольный кит)

Чистый Tcl (TclReadLine 1.1) + Win32-shim на TWAPI (`tclreadline-win.tcl`):
посимвольный ввод через `ReadConsoleInput`, ANSI-рендеринг через
VirtualTerminalProcessing (Windows 10+).

| Клавиша | Действие |
|---|---|
| Up / Down | история |
| Left / Right, Home / End, Del | редактирование строки |
| Ctrl-A/E/K/U/W, Ctrl-P/N | emacs-шорткаты |
| Ctrl-C | очистить текущую строку (в режиме ввода) |
| Shift-Tab | дополнение (команды, переменные, файлы) |
| Ctrl-T | вкл/выкл дополнение по простому Tab |
| Ctrl-D (на пустой строке), `exit` | выход (история сохраняется) |

История: `~/.tclline_history`, rc-файл REPL: `~/.tcllinerc`;
общий rc-файл кита (как tclshrc): `~/winkitrc.tcl` (консоль) /
`~/winkitwishrc.tcl` (GUI).

Проверка в REPL: `package require` любого пакета из таблицы выше
(`package names` показывает 523 зарегистрированных пакета).

## Портируемость

- Зависимости всех четырёх exe — только системные DLL Windows
  (`objdump -p` / `dumpbin /dependents`).
- MSVC-вариант: статический CRT (`OPTS=nomsvcrt`) — вообще ни одной CRT-DLL.
- MinGW-вариант: `-static` + UCRT-форвардеры `api-ms-win-crt-*`
  (встроены в Windows 10+; на Windows 7/8 нужен KB2999226/KB3118401).
- Проверено: запуск из read-only каталога — SMOKE OK.

## Сборка с нуля

Порядок (Windows x64; MSVC = VS Build Tools + Windows SDK, MinGW = MSYS2 UCRT64):

```
scripts\build-msvc-core.bat     # Tcl+Tk+pkgs: nmake OPTS=static,nomsvcrt
scripts\build-msvc-ext.bat      # dyncall 0.9 + TWAPI 5.2.0 (MSVC)
scripts\build-msvc-img.bat      # Img 2.1.2: base, support, 19 форматов
scripts\build-msvc-ext2.bat     # rl_json, mpexpr, itk, tkdnd, treectrl (MSVC)
scripts\build-msvc-kit.bat      # kit_register/kit_main/kit_wish_main + линковка exe
scripts\assemble-msvc-kit.ps1   # staging VFS -> zip -> прицеп к exe -> dist\

$env:MSYSTEM='UCRT64'
C:\msys64\usr\bin\bash.exe -lc /c/src/winkit/scripts/build-mingw-core.sh
C:\msys64\usr\bin\bash.exe -lc /c/src/winkit/scripts/build-mingw-ext.sh   # + repack-dyncall.sh
C:\msys64\usr\bin\bash.exe -lc /c/src/winkit/scripts/build-mingw-ext2.sh  # rl_json, mpexpr, itk, tkdnd, treectrl
C:\msys64\usr\bin\bash.exe -lc /c/src/winkit/scripts/build-mingw-kit.sh
scripts\assemble-mingw-kit.ps1

scripts\build-docs-artifact.ps1 # 5-й артефакт: docs/man/demos -> dist\tclwinkit-docs-<вер>.zip
```

`assemble-*.ps1` staging-образ чистит через `scripts\kit-prune.ps1` (см. выше):
в kit.vfs попадают только рантайм-файлы. Пятый артефакт собирается из деревьев
`build\msvc|mingw|common`, поэтому запускать его нужно после обеих сборок.

Тесты:

```
dist\tclwinkit-msvc.exe tests\smoke.tcl    # и для остальных трёх exe
dist\tclwinkit-msvc.exe tests\tcllib-probe.tcl   # и для остальных трёх exe
scripts\test-repl.ps1                    # интерактивный REPL (инъекция клавиш)
```

`tests\smoke.tcl` покрывает: версии/zipfs, registry, dde, itcl, Thread, tdbc,
sqlite3 (+round-trip), tdbc::sqlite3 (+round-trip), tdbc::odbc, http, zlib,
twapi (+COM, +иконка в трее), rl_json (+round-trip), mpexpr (2**100), tcllib,
CAWT, TclReadLine; в GUI — Img (PNG round-trip), tklib, виджеты Tk, Itk,
Iwidgets (entryfield), tkdnd (drop/drag target), Treectrl (виджет+колонки),
плюс 6 проверок статики в дочерних интерпретаторах (`thread create
{package require sqlite3}`, slave/safe interp).

`tests\tcllib-probe.tcl` — регрессионный страж рантайм-только staging:
грузит каждый пакет tcllib/tklib, который образ предлагает, и сверяет отказы
со снимком неприбранного дерева (`tests\tcllib-probe.baseline.txt`,
пересобирается стоковым tclsh: `tclsh90s.exe tests\tcllib-probe.tcl -baseline`).
Так апстримовый шум (tdom/tls/critcl/Trf/xml/nx, битый `nettool/nextool.tcl`,
дубли версий) не может ни замаскировать, ни имитировать регрессию.

## Структура zipfs-образа

```
//zipfs:/app/
  main.tcl              только в консольном ките: tclsh-семантика + REPL
  tcl_library/          скриптовая библиотека Tcl
  tk_library/           только GUI
  itcl4.3.8/itcl.tcl
  itk4.2.7/             только GUI: itk.tcl + Archetype/Widget/Toplevel.itk
  thread_library/ttrace.tcl
  lib/
    pkgIndex.tcl       физический индекс ВСЕХ static/mixed-пакетов: его находит
                       tclPkgUnknown в любом (в т.ч. дочернем) interp, т.к.
                       init.tcl кладёт //zipfs:/app на auto_path каждого interp
    kit_init.tcl       бутстрап: source pkgIndex.tcl + tcl::tm::path,
                       алиасы имён (tkimg/img::base, Itcl/itcl, Itk/itk, ...)
    tdbc/{tdbc.tcl,tdbcsqlite3.tcl,tdbcodbc.tcl}
    twapi/*.tcl + pkgIndex.tcl
    cawt/…
    TclReadLine/{tclreadline.tcl,pkgIndex.tcl,tclreadline-win.tcl}
    tcllib2.0/<модули>      только рантайм-файлы (см. kit-prune.ps1)
    tklib0.9/<модули>       только GUI, то же самое
    iwidgets4.1.1/           только GUI: iwidgets.tcl + generic/ (~50 классов)
    tkdnd2.9.5/              только GUI: 7 Tcl-скриптов tkdnd
    treectrl2.5.2/           только GUI: treectrl.tcl, filelist-bindings.tcl
```

Бинарные пакеты регистрируются в `kit_register.c` через `Tcl_StaticLibrary`
и активируются `package ifneeded <name> <ver> [list load {} <Prefix>]`
из `pkgIndex.tcl`.

Из tcllib2.0/tklib0.9 в образ попадают только файлы, которые интерпретатор
действительно читает при `package require`/автозагрузке: каталоги `tests`,
`doc`, `html`, `demos`, `examples`, `figures`, `perf`, `build`, `test-assets`
и расширения `.test .man .n .3 .md .txt .html .png .csv .xz .c .h …` вырезаны
`scripts\kit-prune.ps1` (−32,4 МБ и −4276 файлов на GUI-кит). Всё вырезанное
публикуется пятым артефактом. Целостность образа проверяет
`tests\tcllib-probe.tcl` (см. «Тесты»).

Документация: [docs/PLAN.md](docs/PLAN.md) (техрешения и находки),
[docs/ENVIRONMENT.md](docs/ENVIRONMENT.md) (окружение),
[docs/COMPARISON.md](docs/COMPARISON.md) (MSVC vs MinGW),
`src/docs/README.md` (состав и использование docs-архива),
`patches/README.md` (правки вендора).
