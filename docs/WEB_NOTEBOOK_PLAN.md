# Orbit → Vue web notebook

Обновлено 26 октября 2026. Цель: web notebook с обязательной GitHub-авторизацией,
бэкендом на Sputnik/Orbit и Vue-интерфейсом, пригодным затем для Electron на
Linux/Windows. Эта ветка разработки идёт параллельно RC-проверкам общего Orbit;
она не объявляет framework production-ready.

## Уже есть

- [x] Общие `orbit-oauth` и отдельный `orbit-oauth-github`: результаты доступны
  контроллеру, без обязательного User/ORM. Authorization Code, PKCE S256,
  session-bound state и backchannel HTTP остаются на сервере.
- [x] `orbit-session`: CookieStore / MemoryStore и контракт произвольного store;
  отдельный `orbit-session-orm`, без адаптеров сессий для каждой СУБД.
- [x] ORM/adapters: транзакции, явный rollback и блокировки для атомарных операций.
- [x] Контекстный HTML, runtime `%for`, внешние `.html.sv` / `.sql.sv` / `.cmd.sv`.
  Входы объявляются обычной сигнатурой `.s` через `template`; файлы — compile-time
  inputs, с source spans, кешированием и VM/full-native выполнением.
- [x] Выделен `notebook-core`: общий C API/archive для Swift, worker loop,
  протокол/presentation и Sputnik Core/Client API; remote HTTP/CLI остаются
  адаптерами. Web-приложение подключается к этому ядру.
- [x] Native notebook / remote core: snapshots, worker isolation, durable command
  receipts, reconnect, inputs, idle Watch, board actions, server Periodic Work.
- [ ] Browser-facing authentication/authorization и Vue notebook ещё не связаны
  в один проходящий end-to-end продуктовый сценарий.

Исходные пакеты пока подключаем локально. Изменения пакетов не коммитим и новые
`.sputnikpkg` не публикуем до завершения согласованного web notebook flow.

## Локальные и серверные проекты

Electron открывает, редактирует и сохраняет локальные `.sputnikbook` через
локальный адаптер notebook-core. Для этого не нужны GitHub login, User,
серверная запись Project или загрузка книги на сервер. Локальный путь является
параметром host-адаптера и не превращается в серверную идентичность проекта.

Web-приложение также работает с серверными проектами через Orbit и постоянный
core agent. Прикладные Account/Project/ACL относятся к этому серверному режиму:
они связывают identity пользователя и серверный ProjectId. Общий формат книги,
ядро и Vue-компоненты не требуют этих моделей. Публикация/импорт локальной книги
на сервер — отдельное явное действие. Если desktop подключается к серверу,
для серверных операций применяются те же auth/ACL правила.

Очистка orphaned-проектов — отдельная будущая задача фонового maintenance
процесса; в текущий этап её не включаем. Открытие/сохранение книги, logout и
привязка Account/Project не запускают GC. Локальная книга без серверной записи
не считается orphaned-проектом. Существующий optional GC remote core пока
сохраняется без изменений; его периодический запуск по умолчанию отключён.
Выделение отдельного maintenance-процесса ещё не реализовано.

## Ближайший результат: SSR-view-skeleton + Vue/Vite

Orbit собирает полный HTML document выбранной layout-функцией: title, язык,
верхнеуровневую навигацию и общую рамку. Layout принимает `content: Html` от
view-функции страницы. Страница объявляет собственный markup, fallback и
контейнер `#notebook-app`; Vue через `createApp(...).mount(...)` владеет только
этим контейнером. Sputnik-HTML вокруг него сохраняет собственное владение DOM.

