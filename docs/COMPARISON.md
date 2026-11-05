# MSVC vs MinGW-w64: сравнение сборок tclwinkit

Обе цепочки собирают идентичный набор компонентов и проходят один и тот же
smoke-тест (25+ проверок) и интерактивный REPL-тест. Различия — в способе
сборки, размере и зависимостях.

## Итоги

| | MSVC | MinGW-w64 |
|---|---|---|
| Компилятор | cl.exe 19.51 (VS 18 Build Tools) | GCC 16.1.0 (MSYS2 UCRT64) |
| Сборка ядра | `nmake -f makefile.vc OPTS=static,nomsvcrt` | `configure --disable-shared && make` |
| Имена стат. библиот | суффикс `X` (`tcl90sx.lib`, `*sx.lib`) | `libtcl90.a`, `libtcl9tk90.a`, `libtcl9*.a` |
| Консольный exe | **10.75 МБ** | 11.62 МБ |
| GUI exe | **15.85 МБ** | 17.88 МБ |
| CRT | статический, без CRT-DLL (`nomsvcrt`) | статический (`gcc -static`), но остаются форвардеры `api-ms-win-crt-*` (UCRT) |
| Зависимости exe | только Win32 system DLL | system DLL + 12–13 × `api-ms-win-crt-*` |
| Совместимость | Windows x64 (CRT встроен в компилятор) | Win10+ из коробки; Win7/8 — нужен UCRT update (KB2999226/KB3118401) |
| Линковка системных библиот | автоматически: `#pragma comment(lib,...)` в исходниках TWAPI | вручную: потребовались `-ltdh -luuid` (GCC игнорирует `#pragma comment`) |
| Unicode-вход | `_tmain`/TCHAR из коробки | нужен `-municode` (`wmain`/`wWinMain`) |

## Найденные различия/грабли по компонентам

### Img 2.1.2 — имя базового пакета
- nmake-сборка (MSVC): `PACKAGE_TCLNAME=tkimg` → `Tkimg_Init` предоставляет
  пакет **`tkimg`**.
- TEA/configure-сборка (MinGW): base configure ставит `PACKAGE_TCLNAME=img::base`
  → предоставляет **`img::base`**; сгенерированные stub-библиотеки форматов
  требуют `img::base` (внутренне согласованно).
- Решение: `kit_init.tcl` регистрирует `package ifneeded` для **обоих** имён —
  скрипт грузит `load {} Tkimg` один раз и допредоставляет то имя, которое
  C-init не выдал. Работает на обеих цепочках без пересборки Img.

### dyncall 0.9 (нужен TWAPI)
- MSVC: `dynmake.bat` / nmake — собирается без проблем.
- MinGW: правило `ar -rv lib*_s.a` в `dynMakefile` получает пустой список
  объектов → архивы по 8 байт (undefined dc* symbols при линковке).
  Решение: `scripts/repack-dyncall.sh` — `ar rcs lib<X>_s.a *.o` по каталогам
  компонентов (46 dc*-символов). `build-mingw-ext.sh` замеряет число объектов в
  каждом из трёх архивов сразу после сборки dyncall, зовёт этот скрипт, если
  хоть один пуст, и затем проверяет и число объектов, и наличие экспортируемых
  `dc*` — поэтому ручной шаг больше не нужен. Отдельно запускать имеет смысл
  только для дерева, собранного руками или прерванного на середине.

### TWAPI 5.2.0
- Обе цепочки: `--disable-shared`/`OPTS=static`; сгенерированный pkgIndex.tcl
  сам фолбэчится на `load {} Twapi`. Требует `-I<tcl>/libtommath`.
- MSVC: tdh/uuid подтягиваются `#pragma comment(lib)`; MinGW: добавлены явно.

### Линковка kit-exe
- MSVC: список `*sx.lib` + `*stub.lib` один раз достаточно.
- MinGW: циклические зависимости архивов → список архивов на командной строке
  линковщика **удваивается**; `-static -municode -Wl,--stack,2300000`;
  GUI: `-mwindows`.

### Поведение одинаково
- zipfs-прицеп (конкатенация exe+zip) работает идентично.
- Все `package require` проходят; sqlite/tdbc/twapi(+COM)/http/Img(PNG)/tklib —
  SMOKE OK на всех четырёх exe.
