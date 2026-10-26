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
   fileevent+`read stdin`). Реализован shim `tclreadline-win.tcl` (TWAPI):
   rawInput/lineInput → `SetConsoleMode` (посимвольно, без echo; Ctrl+C в raw
   приходит как \x03 и чистит строку), ANSI-вывод → бит
   ENABLE_VIRTUAL_TERMINAL_PROCESSING (0x4) через raw `twapi::SetConsoleMode`
   (символьные флаги TWAPI его не знают), getColumns →
   `get_console_screen_buffer_info -windowsize`, interact → синхронный цикл
   `ReadConsoleInput` (`twapi::_console_read_input_records`): key-записи
   (vkey+модификаторы+char) транслируются в ANSI (`\033[A..D`, `\033[1;5x`
   ctrl, `\033[1;2x` shift, `\033[Z` shift-tab, `\033[H/F`, `\033[3~`), а
   `read stdin` переименован в заглушку («») — ввод идёт мимо канала.
   Логика редактирования/истории/дополнения вендора не тронута.
   `main.tcl` (корень zip, ТОЛЬКО консольный кит): семантика tclsh
   (script args / -encoding / pipe-цикл stdin с продолжением после ошибок /
   интерактив), детект консоли по РЕАЛЬНОМУ stdin-хендлу
   (`get_standard_handle`+`GetConsoleMode`; `get_console_handle` не годится —
   он открывает CONIN$ даже при перенаправленном stdin). GUI-кит без main.tcl
   = сток wish (свой console-виджет).
10. **MinGW**: `configure --disable-shared` в win/ (tcl, tk) и в pkgs/*;
    make сам создаёт staging libtcl.vfs/tcl_library, libtk.vfs/tk_library и
    прицепляет zip к tclsh90s.exe/wish90s.exe. Зависимости exe: только
    системные DLL + api-ms-win-crt-* (UCRT входит в Win10+). Kit-exe линкуем
    с `-static -municode` (полностью автономный).

## Структура VFS (staging `kit.vfs/`)

```
kit.vfs/
  main.tcl              <- ТОЛЬКО консольный кит (tclsh-семантика + REPL)
  tcl_library/          <- из libtcl.vfs ядра (registry/dde pkgIndex уже удалены)
  tk_library/           <- из libtk.vfs (только GUI)
  itcl4.3.8/itcl.tcl    <- itcl ищет рядом с [file dirname $tcl_library]
  thread_library/ttrace.tcl
  lib/
    kit_init.tcl        <- автопуть, алиасы, load {}-индексы Img
    tdbc/{tdbc.tcl,tdbcsqlite3.tcl,tdbcodbc.tcl}
    twapi/*.tcl + pkgIndex.tcl   <- вендорный, с load {} Twapi fallback
    cawt/{pkgIndex.tcl,cawtapp.tcl,Cawt*/…}
    TclReadLine/{tclreadline.tcl,pkgIndex.tcl,tclreadline-win.tcl}
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
3. `scripts/build-msvc-img.bat` — base, support-либы, 19 форматов (OPTS=static,nomsvcrt) ✅
4. `scripts/build-msvc-kit.bat` — kit_register.c ×2 (консоль/GUI-флавор) +
   kit_main.c + kit_wish_main.c; линковка sx-либ + glob pkgs/twapi/img (*sx.lib, *stub.lib) ✅
5. `scripts/assemble-msvc-kit.ps1` — staging → быстрый .NET-zip (forward-slash
   entries; `zipfs mkzip` слишком медленный, ~9 мин против ~1 мин) → конкатенация
   exe+zip стримами → dist/ ✅

### B. MinGW (`build/mingw/`, MSYS2 UCRT64)
1. `scripts/build-mingw-core.sh` — tcl, tk (`configure --disable-shared`), pkgs ✅
2. `scripts/build-mingw-ext.sh` — dyncall (gcc; + `repack-dyncall.sh` — makefile
   dyncall оставляет пустые .a) → twapi (TEA, CPPFLAGS+=libtommath) → Img
   (top-level configure --disable-shared; base предоставляет `img::base`,
   а не `tkimg` — kit_init обрабатывает оба имени) ✅
3. `scripts/build-mingw-kit.sh` — gcc -O2 -static -municode; архивы перечисляем
   дважды (циклические зависимости); -mwindows для GUI; -ltdh -luuid вручную ✅
4. `scripts/assemble-mingw-kit.ps1` — тот же staging/zip-механизм, что MSVC ✅

### C. Тесты — ✅ все зелёные
- `tests/smoke.tcl`: SMOKE OK на всех 4 exe (patchlevel, zipfs, все package
  require, sqlite/tdbc round-trips c UTF-8, thread, itcl, registry, twapi + COM
  (WScript.Shell через dyncall), http, zlib, tcllib, cawtcore, TclReadLine;
  GUI: Img PNG round-trip (image width/height!), tklib canvas::zoom, виджеты).
- `scripts/test-repl.ps1`: REPL-тест инъекцией клавиш (AttachConsole +
  WriteConsoleInput): история по Up, Shift-Tab-дополнение (info patc→patchlevel),
  Left+вставка символа, exit code 0 — OK на MSVC и MinGW. История сохраняется
  в ~/.tclline_history.
