# tclwinkit — план сборки (обновлён по результатам ресёрча)

## Конфигурация (согласовано с заказчиком)

| Параметр | Значение |
|---|---|
| Ядро | Tcl 9.0.4 + Tk 9.0.4 (x64) |
| Цепочки | **MSVC 19.51** и **MinGW-w64 GCC 16.1** (обе, для сравнения) |
| Исполняемые файлы | на каждую цепочку: консольный `tclwinkit.exe` + GUI `winkitwish.exe` |
| Pure-Tcl пакеты | tcllib 2.0, tklib 0.9, CAWT 3.1.1, TclReadLine (в zipfs) |
| Бинарные пакеты (статически) | Itcl 4.3.8, Thread 3.0.6, tdbc 1.1.13 + tdbc::sqlite3 (sqlite 3.53.0), tdbc::odbc, TWAPI 5.2.0 (+dyncall 0.9), Img 2.1.2 (img::base + zlibtcl/pngtcl/jpegtcl/tifftcl + 19 форматов) |
| REPL-надстройка | **TclReadLine** (pure Tcl, BSD) вместо C-tclreadline: GNU readline — GPL-3, под MSVC не поддерживается. Требуется Windows-shim (низкоуровневые proc через TWAPI console API + трансляция клавиш) |
| Формат | один файл: статический exe + прицепленный ZIP (zipfs), без внешних зависимостей |

Bundled pkgs уже лежат в `pkgs/` тарбола Tcl 9.0.4: itcl4.3.8, thread3.0.6,
tdbc1.1.13, tdbcsqlite3-1.1.13 (pure Tcl!), tdbcodbc1.1.13, sqlite3.53.0
(amalgamation внутри, в compat/sqlite3). tdbcmysql/tdbcpostgres пропускаем
(нужны SDK MySQL/libpq).

## Ключевые факты (проверены по исходникам)

1. **Статическое ядро MSVC**: `nmake -f makefile.vc release OPTS=static,nomsvcrt`
   → либы с суффиксом **`sx`** (tcl90sx.lib, tcl9tk90sx.lib, tcl9itcl438sx.lib…)
   и `tclsh90sx.exe`/`wish90sx.exe`, не зависящие от VCRUNTIME (проверено objdump:
   только KERNEL32/ADVAPI32/NETAPI32/USER32/USERENV/WS2_32).
2. **zipfs-прицеп**: `zipfs mkzip out.zip kit.vfs kit.vfs` + конкатенация
   `COPY /b exe+zip`. `TclZipfs_AppHook` монтирует в `//zipfs:/app`.
   **Уточнение ресёрча**: DLL из zipfs в Tcl 9.0 грузить МОЖНО (`load` прозрачно
   извлекает файл в %TEMP% — tclZipfs.c возвращает EXDEV, tclIOUtil.c копирует).
   Это план Б; основной путь — статическая линковка (чище, без %TEMP%).
3. **Tcl_StaticLibrary(interp, "Prefix", Init, SafeInit)** делает библиотеку
   грузимой через `load {} Prefix` (точное, регистрозависимое совпадение префикса).
   `package require X` работает, если pkgIndex/ifneeded вызывает `load {} X`.
   Статический tclsh резолвит registry/dde вообще без pkgIndex — ядро знает о них.
4. **TWAPI 5.2.0**: nmake-сборка `OPTS=static,nomsvcrt` сама генерирует
   pkgIndex.tcl с fallback на `load {} Twapi` (официальная поддержка статики).
   Требует dyncall (bundled prebuilt — /MD); мы пересобираем dyncall 0.9 из
   исходников (dyncall.org) с /MT и подменяем либы (единый CRT).
   Нужно: `-I<tcl>\libtommath` в INCLUDE (tclTomMath.h → tommath.h).
   Tcl-часть: library/*.tcl (44 файла), twapi.tcl требует `registry`.
5. **Img 2.1.2**: каждый формат — TEA/TIP477 пакет (`win/makefile.vc`, общий
   `win/rules-img.vc`). Init-символы: `Tkimg_Init` (img::base), `Zlibtcl_Init`,
   `Pngtcl_Init`, `Jpegtcl_Init`, `Tifftcl_Init`, форматы — `Tkimg<type>_Init`
   (генерируются из init.c-шаблона). Версии: img::* 2.1.2, zlibtcl 1.3.2,
   pngtcl 1.6.58, jpegtcl 10.0.0, tifftcl 4.7.2. Форматы тянут зависимости сами
   через `*tcl_InitStubs` при `load {}`. Порядок сборки: base → zlib → libjpeg →
   libpng → libtiff → 19 форматов.
6. **CAWT 3.1.1 — pure Tcl** (COM через twapi::comobj; cawt.dll не существует).
   Пакеты: cawt (мета) + cawtcore/cawtexcel/cawtword/… — свой pkgIndex.tcl
   расширяет auto_path. Нужен twapi ≥5.1.
7. **itcl4** ищет itcl.tcl в `[file dirname $tcl_library]/itcl4.3.8/` → кладём
   `itcl4.3.8/itcl.tcl` в корень zip.
8. **tdbc**: C-часть (Tdbc_Init) + Tcl-часть tdbc.tcl (wrapper в kit_register.c
   sourc'ит её из zipfs). tdbc::sqlite3 — pure Tcl (tdbcsqlite3.tcl).
9. **TclReadLine**: pure Tcl, но заточен под POSIX (`exec stty`, ANSI-escapes,
   Expect). Для Windows нужен shim: rawInput/lineInput/getColumns/cleanup через
   twapi console API + трансляция Windows-клавиш (0xE0-скан-коды → ANSI).
10. **MinGW**: `configure --disable-shared` в win/ (tcl, tk) и в pkgs/*;
    make сам создаёт staging libtcl.vfs/tcl_library, libtk.vfs/tk_library и
    прицепляет zip к tclsh90s.exe/wish90s.exe. Зависимости exe: только
    системные DLL + api-ms-win-crt-* (UCRT входит в Win10+). Kit-exe линкуем
    с `-static -municode` (полностью автономный).

## Структура VFS (staging `kit.vfs/`)

```
kit.vfs/
  tcl_library/          <- из libtcl.vfs ядра (registry/dde pkgIndex уже удалены)
  tk_library/           <- из libtk.vfs (только GUI)
  itcl4.3.8/itcl.tcl    <- itcl ищет рядом с [file dirname $tcl_library]
  thread_library/ttrace.tcl
  lib/
    kit_init.tcl        <- автопуть, алиасы, load {}-индексы Img
    tdbc/{tdbc.tcl,tdbcsqlite3.tcl}
    twapi/*.tcl + pkgIndex.tcl   <- вендорный, с load {} Twapi fallback
    cawt/{pkgIndex.tcl,cawtapp.tcl,Cawt*/…}
    TclReadLine/{tclreadline.tcl,pkgIndex.tcl}
    tcllib2.0/<134 модуля>       <- modules/ из тарбола
    tklib0.9/<35 модулей>        <- только GUI
