# Патчи вендорных исходников

Все патчи применяются **in-place** к распакованным деревьям в
`build/msvc/ext/` и `build/mingw/ext/` (обе копии идентичны, если не оговорено
иное). Здесь лежат контрольные копии пропатченных файлов — при пересоздании
деревьев из вендорных тарболов скопируйте их поверх оригиналов.

Общий объём правок на пакет — десятки строк; семантика пакетов не меняется,
правки решают только проблемы порта на Tcl 9 / MSVC / статический кит.

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
