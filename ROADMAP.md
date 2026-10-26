## Активная ветка: web notebook — 26 октября 2026

Следующая прикладная цель — Vue web notebook на Sputnik/Orbit, затем общий Vue
клиент для Electron на Linux/Windows. Основы sessions/OAuth/ORM atomicity и внешние
`.sv` templates реализованы; ближайший шаг — `orbit-vite`, безопасный bootstrap и
SSR-view-skeleton с клиентским Vue mount. Затем authenticated shell/project ACL
и первый notebook Run/reconnect slice.

Подробные зависимости, границы DOM/backend и критерии выхода:
[WEB_NOTEBOOK_PLAN.md](docs/WEB_NOTEBOOK_PLAN.md). Это параллельная ветка к общему
RC gate ниже. Новые `.sputnikpkg` пока не публикуем; разработка идёт на локальных
исходниках зависимостей.

Вердикт: Orbit `1.0.0-rc.1` закрывает этапы 0–5, но пока не production-ready. HTTP correctness, lifecycle, graceful shutdown, production transport, security, observability/performance и release engineering реализованы и имеют воспроизводимые gates. Оставшийся блок — длительная RC-валидация в production-equivalent окружении.

## Текущее состояние

Сильные стороны:

- детерминированный router, typed params и reverse routing;
- middleware и per-request controllers;
- безопасные по умолчанию 500 responses;
- strong parameters;
- buffered и full-duplex streaming с backpressure;
- ORM-neutral core и request-scoped ORM lease;
- context-aware HTML с типизированными URL/script/style trust boundaries;
- Host authorization, bounded trusted-proxy policy и безопасный effective origin;
- security headers, CORS, cookies, signed/encrypted sessions, CSRF и bounded multipart;
- хороший `App#call` как тестовая граница.

Основные оставшиеся блокеры:

- нет 72-часового load/soak и 24 часов coverage-guided fuzzing на RC-инфраструктуре;
- не выполнены canary, disconnect/timeout/kill matrix и rollback rehearsal реального приложения;
- исходная ChaCha20-Poly1305 реализация ожидает независимый cryptographic review до финального 1.0;
- TLS и HTTP/2/3 остаются ответственностью обязательного trusted edge.

## Рекомендуемая граница Orbit 1.0

Разумный первый production-контракт:

> Orbit 1.0 — production-ready HTTP/API и server-rendered framework, разворачиваемый за TLS reverse proxy.

TLS и HTTP/2/3 можно оставить нижнему транспортному или edge-слою. Но keep-alive между proxy и Orbit, graceful shutdown, trusted proxies, browser security primitives и observability должны попасть в 1.0.

## Рабочая дорожная карта