```

Каталоги lib/<pkg>/ с pkgIndex.tcl находятся сами: Tcl сканирует auto_path
на глубину 1 (lib/ добавлен в auto_path → lib/twapi/pkgIndex.tcl виден).
Для tcllib/tklib добавляем в auto_path сами каталоги tcllib2.0/tklib0.9
(их pkgIndex'ы — на глубину 1 ниже).

## Этапы сборки

### A. MSVC (`build/msvc/`)
1. `scripts/build-msvc-core.bat` — Tcl+pkgs+Tk `OPTS=static,nomsvcrt` ✅
2. `scripts/build-msvc-ext.bat` — dyncall 0.9 (/MT) → twapi `OPTS=static,nomsvcrt` ✅
3. `scripts/build-msvc-img.bat` — base, support-либы, 19 форматов (OPTS=static,nomsvcrt)
4. `scripts/build-msvc-kit.bat` — kit_register.c ×2 (консоль/GUI-флавор) +
   kit_main.c + kit_wish_main.c; линковка sx-либ + glob pkgs/twapi/img (*sx.lib, *stub.lib)
5. `scripts/assemble-msvc-kit.ps1` — staging → zipfs mkzip (tclsh90sx) → COPY /b → dist/

### B. MinGW (`build/mingw/`, MSYS2 UCRT64)
1. `scripts/build-mingw-core.sh` — tcl, tk (`configure --disable-shared`), pkgs ✅/⏳
2. `scripts/build-mingw-ext.sh` — dyncall (gcc) → twapi (TEA, CPPFLAGS+=libtommath)
   → Img (top-level configure --disable-shared)
3. `scripts/build-mingw-kit.sh` — gcc -O2 -static -municode; архивы перечисляем
   дважды (циклические зависимости); -mwindows для GUI
4. `scripts/assemble-mingw-kit.ps1` — тот же staging, mkzip через mingw tclsh90s.exe

### C. Тесты (на каждый из 4 exe)
- `tests/smoke.tcl`: patchlevel, zipfs, все package require, sqlite/tdbc/thread/
  itcl round-trips, registry, twapi + COM через dyncall (WScript.Shell),
  tcllib (base64/struct/textutil), cawtcore, TclReadLine; GUI: Img PNG
  round-trip, tklib, виджеты.
- Интерактив: REPL с TclReadLine-shim (после основной сборки).
- CAWT live-тест: только при наличии MS Office (осторожно, отдельный сценарий).
- Переносимость: запуск из read-only каталога, отсутствие зависимостей (objdump),
  размер, время старта.

### D. Артефакты
`dist/`: tclwinkit-msvc.exe, winkitwish-msvc.exe, tclwinkit-mingw.exe,
winkitwish-mingw.exe + README + отчёт сравнения цепочек.

## Риски и статус

- ~~CAWT бинарный~~ → **решено**: pure Tcl 3.1.1, только zipfs.
- ~~tclreadline/GPL~~ → **решено**: TclReadLine (BSD). Остался Windows-shim
  (raw console через twapi + трансляция клавиш) — единственная «ручная» часть.
- ~~Img статикой вручную~~ → TIP477 nmake/TEA поддерживают OPTS=static;
  MSVC-сборка идёт штатно (base+zlib+libjpeg+libpng+libtiff+форматы).
- ~~tommath для twapi~~ → для статики символы уже в tcl90sx.lib; нужен только
  include-путь при компиляции.
- Смешивание CRT: dyncall пересобран с /MT — весь MSVC-exe на одном CRT.
- Осталось проверить: статические stub-цепочки Img в одном exe (tkimgstub и
  друзья), twapi-статика в /MT exe (COM-тест в smoke), MinGW top-level
  configure Img (может потребоваться per-package сборка).
