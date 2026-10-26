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
| Консольный exe | **23.75 МБ** | 24.46 МБ |
| GUI exe | **29.47 МБ** | 30.85 МБ |
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
  Решение: `scripts/repack-dyncall.sh` — ручной `ar rcs lib<X>_s.a *.o`
  по каталогам компонентов (46 dc*-символов).

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

## Вывод

- **MSVC** — основной вариант: чуть меньше размер, ноль CRT-зависимостей,
  официальный путь сборки Tcl под Windows, меньше ручных workaround'ов.
- **MinGW** — полностью рабочая альтернатива для тех, кому нужен открытый
  тулчейн; цена: +0.7–1.4 МБ и зависимость от UCRT-форвардеров (Win10+ они
  не заметна).
