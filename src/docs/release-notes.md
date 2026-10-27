Портативная сборка Tcl 9.0.4 (+ Tk 9.0.4) для Windows x64: один файл =
интерпретатор + статически влинкованные расширения + pure-Tcl библиотеки,
прицеплённые ZIP-архивом через встроенный zipfs. Ни DLL beside exe, ни
установщика, ни внешних зависимостей — скопировал файл и работаешь.

## Артефакты

{{ASSET_TABLE}}

Итого {{TOTAL_MB}} МБ. Все четыре kit-exe и docs-архив собраны из одного дерева
исходников и несут одну версию {{VERSION}}; контрольные суммы — в
`SHA256SUMS.txt` (`sha256sum -c SHA256SUMS.txt`, либо `certutil -hashfile
<file> SHA256` в Windows).

## Запуск

```
{{CONSOLE_EXE}} script.tcl arg1 arg2   ;# как tclsh: аргументы, -encoding
type cmds.tcl | {{CONSOLE_EXE}}        ;# stdin-режим, как tclsh
{{CONSOLE_EXE}}                        ;# интерактивный REPL: история,
                                       ;# Ctrl+R, Tab-дополнение (TclReadLine)
{{GUI_EXE}} app.tcl                    ;# как wish
{{GUI_EXE}}                            ;# GUI + Tk console widget
```

Консольный exe — drop-in замена `tclsh` (те же семантики аргументов, pipe-режима
и кодов возврата), GUI — drop-in замена `wish`. Варианты msvc и mingw взаимозаменяемы.

## Состав

| Компонент | Версия | Как подключён |
|---|---|---|
| Tcl core | 9.0.4 | статически |
| Tk | 9.0.4 | статически (GUI-exe) |
| registry / dde | 1.3.7 / 1.4.6 | статически (часть ядра) |
| Itcl | 4.3.8 | статически + `itcl4.3.8/itcl.tcl` в zipfs |
| Itk | 4.2.7 | статически + `itk4.2.7/` в zipfs (GUI-exe) |
| Iwidgets | 4.1.1 | pure Tcl (zipfs, GUI-exe) |
| Thread | 3.0.6 | статически + `thread_library/ttrace.tcl` |
| tdbc / sqlite3 | 1.1.13 / 3.53.0 | статически + Tcl-части в zipfs |
| tdbc::sqlite3 / tdbc::odbc | 1.1.13 | pure Tcl / статически |
| TWAPI | 5.2.0 | статически (+ dyncall 0.9) + Tcl-часть в zipfs |
| Img (tkimg) | 2.1.2 | статически: base, zlibtcl, pngtcl, jpegtcl, tifftcl, 19 форматов |
| rl_json | 0.17.8 | статически (обе сборки) |
| mpexpr | 1.2 | статически (обе сборки) |
| tkdnd | 2.9.5 | статически + Tcl-часть в zipfs (GUI-exe) |
| Treectrl | 2.5.2 | статически + `treectrl2.5.2/` в zipfs (GUI-exe) |
| tcllib | 2.0 | pure Tcl (zipfs) |
| tklib | 0.9 | pure Tcl (zipfs, GUI-exe) |
| CAWT | 3.1.1 | pure Tcl (zipfs) |
| TclReadLine | 1.1 | pure Tcl (zipfs) + Win32-shim на TWAPI |

## Документация, маны и демо

В kit-exe сознательно не кладётся ничего, кроме рантайма: справочные страницы,
HTML-документация, демо-программы и тестовые наборы пакетов вырезаны из
staging-образа (`scripts\kit-prune.ps1`, −32,40 МБ и −4269 файлов на GUI-кит) и
публикуются отдельным архивом `{{DOCS_ZIP}}` — 2684 файла, 41,50 МБ в
распакованном виде. Обязательные лицензионные тексты при этом остаются в exe:
prune режет документацию, но не условия лицензий (см. «Лицензии» ниже).

| Раздел | Файлов | Что внутри |
|---|---:|---|
| `man/` | 584 | nroff-страницы по 14 пакетам (tcl, tk, itcl, itk, iwidgets, img, tdbc×3, sqlite3, thread, rl_json, tkdnd, treectrl) |
| `html/` | 1473 | tcllib/tklib idoc, справочник twapi, cawt, thread, mpexpr, tkdnd, treectrl |
| `demos/` | 519 | Tk, iwidgets, itk (+itkedit), treectrl, tkdnd, cawt |
| `docs/` | 47 | README/CHANGES/ChangeLog по 20 пакетам |
| `LICENSES/` | 54 | тексты лицензий всех бандловых компонентов + своп шапок исходников |
| `tools/` | 2 | `man.tcl`, `iwidgets-demo.tcl` |
| — | 5 | `README.md`, `VERSIONS.txt`, `MANIFEST.txt`, `LICENSE`, `THIRD-PARTY-NOTICES.md` |

Распаковав архив, демо запускаются теми же exe:

```
{{GUI_EXE}} demos\tk\widget              ;# браузер демо Tk
{{GUI_EXE}} demos\iwidgets\catalog       ;# браузер демо iwidgets
{{GUI_EXE}} demos\treectrl\demo.tcl      ;# браузер демо Treectrl
{{CONSOLE_EXE}} tools\man.tcl man\tcl\subst.n  ;# ман-страница текстом, без groff
```

`tools\man.tcl` рендерит nroff в текст на самом ките — groff не нужен.

