# tclwinkit

Portable single-file Tcl 9 distribution for Windows x64.

Один исполняемый файл = интерпретатор **Tcl 9.0.4** + **Tk 9.0.4** + набор
пакетов, statically linked в exe; pure-Tcl библиотеки (tcllib, tklib и Tcl-части
смешанных пакетов) прицеплены к exe ZIP-архивом через встроенный **zipfs**
(монтируется при старте в `//zipfs:/app`).

## Состав (план)

| Пакет | Версия | Тип |
|---|---|---|
| Tcl core | 9.0.4 | статически |
| Tk | 9.0.4 | статически |
| Registry / Dde | 1.3 / 1.4 | статически (часть ядра) |
| Itcl | 4.3.8 | статически (bundled) |
| Thread | 3.0.6 | статически (bundled) |
| tdbc | 1.1.13 | статически (bundled) |
| sqlite3 | 3.53.0 | статически (bundled) |
| tdbc::sqlite3 | 1.1.13 | pure Tcl (zipfs) |
| tdbc::odbc | 1.1.13 | статически (bundled) |
| tcllib / tklib | TBD | pure Tcl (zipfs) |
| TWAPI | TBD | статически + Tcl-часть в zipfs |
| Img | TBD | статически |
| CAWT | TBD | по итогам ресёрча |
| tclreadline | TBD | статически + Tcl-часть в zipfs |

## Варианты сборки

Две тулчейн-цепочки (эксперимент/сравнение), каждая даёт два exe:

| Файл | Тулчейн | Подсистема |
|---|---|---|
| `tclwinkit-msvc.exe` | MSVC 19.51 (static CRT) | console |
| `winkitwish-msvc.exe` | MSVC 19.51 (static CRT) | GUI |
| `tclwinkit-mingw.exe` | MinGW-w64 GCC 16.1 (UCRT) | console |
| `winkitwish-mingw.exe` | MinGW-w64 GCC 16.1 (UCRT) | GUI |

## Сборка

```
scripts\build-msvc-core.bat     # Tcl+Tk+pkgs статически (nmake, OPTS=static,nomsvcrt)
scripts\build-mingw-core.sh     # то же через configure/make (MSYS2 UCRT64)
scripts\build-msvc-kit.bat      # компиляция/линковка kit exe (MSVC)
scripts\build-mingw-kit.sh      # (MinGW)
scripts\assemble-msvc-kit.ps1   # staging VFS + zipfs mkzip + прицеп к exe
tests\smoke.tcl                 # смоук-тест кита
```

## Структура zipfs-образа

```
//zipfs:/app/
  tcl_library/          скриптовая библиотека Tcl (pkgIndex из manifest.txt)
  tk_library/           скриптовая библиотека Tk (только в GUI-exe)
  thread_library/       ttrace.tcl (путь, который понимает pkgIndex Thread)
  lib/
    kit_init.tcl        Tcl-бутстрап: auto_path, алиасы, pure-Tcl драйверы
    tdbc/               tdbc.tcl, tdbcsqlite3.tcl
    tcllib*/, tklib*/   установленные деревья tcllib/tklib
    twapi/ …            Tcl-части бинарных пакетов
```

Документация: [docs/ENVIRONMENT.md](docs/ENVIRONMENT.md),
[docs/PLAN.md](docs/PLAN.md).
