# tclwinkit — план сборки

## Конфигурация (согласовано с заказчиком)

| Параметр | Значение |
|---|---|
| Ядро | Tcl 9.0.4 + Tk 9.0.4 (x64) |
| Цепочки | **MSVC 19.51** и **MinGW-w64 GCC 16.1** (обе, для сравнения) |
| Исполняемые файлы | на каждую цепочку: консольный `tclwinkit.exe` + GUI `winkitwish.exe` |
| Pure-Tcl пакеты | tcllib, tklib (в zipfs) |
| Бинарные пакеты (статически) | Itcl 4.3.8, Thread 3.0.6, tdbc 1.1.13 + tdbc::sqlite3 (sqlite 3.53.0), tdbc::odbc, TWAPI, Img, CAWT, tclreadline |
| Формат | один файл: статический exe + прицепленный ZIP (zipfs), без внешних зависимостей |

Всё перечисленное, кроме TWAPI/Img/CAWT/tclreadline/tcllib/tklib, уже лежит в
`pkgs/` тарбола Tcl 9.0.4 (itcl4.3.8, thread3.0.6, tdbc1.1.13, tdbcsqlite3-1.1.13,
tdbcodbc1.1.13, sqlite3.53.0).

## Как устроен single-file в Tcl 9

1. **Статическое ядро.** `nmake -f makefile.vc release OPTS=static` даёт
   `tcl90s.lib` + raw-шелл; bundled pkgs (`pkgs` target) собираются статическими
   либами (опция `staticpkg` в 9.0 упразднена — статика включает их по умолчанию).
2. **zipfs-прицеп.** ZIP, собранный `zipfs mkzip out.zip stage.vfs stage.vfs`
   (strip-аргумент = корень), просто конкатенируется с exe (`COPY /b exe+zip`).
   При старте `TclZipfs_AppHook` монтирует его в `//zipfs:/app`, ищет
   `//zipfs:/app/tcl_library/init.tcl`; если в корне zip есть `main.tcl` — он
   становится startup-скриптом (starkit-режим; **мы main.tcl не кладём**, чтобы
   exe вёл себя как обычный tclsh/wish).
