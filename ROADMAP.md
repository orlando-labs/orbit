Вердикт: Ember уже выглядит как сильный framework preview, но пока не production-ready. Базовый API работает; главные точки роста — транспортный lifecycle, безопасность, наблюдаемость, доказуемая надёжность и выпуск пакета.

Код не изменялся, рабочее дерево осталось чистым. После чистой сборки прошли все четыре набора self-tests: core, strong params, loopback HTTP и ORM.

## Текущее состояние

Сильные стороны:

- детерминированный router, typed params и reverse routing;
- middleware и per-request controllers;
- безопасные по умолчанию 500 responses;
- strong parameters;
- buffered и full-duplex streaming с backpressure;
- ORM-neutral core и request-scoped ORM lease;
- HTML escaping для обычного text/quoted-attribute контекста;
- хороший `App#call` как тестовая граница.

Основные блокеры:

- [транспорт](/Users/slowpilot/workspace/amber/ember/README.md:290) обслуживает один запрос на соединение и всегда закрывает его; нет keep-alive, TLS, HTTP/2;
- [App#run](/Users/slowpilot/workspace/amber/ember/src/ember.am:1375) не экспонирует имеющиеся в `net.http.Server` лимиты, read/write timeout, backlog и server handle;
- нет graceful shutdown, readiness lifecycle и start/stop hooks для интеграций;
- общий `rescue Exception` потенциально превращает cancellation в 500;
- [request-id middleware](/Users/slowpilot/workspace/amber/ember/src/ember/middleware.am:11) несовместим со streaming response: он пытается превратить его обратно в buffered `Response`;
- response headers представлены map-структурой, поэтому нельзя корректно выразить повторяемые поля вроде `Set-Cookie`;
- `request.origin` доверяет `Host` и всегда считает схему `http`; нет host allowlist и trusted-proxy политики;
- [HTML macro](/Users/slowpilot/workspace/amber/ember/src/ember/html.am:17) не различает HTML, URL, JavaScript и CSS-контексты;
- заявленная immutable route table требует усиления: итоговый массив копируется, но явно не замораживается;
- нет CI, версий, тегов, LICENSE, CHANGELOG, SECURITY policy, package lock и воспроизводимого dependency resolution;
- все пять self-test графов собираются с `native_graph_full_coverage: true` и без bytecode/VM fallback (3165/3165 code objects); дальнейшее расширение native lane остаётся совместной зоной Ember и Amber compiler/runtime;
- тесты пока являются короткими self-tests, а не conformance/property/fuzz/load suite.

## Рекомендуемая граница Ember 1.0

Разумный первый production-контракт:

> Ember 1.0 — production-ready HTTP/API и server-rendered framework, разворачиваемый за TLS reverse proxy.

TLS и HTTP/2/3 можно оставить нижнему транспортному или edge-слою. Но keep-alive между proxy и Ember, graceful shutdown, trusted proxies, browser security primitives и observability должны попасть в 1.0.

## Рабочая дорожная карта

| Этап | Результат | Критерий выхода |
|---|---|---|
| 0. Контракт, 1 неделя — **выполнен 2026-07-19** | Зафиксировать HEAD fallback, trailing slash, status/body semantics, публичный API, edge deployment model и compatibility policy | Принят [ADR-0001](docs/adr/0001-ember-1-0-contract.md), опубликованы контракты и [definition of production-ready](docs/PRODUCTION_READINESS.md), решения закреплены self-test |
| 1. Correctness и lifecycle, 2–3 недели | Исправить streaming middleware, cancellation propagation, immutable snapshots, multi-value headers; добавить error hook и configurable server limits/timeouts | Все invariants покрыты unit/property tests; shutdown и cancellation не превращаются в 500 |
| 2. Production transport, 3–4 недели | Server handle, stop accepting, drain in-flight requests, shutdown deadline, keep-alive, overload policy, integration start/stop; корректные HEAD/204/304/1xx semantics | Graceful shutdown воспроизводим; нет потерянных ORM leases и зависших streams; HTTP conformance suite зелёный |
| 3. Security baseline, 3–4 недели | Host authorization, explicit trusted-proxy/CIDR policy, secure request-id validation, security headers, CORS; cookies, signed/encrypted sessions, CSRF, multipart с жёсткими лимитами; context-aware HTML или запрет опасных контекстов | Threat model закрыт; выполнен framework-relevant профиль [OWASP ASVS 5.0](https://owasp.org/www-project-application-security-verification-standard/); нет critical/high findings |
| 4. Observability и performance, 2–3 недели | Structured access/error logs, redaction, route template вместо raw path, duration/bytes/status; metrics, tracing, health/readiness; router и streaming benchmarks | Совместимость с [OpenTelemetry HTTP conventions](https://opentelemetry.io/docs/specs/semconv/http/http-spans/); определены p50/p95/p99 бюджеты и regression threshold |
| 5. Release engineering и DX, 2–3 недели | CI matrix, versioned packages вместо sibling paths, SemVer, changelog, license, security policy, supported Amber versions; API reference, deployment/runbook и migration guide | Установка и сборка выполняются из чистого окружения одной документированной командой |
| RC, 2 недели | Реальное приложение за reverse proxy, canary, нагрузка, disconnect/timeout/kill tests, rollback rehearsal | 72-часовой soak без утечек/неограниченного роста памяти; 24 часа fuzzing без crash; подтверждён rollback |

### Результат этапа 0

- [HTTP-контракт 1.0](docs/HTTP_CONTRACT.md) фиксирует строгий trailing slash,
  `HEAD -> GET` по умолчанию с приоритетом явного `HEAD`, 404/405/OPTIONS,
  нормализацию return values и status/body/framing semantics.
- [Граница публичного API](docs/PUBLIC_API.md) отделяет поддерживаемые имена и
  extension protocols от экспортированных macro helpers и внутренних деталей.
- [Модель edge deployment](docs/DEPLOYMENT.md) задаёт поддерживаемый профиль за
  TLS reverse proxy, trust boundary и startup/shutdown lifecycle.
- [Compatibility policy](docs/COMPATIBILITY.md) задаёт SemVer, deprecation,
  матрицу Ember × Amber/runtime/platform и срок поддержки.
- [Definition of production-ready](docs/PRODUCTION_READINESS.md) превращает
  этапы 1–5 и RC в измеримые release gates с обязательными доказательствами.
- `test/contract_selftest.am` проверяет уже реализованные решения этапа 0;
  оставшиеся нормативные transport/status invariants явно назначены этапам 1–2.

Тестирование должно развиваться параллельно с этапами 1–5:

- property tests для route matching и `path()` round-trip;
- corpus по [RFC 9110](https://www.rfc-editor.org/info/rfc9110/) и [RFC 9112](https://www.rfc-editor.org/rfc/rfc9112.html): CL/TE ambiguity, duplicate Host/Content-Length, bare LF, obs-fold, trailers, premature EOF;
- fuzzing percent decoding, query/JSON/multipart и HTTP framing; для C++-части подходит continuous fuzzing наподобие [ClusterFuzzLite](https://github.com/google/clusterfuzzlite);
- concurrency, cancellation, slowloris, slow reader/writer, client disconnect;
- load/soak профили для small JSON, 1K/4K routes, streaming, ORM pool exhaustion;
- compatibility matrix Ember × Amber compiler/runtime.

## Приоритеты

P0 до первого production deployment:

- lifecycle и graceful shutdown;
- cancellation и streaming-safe middleware;
- конфигурируемые лимиты/timeouts;
- immutable request/route invariants;
- multi-value headers;
- Host/trusted-proxy policy;
- context-aware HTML safety;
- CI, conformance и fuzz corpus;
- error reporting и минимальные structured logs.

P1 до Ember 1.0:

- keep-alive;
- metrics/tracing/readiness;
- cookies, sessions, CSRF и bounded multipart;
- benchmarks и regression gates;
- package/release/compatibility contract;
- полноценная operational документация.

После 1.0 можно отложить WebSocket, HTTP/2/3 внутри процесса, direct TLS, hot reload, generators/resources, `.amv`, asset pipeline и динамически заменяемые route snapshots.

Оценка для production-ready общего web-профиля: примерно 24–32 инженерные недели, или 14–18 календарных недель для двух опытных разработчиков. Самый значимый риск расписания — необходимые изменения в `amber-lang/net.http`, а не в router/API Ember.