- CAWT live-тест: только при наличии MS Office (отдельный сценарий, не блокирует).
- Переносимость: objdump — только системные DLL (MSVC без CRT-DLL; MinGW —
  api-ms-win-crt-* UCRT-форвардеры); запуск из read-only каталога — SMOKE OK;
  GUI-exe без аргументов живут в event loop (двойной клик).

### D. Артефакты
`dist/`: tclwinkit-msvc.exe, winkitwish-msvc.exe, tclwinkit-mingw.exe,
winkitwish-mingw.exe + README + отчёт сравнения цепочек.

## Риски и статус — ВСЁ РЕШЕНО

- ~~CAWT бинарный~~ → **решено**: pure Tcl 3.1.1, только zipfs.
- ~~tclreadline/GPL~~ → **решено**: TclReadLine (BSD) + Windows-shim
  `tclreadline-win.tcl` (twapi console API; см. п.9 выше). Ключевая грабля:
  `source` shim-файла из proc в namespace ::winkit определял proc'и
  ОТНОСИТЕЛЬНО текущего namespace — все имена в shim'е теперь с `::`.
- ~~Img статикой вручную~~ → TIP477 nmake/TEA поддерживают OPTS=static ✅.
  Минговая TEA-base даёт `img::base` вместо `tkimg` — dual-name ifneeded в
  kit_init.tcl (грузим один раз, допредоставляем отсутствующее имя).
- ~~tommath для twapi~~ → include-путь при компиляции; символы в tcl90sx ✅.
- ~~Смешивание CRT~~ → dyncall пересобран с /MT (MSVC); MinGW -static ✅.
- ~~stub-цепочки Img / twapi-статика / MinGW Img~~ → проверены smoke-тестами
  (PNG round-trip в GUI, COM-тест twapi в обоих консолях) ✅.
- `main.tcl` в корне zip (консоль): tclsh-семантика (script/-encoding/pipe/
  интерактив), catch нормализует `return -code N` в код N (не 2!).
  Детект консоли — по РЕАЛЬНОМУ stdin-хендлу (get_standard_handle +
  GetConsoleMode), не по CONIN$.
- Zip-attachment: exe+zip конкатенация; zip обязан иметь forward-slash имена
  entry (.NET CreateFromDirectory пишет backslash — непригоден; собираем
  per-entry через CreateEntryFromFile).

## Вторая волна пакетов (Itk, Iwidgets, rl_json, mpexpr, tkdnd, Treectrl)

Итоговый состав: rl_json 0.17.8 + mpexpr 1.2 — в оба кита; Itk 4.2.7 +
Iwidgets 4.1.1 + tkdnd 2.9.5 + Treectrl 2.5.2 — только GUI. **winico отброшен**:
трей и уведомления полностью покрывает TWAPI (`twapi::systemtray::addicon`
+ `load_icon_from_file/system`), дублировать не стали. Демо/примеры/man в кит
не кладутся (решение пользователя). Все патчи — в `patches/` + `patches/README.md`.

Ключевые находки:

- **Tcl 9 убрал публичный `Tcl_Backslash`** (mpparse.c mpexpr зовёт его в 6 местах)
  → компактный шим `MpBackslash` (семантика 8.6) под `#if TCL_MAJOR_VERSION > 8`.
  Внутренний `TclParseBackslash` из tclInt.h не подходит — другая сигнатура.