3. **auto_path.** `init.tcl` добавляет в `auto_path` каталог `tcl_library` и его
   **родителя** (т.е. корень `//zipfs:/app`). Значит pure-Tcl пакеты, лежащие
   соседними каталогами с pkgIndex.tcl, находятся автоматически; для tcllib/tklib
   (у них pkgIndex'ы в подкаталогах модулей) наш AppInit дополнительно делает
   `lappend auto_path //zipfs:/app/tcllib2.x //zipfs:/app/tklib0.x`.
4. **Бинарные расширения** DLL из zipfs грузить нельзя → линкуем статически и
   регистрируем в собственном AppInit через `Tcl_StaticLibrary()` (API Tcl 9;
   в `tclAppInit.c` так сделаны Registry/Dde). Хук `TCL_LOCAL_APPINIT` позволяет
   подсунуть свой AppInit без переписывания tclAppInit.c.

## Структура VFS (staging `kit.vfs/`)

```
kit.vfs/
  tcl_library/        <- копия library/ ядра; manifest.txt -> pkgIndex.tcl;
                         registry/ и dde/ pkgIndex удалить (регистрируются статически)
  tk_library/         <- копия library/ Tk (+ manifest -> pkgIndex), для GUI-exe
  tcllib2.x/          <- модули tcllib (после install в staging)
  tklib0.x/           <- модули tklib
  twapi/              <- Tcl-часть TWAPI (pkgIndex.tcl + *.tcl)
  img*/               <- Tcl-обвязка Img (если есть)
  cawt/               <- Tcl-часть CAWT (cawt.tcl + pkgIndex.tcl)
  tclreadline/        <- Tcl-обвязка tclreadline
  tdbc/ thread/ ...   <- Tcl-части бинарных pkgs, не попавшие в tcl_library
```

Бинарные части (команды) пакетов уже в exe — pkgIndex.tcl в VFS для них
подменяем на `package ifneeded X ver {list ...}` без `load` (или используем
`package require` напрямую: статическая регистрация делает пакет «присутствующим»).

## Этапы сборки

### A. MSVC (`build/msvc/`)
1. `nmake release OPTS=static` в tcl9.0.4/win → tcl90s.lib, tclsh90s(-raw).exe,
   статические либы bundled pkgs, staging `libtcl.vfs/tcl_library`.
2. `nmake release OPTS=static TCLDIR=..\tcl9.0.4` в tk9.0.4/win → tk90s.lib, wish.
3. Внешние расширения (TWAPI, Img, tclreadline, CAWT): статические .lib
   (nmake/TEA makefile.vc со STATIC_BUILD; детали по результатам ресёрча).
4. `src/kit/kit_main.c` (консоль) и `src/kit/kit_wish_main.c` (GUI): регистрация
   всех пакетов + auto_path-довески; линковка с tcl90s/tk90s/все .lib.
5. Стажинг kit.vfs → `zipfs mkzip` (свежесобранным tclsh90s) → `COPY /b` → exe.

### B. MinGW (`build/mingw/`, под MSYS2-оболочкой UCRT64)
1. `configure --disable-shared --enable-threads --prefix=...` + `make -j16`
   в tcl9.0.4/unix → libtcl90.a, tclsh9.0.exe.
2. Аналогично tk9.0.4/unix → libtk90.a.
3. Bundled pkgs: у каждого свой configure → `--disable-shared` → .a.
4. Внешние расширения: TEA `configure --disable-shared` (TWAPI/Img/tclreadline;
   tclreadline против readline из MSYS2 ucrt64; CAWT — по итогам ресёрча).
5. Тот же kit_main.c, линковка gcc -static (libgcc/libwinpthread статически),
   staging + mkzip + конкатенация.

### C. Тесты (на каждый exe)
- `info patchlevel`, `package require` всех заявленных пакетов;
- sqlite: создать БД, вставить/прочитать; twapi: `twapi::get_os_version`;
- GUI-smoke: окно с кнопкой/канвасом (Img: загрузить PNG);
- tclreadline: интерактивный запуск, строка с редактированием;
- CAWT: при наличии MS Office — открыть Excel/создать документ (осторожно, live);
- размер exe, запуск с флешки-подобного read-only каталога, двойной клик.

### D. Артефакты
`dist/`: tclwinkit-msvc.exe, winkitwish-msvc.exe, tclwinkit-mingw.exe,
winkitwish-mingw.exe + README + отчёт сравнения цепочек (размер, скорость
старта, результаты тестов).

## Каталоги проекта

```
vendor/    тарболы/скачанные исходники
build/     деревья сборки (msvc/, mingw/)
src/kit/   kit_main.c, kit_wish_main.c, Tcl-довески (kit init)
scripts/   build-msvc-core.bat, build-mingw-core.sh, build-ext-*, assemble-kit.*
dist/      финальные exe
docs/      ENVIRONMENT.md, PLAN.md, отчёты
```

## Риски

- **CAWT**: возможно, распространяется только бинарно (MSVC-сборка) — тогда
  в MinGW-вариант не попадёт, а в MSVC-вариант пойдёт DLL? (из zipfs DLL не
  грузится — нужен план Б: только если есть исходники).
- **tclreadline под MSVC**: требует GNU readline; порта под MSVC может не быть →
  в MSVC-варианте функция может быть ограничена (или замена на linenoise-REPL).
- **Img/TWAPI статикой**: TEA-сборки обычно дают DLL; статлибы собираем вручную
  (cl/gcc по списку исходников) — это рабочая, но ручная процедура.
- **Tk статический + zipfs**: wish с прицепленным zip должен искать tk_library
  в `//zipfs:/app/tk_library` — проверяем эмпирически (в nmake-сборке Tk уже
  поддерживает embed; для MinGW делаем staging сами).