## Лицензии

Собственная обвязка кита (`src/kit`, `scripts`, `docs`, `tests`) — MIT, см.
`LICENSE` репозитория. Всё остальное остаётся при своих лицензиях: бандл
состоит из Tcl 9.0.4 / Tk 9.0.4 и их расширений (лицензия Tcl), tcllib/tklib
(лицензия Tcl с модульными исключениями), iwidgets (DSC/BSD), TWAPI и CAWT
(BSD-3), SQLite (public-domain «благословение»), libpng/libtiff/libjpeg/zlib,
Info-ZIP-шифра в zipfs и нескольких нотисов, существующих только в шапках
исходников.

Что это не декларация, а факт поставки:

- обязательные тексты лежат **внутри каждого exe** (`//zipfs:/app/...`), а не
  только в репозитории;
- `THIRD-PARTY-NOTICES.md` (в корне репозитория и в docs-архиве) называет
  каждый компонент, его лицензию, держателей и цитирует дословно то, что
  лицензия требует воспроизвести в дистрибутиве;
- каталог `LICENSES/` (54 текста) целиком генерируется
  `scripts/make-licenses.ps1` из вендорских деревьев — ничего набрано руками,
  флаг `-Check` верифицирует дерево обратно и годится в CI;
- `tests/kit-license-check.tcl` читает тексты из образа готового exe и проверяет
  в них фразы, которые требует каждая конкретная лицензия.

## Проверено на этой сборке

- `tests\smoke.tcl` — SMOKE OK на всех четырёх exe, включая статику в дочерних
  интерпретаторах (`thread create {package require sqlite3 ; thread wait}`).
- `tests\tcllib-probe.tcl` — PROBE OK ×4: консоль 439 offered / 384 loaded,
  GUI 571 / 508 loaded, 0 новых поломок против неприбранного дерева
  (апстримовые отказы сверяются со снимком `tests\tcllib-probe.baseline.txt`).
- `tests\kit-license-check.tcl` — KIT LICENSE CHECK OK ×4 (консоль: 8 путей + 6
  фраз, GUI: 17 + 11; слои отсутствуют только целиком, поэтому консольный кит
  без Tk не считается пропуском лицензии). Гард проверен негативными контролями:
  удаление 6 обязательных текстов из копии образа → 6 провалов и exit 1;
  обрезка одного до 43 байт → 2 провала (слишком короткий + требуемая фраза
  отсутствует).
- Пакетные наборы, оба кита (цифры msvc ↔ mingw совпадают): iwidgets
  3308/3308/0F, itk 100/100/0F, Img 290/272/18skip/0F, treectrl
  1236/1216/19skip/1F (upstream `itemdesc-1.15`), tkdnd 6/6 load-OK;
  itcl 793/727/66skip/0F, thread 143/117/26skip/0F, sqlite3 1/1/0/0,
  tdbc 13/13/0/0, tdbc::sqlite3 161/158/3/0F, rl_json 2565/2562/3/0F,
  mpexpr чисто; tcllib-модули: doctools 599/599/0F, textutil 211/211/0F,
  struct 2708/2672/36skip/0F, json 527/527/0F.
- `tools\man.tcl` прогоняет 556/556 страниц man-раздела готового архива с exit 0.

## Известные ограничения

- **twapi 5.2.0** — частичная поддержка: основные функции есть и работают, но
  часть собственного тестового набора апстрима падает (Windows 11 + Tcl 9).
  CAWT поверх twapi протестирован отдельно и работает.
- **X11-курсоры**: Tk на Windows берёт имена курсоров из именных CURSOR-ресурсов
  exe, поэтому нестандартные X11-имена в ките недоступны; штатные (`arrow`,
  `hand2`, `xterm`, …) работают. В docs-архиве курсоры tkdnd положены только
  для Windows.
- **Демо CAWT** частично управляют реальными приложениями Office через COM
  (Excel/Word/PowerPoint/Outlook/OneNote) — это демо автора пакета, а не тесты
  кита; нужен установленный Office.
- **Суб-демо Tk не стартуют отдельно**: 63 из 66 скриптов в `demos\tk\` при
  прямом запуске открывают диалог «Error in startup script» с текстом
  `This script should be run from the "widget" demo.` (в stderr ничего не
  попадает, процесс живёт с диалогом) — штатное поведение вендора, а не
  дефект архива; вход через `demos\tk\widget`. Демо iwidgets при упаковке
  перепривязаны к своему каталогу и запускаются напрямую.
- **MinGW-exe** несут форвардеры `api-ms-win-crt-*` (UCRT встроен в Windows 10+;
  на Win7/8 нужен KB2999226/KB3118401). **MSVC-exe** не зависят от CRT-DLL
  вовсе — только системные DLL.

## Сборка из исходников

Порядок — в README репозитория (`scripts\build-msvc-*.bat` /
`scripts\build-mingw-*.sh` + `scripts\assemble-*-kit.ps1` +
`scripts\build-docs-artifact.ps1`, тексты лицензий — `scripts\make-licenses.ps1`);
техрешения и найденные грабли — `docs\PLAN.md`, сравнение цепочек —
`docs\COMPARISON.md`, окружение — `docs\ENVIRONMENT.md`, правки вендора —
`patches\README.md`.

Релиз подготовлен `scripts\publish-release.ps1`; тег `{{TAG}}` указывает на commit
`{{HEAD}}`.