- REPL (TclReadLine + win32-shim): история, стрелки, Shift-Tab-дополнение —
  OK на обеих цепочках.

## Вторая волна: rl_json, mpexpr, Itk, Iwidgets, tkdnd, Treectrl

Сборка (`build-*-ext2`), различия по цепочкам:

### rl_json 0.17.8
- MSVC: nmake `OPTS=static,nomsvcrt`; потребовались `/Zc:preprocessor`,
  конфиг-макросы в PRJ_DEFINES, переименование меток `finally`→`finally_label`
  (SEH), включение teabase/names.c и rl_jsonBuildInfo.c в PRJ_OBJS,
  вручную сгенерированный `rl_jsonUuid.h` в `generic/`, заглушка `mkstemp`.
- MinGW: TEA configure, но пробы `Tcl_GetBytesFromObj`/`Tcl_GetNumberFromObj`
  misdetect'ятся (системный tcl.h 8.6 из /ucrt64/include + линковка на stubs)
  → явные `CPPFLAGS="-I$TCL/generic -I$TCL/win" LIBS="-L$TCL/win -ltcl90"`.
  Сборка только in-tree (`-Iteabase` относителен). Doc-цель требует pandoc
  (отсутствует) → `make || true` + контроль наличия архива.
- Итог идентичен: `rl_json::json` (NR-команда, ENSEMBLE=0), 0.17.8.

### mpexpr 1.2
- Обе цепочки: легаси-макросы Tcl 8.x (`_ANSI_ARGS_`, `TCL_VARARGS_*`) в
  mpexpr.h, CONST-guard'ы в zmath.h, шим `Tcl_Backslash` (в Tcl 9 удалён).
- MSVC: nmake makefile.vc из тарбола после макросов собрался.
- MinGW: штатные сценарии не сработали → кастомный gcc-цикл
  (`-fpermissive`, `-std=gnu17`) + `ar rcs libmpexpr.a`.
- `VOID` не определяли: `#define VOID void` ломает winnt.h в MinGW.

### Itk 4.2.7
- MSVC: свой rules.vc 1.19 без targets.vc → переименован (fallback на tcl 1.16);
  апстрим-баг `\>` в makefile.vc (затирал ITCL_DIR) → `\>>`; ITCL_DIR —
  junction на pkgs/itcl4.3.8.
- MinGW: TEA configure `--with-itcl=$ITCLDIR` (из itclConfig.sh) — без правок.

### tkdnd 2.9.5
- C++ (OleDND.cpp, extern "C" у Tkdnd_Init). MSVC: nmake static. MinGW:
  configure --disable-shared; линковка кита идёт gcc → добавлен `-lstdc++`.

### Treectrl 2.5.2 (директория tktreectrl-2.5.1)
- Обе: `DllMain` в tkWinTree.c под `#ifndef STATIC_BUILD` (конфликт с twapi).
- MSVC nmake static; MinGW configure из bld/.

### Iwidgets 4.1.1 — pure Tcl, цепочки не касаются
- Источник — Debian-тарбол исходников (решение A7, обоснование и дигест:
  [SOURCES.md](SOURCES.md), замечание: [PLAN.md](PLAN.md));
  `iwidgets.tcl` генерится на стадии сборки из `.in`;
  классы autoload из `generic/tclIndex`.

## Вывод

- **MSVC** — основной вариант: чуть меньше размер, ноль CRT-зависимостей,
  официальный путь сборки Tcl под Windows, меньше ручных workaround'ов.
- **MinGW** — полностью рабочая альтернатива для тех, кому нужен открытый
  тулчейн; цена: +0,9 МБ (консоль) / +2,0 МБ (GUI) и зависимость от
  UCRT-форвардеров (Win10+ они не заметна).
- Разница — только в коде/CRT: zipfs-образ (`kit.vfs`) после
  `scripts\kit-prune.ps1` у цепочек идентичен по составу (tcllib2.0 905 файлов,
  tklib0.9 307 файлов — включая обязательные лицензионные тексты, которые
  prune сохраняет по имени файла), поэтому и пятый артефакт
  (`tclwinkit-docs-<вер>.zip`, 13,57 МБ) один на обе сборки: он собирается из
  деревьев `build\common|msvc|mingw` и запускается любым из четырёх exe.
