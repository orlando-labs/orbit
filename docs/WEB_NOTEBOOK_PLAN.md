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
  Входы объявляются обычной сигнатурой `.s` через `@template`; файлы — compile-time
  inputs, с source spans, кешированием и VM/full-native выполнением.
- [x] Native notebook / remote core: snapshots, worker isolation, durable command
  receipts, reconnect, inputs, idle Watch, board actions, server Periodic Work.
- [ ] Browser-facing authentication/authorization и Vue notebook ещё не связаны
  в один проходящий end-to-end продуктовый сценарий.

Исходные пакеты пока подключаем локально. Коммиты можно фиксировать, публикацию
новых `.sputnikpkg` откладываем до завершения согласованного web notebook flow.

## Ближайший результат: SSR-view-skeleton + Vue/Vite

Orbit отдаёт полноценный HTML document из `app.html.sv`: title, язык,
верхнеуровневую навигацию, состояние входа, доступный fallback и контейнер
`#notebook-app`. Vue через `createApp(...).mount(...)` владеет только этим
контейнером. Sputnik-HTML вокруг него сохраняет собственное владение DOM.

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
backend/views.s                typed @template declarations
backend/views/app.html.sv       SSR shell
frontend/src/main.ts           Vue client mount
frontend/src/api/               transport and versioned wire types
frontend/src/notebook/          editor, cells, results, execution state
frontend/dist/.vite/manifest.json
sputnik.build.json             source_formats and local Sputnik dependencies
package.json + lockfile         pinned frontend toolchain
```

Это предложенное расположение будущего приложения, не уже созданные директории.

### Связка controller → view → browser

В первом slice view остаётся обычной экспортируемой функцией Sputnik с явной
сигнатурой. Controller собирает view model, получает `orbit.Html` вызовом
`views.app(...)` и передаёт его существующему `render(html: ...)`. Декларации
`@template` и регистрация `.html.sv` входят в build graph приложения. Layout и
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

Dev runner перезапускает Sputnik backend при изменении `.s`/`.sv`; frontend HMR
остаётся в Vite. Production release собирается из frontend manifest/assets и
backend binary как одно целое; shell ссылается на assets той же release-версии.

### 1. Общий пакет `orbit-vite`

Первый следующий пакет связывает Vite assets с любым Orbit view; Vue-specific
логика остаётся в приложении.

- [ ] Явная конфигурация mode, frontend root, entry names, public asset base и
  разрешённого development origin. Request Host не выбирает Vite server.
- [ ] Production loader для `.vite/manifest.json`, проверяемый при старте:
  существующие entry/files, bounded manifest, безопасные пути внутри asset root,
  отсутствие неизвестных ссылок и циклов imports.
- [ ] Typed HTML helpers для stylesheet/module script/modulepreload, с
  детерминированным обходом imports и дедупликацией CSS/preload.
- [ ] Development helper добавляет `@vite/client` и entry URL; HMR работает через
  настроенный dev origin или edge proxy. CORS/WS допускаются только для явно
  заданного режима разработки.
- [ ] В production используются hashed filenames из manifest; отсутствующий entry
  — диагностируемая ошибка сборки/старта, а не пустая страница.
- [ ] CSP поддерживается явными атрибутами/nonce; helper возвращает `orbit.Html`.
  В `.sv` вставляется готовый fragment в text context. `%if` для этого не нужен:
  выбор режима и списки assets формируются до вызова view.

Соответствие Vite: явный JS entry и `build.manifest`, dev module tags,
production CSS из entry/imported chunks и optional modulepreload — по
[официальному backend integration](https://vite.dev/guide/backend-integration).
Точные имена конфигурации закрепляем вместе с выбранной версией toolchain.

**Выход:** `examples/vue_shell` запускается в dev с HMR и из production build
с выключенным Vite server; browser smoke не имеет 404 JS/CSS и ошибок mount.
Manifest, binary и assets устанавливаются одной согласованной release-версией.

### 2. Безопасная передача bootstrap data

- [ ] В `orbit.html` добавить общий helper JSON data island, например
  `json_script(data, id:, nonce:) -> Html`. Он сам кодирует JSON и исключает
  возможность закрыть script element пользовательской строкой; `raw(Json...)`
  не становится приложенческим соглашением.
- [ ] Версионированный bootstrap: публичное описание пользователя, notebook ID,
  revision, permissions/capabilities, API base, CSRF presentation. GitHub access
  token, OAuth secret и remote-core bearer туда не попадают.
- [ ] IDs/revisions и потенциальные Int64/BigInt передаются явно по wire schema;
  браузер не должен молча округлять числа вне safe integer range JavaScript.
- [ ] JSON читается через DOM `textContent`; Vue получает данные как значения.
  Авторизованный shell получает private/no-store и не кешируется общим CDN.
- [ ] Проверки `</script>`, кавычек, Unicode, HTML-like data и CSP входят в gate.

**Выход:** один и тот же bootstrap корректно принимает dev/prod Vue entry;
данные другого пользователя и серверные credentials в HTML отсутствуют.

### 3. Закончить browser authentication boundary

- [ ] Собрать login/start/callback/logout из `orbit-session`, `orbit-oauth` и
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
- [ ] Ввести владельца/ACL проекта до подключения общего project registry к web.
  Authenticated пользователь A не читает, не запускает и не скачивает данные B.

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

1. `orbit-vite` + JSON bootstrap helper + `examples/vue_shell` на `.html.sv`.
2. Authenticated shell и project ACL в новом notebook-web приложении.
3. Первый notebook API/client/editor/run/reconnect slice.

Расширение UI следует после прохождения dev/prod asset gate и auth/ACL gate.
Общий Orbit RC soak/fuzz/crypto review остаётся отдельным production release gate.
