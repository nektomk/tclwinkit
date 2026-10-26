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
| `tclwinkit-msvc.exe` | MSVC 19.51 (static CRT) | console | ~23.8 МБ |
| `winkitwish-msvc.exe` | MSVC 19.51 (static CRT) | GUI | ~29.5 МБ |
| `tclwinkit-mingw.exe` | MinGW-w64 GCC 16.1 (UCRT) | console | ~24.5 МБ |
| `winkitwish-mingw.exe` | MinGW-w64 GCC 16.1 (UCRT) | GUI | ~30.9 МБ |

Консольный exe = drop-in замена `tclsh` (те же семантики аргументов, pipe-режима
и кодов возврата) + интерактивный REPL с редактированием строки, историей и
дополнением. GUI exe = drop-in замена `wish` (сток-поведение, Tk console widget).

## Состав

| Компонент | Версия | Как подключён |
|---|---|---|
| Tcl core | 9.0.4 | статически |
| Tk | 9.0.4 | статически (GUI-exe) |
| registry / dde | 1.3.7 / 1.4.6 | статически (часть ядра) |
| Itcl | 4.3.8 | статически + `itcl4.3.8/itcl.tcl` в zip |
| Thread | 3.0.6 | статически + `thread_library/ttrace.tcl` |
| tdbc | 1.1.13 | статически + `lib/tdbc/tdbc.tcl` |
| sqlite3 | 3.53.0 | статически |
| tdbc::sqlite3 | 1.1.13 | pure Tcl (zipfs) |
| tdbc::odbc | 1.1.13 | статически + `lib/tdbc/tdbcodbc.tcl` |
| TWAPI | 5.2.0 | статически (+ dyncall 0.9) + Tcl-часть в zipfs |
| Img (tkimg) | 2.1.2 | статически: base, zlibtcl 1.3.2, pngtcl 1.6.58, jpegtcl 10.0.0, tifftcl 4.7.2, 19 форматов |
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
(`package names` показывает ~520 зарегистрированных пакетов).

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
scripts\build-msvc-kit.bat      # kit_register/kit_main/kit_wish_main + линковка exe
scripts\assemble-msvc-kit.ps1   # staging VFS -> zip -> прицеп к exe -> dist\

$env:MSYSTEM='UCRT64'
C:\msys64\usr\bin\bash.exe -lc /c/src/winkit/scripts/build-mingw-core.sh
C:\msys64\usr\bin\bash.exe -lc /c/src/winkit/scripts/build-mingw-ext.sh   # + repack-dyncall.sh
C:\msys64\usr\bin\bash.exe -lc /c/src/winkit/scripts/build-mingw-kit.sh
scripts\assemble-mingw-kit.ps1
```

Тесты:

```
dist\tclwinkit-msvc.exe tests\smoke.tcl    # и для остальных трёх exe
scripts\test-repl.ps1                      # интерактивный REPL (инъекция клавиш)
```

`tests\smoke.tcl` покрывает: версии/zipfs, registry, dde, itcl, Thread, tdbc,
sqlite3 (+round-trip), tdbc::sqlite3 (+round-trip), tdbc::odbc, http, zlib,
twapi (+COM), tcllib, CAWT, TclReadLine; в GUI — Img (PNG round-trip), tklib,
виджеты Tk.

## Структура zipfs-образа

```
//zipfs:/app/
  main.tcl              только в консольном ките: tclsh-семантика + REPL
  tcl_library/          скриптовая библиотека Tcl
  tk_library/           только GUI
  itcl4.3.8/itcl.tcl
  thread_library/ttrace.tcl
  lib/
    kit_init.tcl        бутстрап: auto_path, package ifneeded для load {},
                        алиасы имён (tkimg/img::base, Itcl/itcl, ...)
    tdbc/{tdbc.tcl,tdbcsqlite3.tcl,tdbcodbc.tcl}
    twapi/*.tcl + pkgIndex.tcl
    cawt/…
    TclReadLine/{tclreadline.tcl,pkgIndex.tcl,tclreadline-win.tcl}
    tcllib2.0/<модули>
    tklib0.9/<модули>        только GUI
```

Бинарные пакеты регистрируются в `kit_register.c` через `Tcl_StaticLibrary`
и активируются `package ifneeded <name> <ver> [list load {} <Prefix>]`
из `kit_init.tcl`.

Документация: [docs/PLAN.md](docs/PLAN.md) (техрешения и находки),
[docs/ENVIRONMENT.md](docs/ENVIRONMENT.md) (окружение),
[docs/COMPARISON.md](docs/COMPARISON.md) (MSVC vs MinGW).