Это server-rendered shell с клиентским Vue-приложением. Полная Vue SSR/hydration
может стать отдельным этапом: hydration требует HTML того же Vue-приложения,
созданного на сервере, и соответствующего client entry. Это описано в
[Vue SSR / Client Hydration](https://vuejs.org/guide/scaling-up/ssr.html#client-hydration).
В первом этапе production HTTP/backend остаётся Sputnik; JavaScript toolchain
используется при сборке frontend assets и при разработке.

Пример целевой структуры в `sputnik-notebook/apps/notebook-web/`:

```text
backend/main.s                 Orbit application and routes
backend/controllers/           auth, shell, authorized notebook API
backend/layouts.s              layout template declarations
backend/views/layouts/         one or more document layouts
backend/views.s                page template declarations
backend/views/account/         page fragments / Vue mount points
frontend/src/main.ts           Vue client mount
frontend/src/api/               transport and versioned wire types
frontend/src/notebook/          editor, cells, results, execution state
frontend/dist/.vite/manifest.json
sputnik.build.json             source_formats and local Sputnik dependencies
package.json + lockfile         pinned frontend toolchain
```

Для notebook-web это предложенное расположение. Реализованный account-only прототип
лежит в `examples/vue_shell/`, с frontend в `./frontend`.

### Связка controller → view → browser

В первом slice view остаётся обычной экспортируемой функцией Sputnik с явной
сигнатурой. Controller получает `orbit.Html` вызовом page view, передаёт его как
`content` в явно выбранную layout-функцию и отдаёт готовый document через
`render(html: ...)`. В прототипе это `layouts.application(views.account(), ...)`.
Layout-вьюх может быть несколько, выбор делается обычным вызовом в коде action.
В `<head>` Vue-layout прямо вызывает `assets.tags(entry: entry)` и
`json_script(bootstrap, id: "orbit-bootstrap")`; entry выбирает dev module URL
или production JS/CSS по Vite manifest. Декларации
`template` и регистрация `.html.sv` входят в build graph приложения. Layout и
partials при необходимости составляются вызовами таких же функций с безопасными
HTML fragments. Отдельный пакет `orbit-views` можно выделить после появления
общих соглашений; первый shell использует уже существующий render-контракт.

В production тот же trusted edge, который завершает TLS перед Orbit, обслуживает
`/assets/` из соответствующего frontend dist: корректные MIME types, immutable
cache для hashed assets и настоящий 404 для отсутствующего файла. Маршруты
`/api/` и страницы идут в Orbit; HTML fallback не подменяет отсутствующий JS.
В `examples/vue_shell` нужны и конфигурация edge/static preview, и browser smoke
с выключенным Vite server. Это фиксирует способ доставки assets без добавления
отдельного `orbit-static` в первый scope.

Обычные публичные файлы приложения живут в `./assets` и могут передаваться самим
Sputnik через `orbit.assets.StaticFiles()`. В Vue-примере favicon отдаётся так,
без controller action: scoped `fs.File.open` / `each_chunk`, fixed-length stream
и HEAD без producer. Это модуль Orbit, отдельный пакет не добавляется.
Код приложения не импортирует `orbit.telemetry`, когда telemetry не настроена;
full-native сборка обрабатывает необязательные hooks без искусственной зависимости.

Приложение запускается от `backend/main.s`, локальные файлы находятся по
импортам. Манифест для обычного приложения не обязателен. В Vue-примере
`sputnik.build.json` содержит только path overrides для локальной разработки
и `source_formats`; `modules`, `sources`, `root` и повторной точки входа нет.
Остальные build-примеры используют `entry`, без перечисления исходников.
Resolver общий для imports, макросов и `.sv`; graph lock фиксирует выбранные
пакеты/источники/связи, а локальные исходники остаются изменяемыми. Dev watcher
получает реальные inputs из compiler summary.

`respond` выбирает одно представление по Accept: HTML/JSON/text или произвольный
MIME с явным encoder. Vue shell использует его для страницы/сессии и HTML/JSON
веток login/logout; клиент явно запрашивает JSON. Vary, 400/406 и ленивая
семантика веток проверяются в VM/full-native и браузере.

Dev runner перезапускает Sputnik backend при изменении `.s`/`.sv`; frontend HMR
остаётся в Vite. Production release собирается из frontend manifest/assets и
backend binary как одно целое; shell ссылается на assets той же release-версии.

### 1. Общий пакет `orbit-vite`

Первый следующий пакет связывает Vite assets с любым Orbit view; Vue-specific
логика остаётся в приложении.

- [x] Явная конфигурация mode, frontend root, entry names, public asset base и
  разрешённого development origin. Request Host не выбирает Vite server.
- [x] Production loader для `.vite/manifest.json`, проверяемый при старте:
  существующие entry/files, bounded manifest, безопасные пути внутри asset root,
  отсутствие неизвестных ссылок. Обход imports использует visited set и
  ограничение числа узлов; циклические ссылки не приводят к бесконечной рекурсии.
- [x] Typed HTML helpers для stylesheet/module script/modulepreload, с
  детерминированным обходом imports и дедупликацией CSS/preload. CSS entry
  предшествует CSS imports с сохранением manifest order; dynamicImports остаются
  ленивыми и не превращаются в обязательный initial preload.
- [x] Development helper добавляет `@vite/client` и entry URL; HMR работает через
  настроенный dev origin или edge proxy. CORS/WS допускаются только для явно
  заданного режима разработки.
- [x] В production используются hashed filenames из manifest; отсутствующий entry
  — диагностируемая ошибка сборки/старта, а не пустая страница.
- [x] CSP поддерживается явными атрибутами/nonce; helper возвращает `orbit.Html`.
  В `.sv` вставляется готовый fragment в text context. `%if` для этого не нужен:
  выбор режима и списки assets формируются до вызова view.
- [x] Общая `orbit.ContentSecurityPolicy` с immutable `.with(...)`; `Assets.csp`
  автоматически добавляет dev script/style/HMR permissions и оставляет core
  same-origin политику в production. Пример не собирает CSP строкой.
- [x] `orbit.Origin` и `SecurityPolicy(origin:)` проверяют scheme/host/port после
  trusted-proxy обработки; отдельный origin middleware в приложении удалён.

Соответствие Vite: явный JS entry и `build.manifest`, dev module tags,
production CSS из entry/imported chunks и optional modulepreload — по
[официальному backend integration](https://vite.dev/guide/backend-integration).
Точные имена конфигурации закрепляем вместе с выбранной версией toolchain.

**Выход:** `examples/vue_shell` запускается в dev с HMR и из production build
с выключенным Vite server; browser smoke не имеет 404 JS/CSS и ошибок mount.
Manifest, binary и assets устанавливаются одной согласованной release-версией.

### 2. Безопасная передача bootstrap data

- [x] В `orbit.html` добавить общий helper JSON data island, например
  `json_script(data, id:, nonce:) -> Html`. Он сам кодирует JSON и исключает
  возможность закрыть script element пользовательской строкой; `raw(Json...)`
  не становится приложенческим соглашением.
- [ ] Расширить существующий версионированный account bootstrap: notebook ID,
  revision, permissions/capabilities, API base, CSRF presentation. GitHub access
  token, OAuth secret и remote-core bearer туда не попадают.
- [x] IDs/revisions и потенциальные Int64/BigInt передаются явно по wire schema;
  браузер не должен молча округлять числа вне safe integer range JavaScript.
- [x] JSON читается через DOM `textContent`; Vue получает данные как значения.
  Авторизованный shell получает private/no-store и не кешируется общим CDN.
- [x] Проверки `</script>`, кавычек, Unicode, HTML-like data и CSP входят в gate.

**Выход:** один и тот же bootstrap корректно принимает dev/prod Vue entry;
данные другого пользователя и серверные credentials в HTML отсутствуют.

### 3. Закончить browser authentication boundary

- [x] В account-only `examples/vue_shell` собрать login/start/callback/logout из `orbit-session`, `orbit-oauth` и
  `orbit-oauth-github`; после входа rotate session, до API проверять session.
- [ ] CookieStore оставить первым вариантом, чтобы не создавать session writes
  в SQLite на каждый request. User/account linking и ACL принадлежат приложению.
- [ ] Закрепить политику expiry, logout/revocation и replay при нескольких
  процессах. Cookie snapshots сами по себе не дают глобального одноразового
  потребления OAuth state; shared/atomic хранение выбирается явно при требовании
  такой гарантии. Протестировать выбранный режим, не скрывать ограничение store.
- [ ] Browser API работает через same-origin Orbit; modifying requests защищены
  CSRF. Непроверенный return_to, ошибки state/PKCE и callback replay закрываются
  согласованными сценариями, без записи credentials в logs.
- [x] Ввести владельца/ACL серверного проекта до подключения общего project registry к web.
  Authenticated пользователь A не читает, не запускает и не скачивает данные B.
  Эти модели не требуются для открытия локального `.sputnikbook` в Electron.

**Выход:** GitHub login → session → SSR shell → authorized API → logout проходит
в браузере; негативные auth/CSRF/ACL сценарии проверены. Внешний GitHub smoke
отделён от offline provider mocks и требует реальной конфигурации приложения.

### 4. Один notebook через Orbit browser API

Orbit становится browser-facing границей и адаптирует существующий core:
`browser → Orbit session/ACL → local/remote core → isolated worker`.
Core bearer и доступ к Unix socket/SSH остаются серверными.

- [ ] Versioned browser API/client contract: project/snapshot, document, registry,
  Run, receipt, status/events, presentation, Stop и reconnect.
- [ ] Сначала bounded polling/events cursor поверх уже имеющегося протокола.
  SSE/WebSocket добавляются при измеренной необходимости и не блокируют slice.
- [ ] Command IDs, revision, runtime epoch и input version передаются явно;
  reconnect/lost reply не создают повторный Run.
- [ ] Vue slice: открыть один notebook, показать ячейки, изменить source, Run,
  увидеть result/error/diagnostic span, Stop, обновить вкладку и reattach.
- [ ] Lifecycle API не смешивает загрузку/просмотр документа с исполнением кода.
  Закрытие браузера не завершает уже принятую сервером работу.
- [ ] Терминальный результат/ошибка, устаревший результат, disconnected и busy
  состояния различимы; старый response не затирает новую revision.

**Выход:** один сценарий работает и из dev entry, и из production assets после
reconnect, с запретом межпользовательского доступа и дублей команд.

### 5. Дальнейшая полнота и Electron

- [ ] Перенести inputs/Apply/Watch, boards/actions и Periodic Work по имеющимся
  server contracts, затем typed result renderers, media/artifacts и зависимости.
- [ ] Вынести browser-neutral API/wire types из компонентов. Electron на
  Linux/Windows использует тот же Vue build; host capabilities предоставляет
  узкий preload/backend bridge. Renderer не получает общий filesystem/process
  доступ. Desktop-local и remote authenticated режимы описываются отдельно.
- [ ] Выбрать packaging/update/distribution и платформенные gates после web slice.
  GitHub browser login не должен блокировать согласованный локальный offline режим.

## Что реализовывать следующим заходом

1. Готово: `orbit-vite` + JSON bootstrap helper + `examples/vue_shell` на `.html.sv`.
   Dev/prod browser gates и full-native backend проверены с локальным GitHub HTTP
   fixture на Sputnik. Реальный GitHub consent run требует OAuth App credentials.
2. Готово: выделен `notebook-core`, общий Session/kernel/worker, C API для Swift
   и Sputnik Core/Client API для remote и Orbit. HTTP/CLI и UI остаются адаптерами.
   Дальнейшие web API используют это ядро; нового evaluator/backend не создаём.
3. Готов каркас `sputnik-notebook/apps/notebook-web`: GitHub Account/Identity,
   Project с владельцем, Membership editor/viewer, миграции ORM/SQLite,
   CookieStore, SSR layout + Vue-каталог и управление доступом. Core Client
   подключается как optional service; создание проекта пока создаёт только
   запись каталога, без документа или core project. Следом — явный import/create
   документа в общем core, затем editor/run/reconnect slice через Orbit ACL.
   Локальный desktop adapter остаётся независимым от аккаунтов; orphan GC
   в этот этап не входит.

Расширение UI следует после прохождения dev/prod asset gate и auth/ACL gate.
Общий Orbit RC soak/fuzz/crypto review остаётся отдельным production release gate.

В прототипе нет Python-зависимостей: backend и OAuth fixture — Sputnik,
frontend/dev/browser tooling — Node/Vite. Project ACL реализован в notebook-web;
редактор и исполнение notebook UI предстоит подключить к общему core.