- **`finally` — ключевое слово SEH в MSVC**: 256 goto-меток `finally:` в
  rl_json generic/*.c переименованы в `finally_label`.
- **MSVC-препроцессор по умолчанию не тянет вариативный выбор макроса**
  (CHECK_ARGS_LABEL) → обязателен `/Zc:preprocessor`.
- **nmake не отслеживает смену defines**: dedup.obj скомпилировался с пустым
  `#if DEDUP` ДО добавления `/DDEDUP=1` и не пересобирался → LNK2001
  new_stringobj_dedup/free_cache. Лечится удалением outdir (clean).
- **rl_jsonBuildInfo.c + rl_jsonUuid.h**: MinGW configure генерирует заголовок
  в корень дерева (находится через `-I.`), MSVC makefile его не знает →
  obj добавлен в PRJ_OBJS вручную, сгенерированный uuid-заголовок скопирован
  в `generic/` (quoted include ищет рядом с файлом).
- **`mkstemp` отсутствует в MSVC CRT**; в rl_json используется только
  debug-командой `checkmem` → `#if defined(_MSC_VER)`-заглушка `(Tcl_SetErrno(EINVAL), -1)`.
- **Конфликт `DllMain`**: tkWinTree.c (treectrl) и twapi.c оба определяют
  DllMain → в статическом ките LNK2005/multiple definition. DllMain treectrl
  обёрнут в `#ifndef STATIC_BUILD` (нужен только чтобы поймать HMODULE для
  GetModuleFileNameA; с NULL возвращает путь exe — для кита верно).
- **itk несёт свой rules.vc 1.19 БЕЗ targets.vc** → переименован в rules.vc.own,
  работает fallback на tcl'овский rules.vc 1.16. Апстрим-баг makefile.vc
  (`echo TK_DIR = \> nmakehlp.out` обрезает файл, стирая предыдущие строки)
  исправлен на `\>>` — в itk и rl_json.
- **tkdnd — C++ (OleDND.cpp с extern "C")**: линковка kit'а идёт gcc → добавлен
  `-lstdc++` в GUI-вариант MinGW.
- **rl_json MinGW**: configure-пробы (Tcl_GetBytesFromObj и др.) врут —
  линкуются против stub и системного tcl.h 8.6 из /ucrt64/include; лечится
  `CPPFLAGS="-I$TCL/generic -I$TCL/win" LIBS="-L$TCL/win -ltcl90"`; сборка
  строго in-tree (Makefile использует относительный `-Iteabase`).
- **mpexpr не собирается ни одним штатным способом под Tcl 9** (мезон/nmake
  ломаются на легаси-макросах) → легаси-макросы в mpexpr.h/zmath.h
  (`_ANSI_ARGS_`, `TCL_VARARGS_DEF/START`, CONST) + кастомный gcc-цикл в
  build-mingw-ext2.sh с `-fpermissive`. `#define VOID void` НЕ добавлять —
  ломает winnt.h (`#ifndef VOID` guarding typedef'ов CHAR/SHORT).
- **Itk_Init сам НЕ грузит itcl** → обёртка `ItkKit_Init` в kit_register.c
  делает `package require itcl` перед `Itk_Init`. Оба имени (`Itk` и `itk`)
  itk предоставляет сам (Tcl_PkgProvideEx ×2 в itkBase.c).
- **itk ищет библиотеку как `[file dirname $tcl_library]/itk$patchLevel`** →
  стадия `itk4.2.7/` в КОРНЕ zip (рядом с itcl4.3.8/). Treectrl —
  `tcl_findLibrary` → `::treectrl_library` выставляется до `load {} Treectrl`
  (ifneeded-скрипт в kit_init.tcl).
- **Iwidgets pkgIndex не нужен**: ifneeded регистрирует kit_init.tcl,
  `iwidgets.tcl` генерится из `.in` на стадии сборки
  (@PACKAGE_VERSION@→4.1.1, @itcl_VERSION@→4.3.8). Классы autoload'ятся
  из `generic/tclIndex`.
- **tkdnd в статике**: нативный pkgIndex зовёт `tkdnd::initialise`, которая
  грузит DLL; kit_init.tcl повторяет её win32-путь вручную и делает
  `load {} Tkdnd` (C-часть статическая). `_windowingsystem` = windows,
  `_platform_namespace` = olednd, temp dir из `%TEMP%`.
- **mpexpr вызывает `Tcl_InitStubs(interp, "8.5", 0)`** — Tcl 9 отклоняет и
  "8.5", и "8.6" (version conflict) → под `#if TCL_MAJOR_VERSION >= 9`
  заменено на "9.0"; второй вызов `Tcl_PkgRequire(interp,"Tcl","8.5",0)`
  вообще исключён для Tcl 9. Команды: `mpexpr`, `mpformat`; оператор `**`
  отсутствует (mpexpr 1.2 старше Tcl 8.5) — использовать `pow(x,y)`.
- **Tcl 9 ужесточил разрешение квалифицырованных имён переменных**: внутри
  `namespace eval ::ns` имя `$ns::var` больше НЕ фолбэчится в глобаль —
  ищется как `::ns::ns::var` (в 8.6 работало). Последствия для iwidgets.tcl:
  `$iwidgets::library` → `$library` (variable-linked), `lappend auto_path` →
  `lappend ::auto_path` (иначе правится ::iwidgets::auto_path и autoload
  классов ломается). Правки — на стадии генерации в assemble-скриптах.
- **iwidgets.tcl делает `package forget Itk`**, если Itk ещё не предоставлен —
  убивает наш ifneeded. В ifneeded Iwidgets добавлен предварительный
  `package require Itk`.
- **tkdnd: generic/windows/compat используют относительные namespace**
  (`namespace eval generic/olednd`) — нативный `::tkdnd::initialise` грузит их
  через обёртку `::tkdnd::source`, чей proc-фрейм уже в контексте ::tkdnd.
  Реплика в kit_init зовёт `::tkdnd::source` напрямую + выставляет
  `_platform_namespace olednd` (читается в рантайме для конверсии типов).
  `namespace eval ::tkdnd { ... $dir ... }` НЕ работает: в eval-блоке
  переменные резолвятся в namespace, а не в локальном фрейме apply.
- **rl_json MSVC**: без `/DHAVE_TCL_GETNUMBERFROMOBJ=1 /DTIP445_SHIM=0
  /DGETBYTES_SHIM=0` init падает «Can't retrieve objType for int» (в Tcl 9
  числовые objType не регистрируются по имени). `Rl_json_Init` читает
  переменную `dir` из кадра вызова (вендорный pkgIndex передаёт её через
  apply) → ifneeded обёрнут в `apply {{dir} {load {} Rl_json}}`.