| Этап | Результат | Критерий выхода |
|---|---|---|
| 0. Контракт, 1 неделя — **выполнен 2026-07-19** | Зафиксировать HEAD fallback, trailing slash, status/body semantics, публичный API, edge deployment model и compatibility policy | Принят [ADR-0001](docs/adr/0001-orbit-1-0-contract.md), опубликованы контракты и [definition of production-ready](docs/PRODUCTION_READINESS.md), решения закреплены self-test |
| 1. Correctness и lifecycle, 2–3 недели — **выполнен 2026-07-21** | Исправить streaming middleware, cancellation propagation, immutable snapshots, multi-value headers; добавить error hook и configurable server limits/timeouts | Все invariants покрыты unit/property tests; shutdown и cancellation не превращаются в 500 |
| 2. Production transport, 3–4 недели — **выполнен 2026-07-21** | Server handle, stop accepting, drain in-flight requests, shutdown deadline, keep-alive, overload policy, integration start/stop; корректные HEAD/204/304/1xx semantics | Graceful shutdown воспроизводим; нет потерянных ORM leases и зависших streams; HTTP conformance suite зелёный |
| 3. Security baseline, 3–4 недели — **выполнен 2026-07-22** | Host authorization, explicit trusted-proxy/CIDR policy, secure request-id validation, security headers, CORS; cookies, signed/encrypted sessions, CSRF, multipart с жёсткими лимитами; context-aware HTML или запрет опасных контекстов | Threat model закрыт; выполнен framework-relevant профиль [OWASP ASVS 5.0](https://owasp.org/www-project-application-security-verification-standard/); нет critical/high findings |
| 4. Observability и performance, 2–3 недели — **выполнен 2026-07-22** | Structured access/error logs, redaction, route template вместо raw path, duration/bytes/status; metrics, tracing, health/readiness; router и streaming benchmarks | Совместимость с [OpenTelemetry HTTP conventions](https://opentelemetry.io/docs/specs/semconv/http/http-spans/); определены p50/p95/p99 бюджеты и regression threshold |
| 5. Release engineering и DX, 2–3 недели — **выполнен 2026-07-22** | CI matrix, versioned packages вместо sibling paths, SemVer, changelog, license, security policy, supported Sputnik versions; API reference, deployment/runbook и migration guide | Установка и сборка выполняются из чистого окружения одной документированной командой |
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
  матрицу Orbit × Sputnik/runtime/platform и срок поддержки.
- [Definition of production-ready](docs/PRODUCTION_READINESS.md) превращает
  этапы 1–5 и RC в измеримые release gates с обязательными доказательствами.
- `test/contract_selftest.s` проверяет уже реализованные решения этапа 0;
  оставшиеся нормативные transport/status invariants явно назначены этапам 1–2.

### Результат этапа 1

- `orbit.Headers` сохраняет порядок и повторяемые поля, валидирует имена/значения и исключает неоднозначное framing.
- Streaming-safe middleware сохраняет тип response и повторяемые заголовки; cancellation/runtime control flow не превращается в `500`.
- Immutable snapshots усилены для routes, matches, request metadata и headers; `on_error` получает редактированный `ErrorEvent`.
- Все server limits/timeouts доступны через `App`, валидируются до bind.
- `test/stage1_selftest.s` покрывает invariants, отрицательные случаи и route/path round-trip property corpus.

### Результат этапа 2

- Публичный `ServerHandle` реализует readiness, `stop_accepting`, in-flight/stats, blocking/async serve, clean drain, deadline cancellation и идемпотентный shutdown.
- HTTP/1.1 transport поддерживает bounded keep-alive/pipelining, idle timeout, ограничение запросов на соединение и немедленный `503` при исчерпании hard capacity.
- Lifecycle-aware integrations наследуют `orbit.Integration`; их hooks запускаются до readiness и останавливаются после drain/cancellation в обратном порядке, а startup failure выполняет unwind уже запущенных hooks. ORM pool закрывается только после освобождения request lease.
- Wire rules для `HEAD`, final `1xx`, `204`, `205`, `304`, `Content-Length`, `Transfer-Encoding`, trailers и malformed Host/CL-TE/obs-fold проверяются до/на границе transport.
- `test/stage2_selftest.s` и `sputnik-lang/tests/vm_net_http_tests.cpp` воспроизводят keep-alive, raw-socket conformance, overload, clean/forced shutdown и cancel/unwind без потерянных leases или зависших задач.
- Конкретный API и операционные ограничения опубликованы в [TRANSPORT.md](docs/TRANSPORT.md).

### Результат этапа 3

- `orbit.SecurityPolicy` авторизует Host до routing, принимает forwarding metadata только от явных IPv4 CIDR/exact IPv6 `/128` peers, ограничивает число hops и формирует безопасные `origin`, scheme и client IP.
- Response security headers применяются и к success, и к error responses; HSTS зависит только от validated HTTPS provenance. `RequestIdMiddleware` принимает лишь bounded ASCII IDs или генерирует secure Base64URL ID.
- Новый `orbit.security` реализует bounded Cookie/Set-Cookie, HMAC-signed values, RFC 8439 ChaCha20-Poly1305 encrypted sessions с expiry/key rotation, exact CORS и session-bound signed double-submit CSRF.
- Новый `orbit.multipart` строго разбирает `multipart/form-data` с aggregate/part/header/field/file/name limits и запретом path-like filenames; storage/content validation оставлены явной политикой приложения.
- `orbit.html` различает text, quoted attribute, URL, JavaScript, CSS, event, srcdoc и запрещённые контексты; URL/script/style требуют typed wrappers, comments/tag syntax/unquoted attributes завершают macro expansion ошибкой `ORBIT_HTML_CONTEXT`.
- `test/stage3_selftest.s` проверяет positive/negative security corpus и официальный RFC 8439 vector; два compile-fail fixture закрепляют запрет неоднозначных HTML-контекстов.
- Опубликованы [security contract](docs/SECURITY.md), versioned [threat model](docs/THREAT_MODEL.md), [OWASP ASVS 5.0.0 mapping](docs/ASVS_5_MAPPING.md) и [security review/scan record](docs/SECURITY_REVIEW.md). Открытых critical/high findings нет; lower-severity risks имеют владельца и release gate.

### Результат этапа 4

- `App(telemetry:)` наблюдает полный request lifecycle: buffered ответы завершаются после validation, streaming — после producer; sink failure не меняет response/cancellation semantics.
- Новый `orbit.telemetry` публикует JSON access/error/lifecycle events с request ID, route template, status, duration, bytes и outcome; raw path/query/body/cookie/auth/error message не входят в schema, дополнительные поля редактируются политикой.
- `MetricsRegistry` считает requests, in-flight, OTel duration buckets, bytes, errors, bounded route series, stream/server/rejection/shutdown state и bounded integration-pool gauges.
- W3C `traceparent` принимается только от validated trusted proxy; server spans используют актуальные OpenTelemetry HTTP names, low-cardinality span name и privacy-safe path default.
- `HealthProbe` привязан к `ServerHandle`: readiness меняется на `503` до bind и при drain, liveness остаётся process-local.
- `benchmark/` покрывает small JSON, buffered HTML, 1K/4096 routes, full-duplex streaming, keep-alive и ORM pool exhaustion; опубликованы named environment, machine-readable baseline/budgets и автоматический 10% regression gate.
- Контракт и доказательства опубликованы в [OBSERVABILITY.md](docs/OBSERVABILITY.md), [PERFORMANCE.md](docs/PERFORMANCE.md) и `test/stage4_selftest.s`.

### Результат этапа 5

- Зафиксирован SemVer `1.0.0-rc.1`; core и ORM integration разделены на
  versioned `orbit`/`orbit-orm` packages с детерминированными `sputnik.lock`.
- `release/dependencies.lock.json` фиксирует версии, commits и tree digests
  Sputnik/ORM/SQLite; все tracked build manifests используют только внутренний
  `.build/dependencies`, который clean-room resolver создаёт без sibling checkout.
- `./script/clean-room-build` одной командой разрешает Sputnik, дважды собирает и
  сравнивает package, проверяет/устанавливает его, компилирует и запускает API
  example и компилирует server example.
- GitHub CI покрывает static/docs/locks, все self/property/security/telemetry
  tests, native/raw HTTP conformance, parser/framing fuzz smoke и examples на
  Linux x86_64, Linux arm64 и macOS arm64; отдельная строка проверяет ORM/SQLite.
- Tag workflow требует annotated `v$VERSION`, protected release review,
  повторяемую signed package build, SHA-256 source/package checksums и build
  provenance.
- Опубликованы [API reference](docs/API_REFERENCE.md),
  [configuration reference](docs/CONFIGURATION.md),
  [deployment examples](docs/DEPLOYMENT.md), [operations runbook](docs/RUNBOOK.md),
  [migration guide](docs/MIGRATION_1_0.md), [release checklist](docs/RELEASING.md),
  `LICENSE`, `CHANGELOG.md` и root `SECURITY.md`; API/export inventory и локальные
  links проверяются автоматически.
- `test/api_reference_selftest.s` компилирует документированные core examples,
  `test/stage5_fuzz_smoke.s` закрепляет bounded percent/query/JSON/multipart и
  raw HTTP framing corpus. Длительное coverage-guided fuzzing остаётся RC gate.
- `examples/soak` содержит controller-based REST-сервис для модели с 22
  сохраняемыми атрибутами и Sputnik-клиент полного CRUD/4xx-контракта;
  `script/soak` воспроизводимо собирает их, выполняет CI smoke и готовит
  временные ряды RSS/FD/application metrics и итоговый отчёт для настоящего
  72-часового прогона. Формат и критерии описаны в
  [SOAK_TEST.md](docs/SOAK_TEST.md); RC checkbox останется открытым до получения
  и review фактического 72h evidence.

Тестирование должно развиваться параллельно с этапами 1–5:

- property tests для route matching и `path()` round-trip;
- corpus по [RFC 9110](https://www.rfc-editor.org/info/rfc9110/) и [RFC 9112](https://www.rfc-editor.org/rfc/rfc9112.html): CL/TE ambiguity, duplicate Host/Content-Length, bare LF, obs-fold, trailers, premature EOF;
- fuzzing percent decoding, query/JSON/multipart и HTTP framing; для C++-части подходит continuous fuzzing наподобие [ClusterFuzzLite](https://github.com/google/clusterfuzzlite);
- concurrency, cancellation, slowloris, slow reader/writer, client disconnect;
- load/soak профили для small JSON, 1K/4K routes, streaming, ORM pool exhaustion;
- compatibility matrix Orbit × Sputnik compiler/runtime.

## Приоритеты

P0 до первого production deployment:

- RC canary, 72-часовой soak, 24-часовой coverage-guided fuzzing и rollback rehearsal;
- production exporter/dashboard/alert configuration для опубликованной telemetry schema;
- deployment-specific security configuration и application threat-model extension.

P1 до Orbit 1.0:

- RC load/soak evidence и проверка performance baseline на release runner;
- независимый cryptographic review или vetted runtime primitive;
- immutable RC evidence index со всеми CI/load/fuzz/rollback артефактами.

После 1.0 можно отложить WebSocket, HTTP/2/3 внутри процесса, direct TLS, hot reload, generators/resources и динамически заменяемые route snapshots.

Оставшаяся оценка для production-ready общего web-профиля: примерно 2–4 инженерные недели при наличии RC-инфраструктуры. Самый значимый риск расписания теперь сосредоточен в длительных soak/fuzz прогонах, независимом crypto review и canary/rollback evidence, а не в framework implementation или release tooling.
