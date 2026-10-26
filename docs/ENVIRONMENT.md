# tclwinkit — обследование окружения

Дата: 2026-10-26. Хост: Windows 11 IoT Enterprise LTSC (build 26100), x64.
Ресурсы: 16 ядер CPU, 16 ГБ RAM, ~42 ГБ свободно на C:.

## Цель проекта

`tclwinkit` — один portable-исполняемый файл для Windows, содержащий:

- интерпретатор Tcl 9 (zipfs встроен в ядро — пакеты монтируются из ZIP, прицепленного к exe);
- Tk 9 и набор расширений, достаточный для комфортной работы;
- не требует установки и внешних зависимостей.

Рабочая директория проекта: `C:\src\winkit`.

## Компиляторы (проверены тестовой компиляцией)

| Инструмент | Версия | Расположение | Статус |
|---|---|---|---|
| MSVC cl.exe (x64) | 19.51.36260 (VS 18 Build Tools) | `C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools\VC\Tools\MSVC\14.51.36231` | работает (через `vcvars64.bat`) |
| MinGW-w64 gcc (UCRT) | 16.1.0 Rev5 | `C:\msys64\ucrt64\bin` | работает |
| Windows SDK | 10.0.26100 (rc.exe, lib) | `C:\Program Files (x86)\Windows Kits\10` | есть |

Обе цепочки x64. MSVC — официально основной путь сборки Tcl под Windows
(`win/makefile.vc` + nmake); MinGW — альтернатива (configure/`win/Makefile.in`).

## Средства сборки

| Инструмент | Версия | Примечание |
|---|---|---|
| nmake | MSVC 14.51 | через vcvars64 |
| cmake | 4.3.3 | ucrt64 |
| ninja | ucrt64 | |
| GNU make | 4.4.1 | `C:\msys64\usr\bin` (MSYS-вариант) |
| ccache | 4.13.6 | ucrt64, ускорение пересборок |
| binutils (ar, strip, dlltool, windres) | 2.46 | ucrt64 |
| git | 2.49.0 | доступен GitHub-зеркало Tcl (`github.com/tcltk/*`) |
| 7-Zip | 26.01 | ucrt64 |
| curl | 8.20.0 | ucrt64 + системный |
| Python | 3.14.7 | `C:\Python314` |
| Node.js | установлен | вспомогательно |

## Tcl в системе

- MSYS2 ucrt64: **tcl/tk 8.6.18** (tclsh, wish) — годится только как bootstrap-инструмент;
  есть команда `zlib`, нет `zipfs` (появился в 8.7/9.0), нет `vfs::zip`.
- Установленного Tcl 9 на диске нет — будем собирать из исходников.
- zlib 1.3.2 в ucrt64 (в исходниках Tcl zlib всё равно встроен в `pkgs/`).

## Доступные версии Tcl/Tk 9 (SourceForge + зеркало GitHub)

- Серия 9.0.x: 9.0.0 … **9.0.4** (стабильная patch-ветка)
- **9.1.0** — свежий минорный релиз (теги `core-9-1-0` у tcl и tk)
- Интернет-доступ: github.com — OK, sourceforge.net — OK.

## Заметки к плану сборки

1. Ядро Tcl 9 собирается со статическими опциями; `zipfs` позволяет прицепить
   ZIP с pure-Tcl пакетами (tcllib, tklib) прямо к exe — механизм «одного файла»
   без старпак-магии 8.x.
2. Бинарные расширения (Thread, tdbc::sqlite3, TWAPI, Img, tcltls…) для
   truly-single-file нужно линковать статически в exe, т.к. DLL из zipfs не грузятся.
3. Подсистема exe (console vs windows) — одна на файл; консольный вариант
   (tclsh-стиль) сохраняет отладочный вывод, Tk-окна при этом работают.

## Итоговый статус (2026-10-26)

Проект собран и проверен полностью:

- `dist/`: tclwinkit-msvc.exe (23.75 МБ), winkitwish-msvc.exe (29.47 МБ),
  tclwinkit-mingw.exe (24.46 МБ), winkitwish-mingw.exe (30.85 МБ).
- `tests/smoke.tcl` — SMOKE OK на всех четырёх exe (~25 проверок: версии,
  zipfs, все package require, sqlite/tdbc round-trips, thread, itcl, registry,
  twapi+COM, http, zlib, tcllib, CAWT, TclReadLine; GUI: Img PNG, tklib,
  виджеты Tk).
- `scripts/test-repl.ps1` — интерактивный REPL (TclReadLine + Win32-shim):
  история, стрелки, Shift-Tab-дополнение, exit 0 — OK на MSVC и MinGW.
- Портируемость: зависимости — только системные DLL (MSVC без CRT-DLL;
  MinGW — UCRT api-ms-win-crt-*, Win10+); запуск из read-only каталога OK;
  GUI-exe без аргументов живут в event loop.
- Подробности техрешений: PLAN.md; сравнение цепочек: COMPARISON.md.
