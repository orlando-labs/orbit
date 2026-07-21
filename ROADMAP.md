Вердикт: Ember уже выглядит как сильный framework preview, но пока не production-ready. Этапы 0–2 завершены: HTTP correctness, lifecycle, graceful shutdown и production transport реализованы и покрыты conformance/regression-тестами. Оставшиеся главные точки роста — безопасность, наблюдаемость, release engineering и RC-валидация.

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

Основные оставшиеся блокеры:

- `request.origin` доверяет `Host` и всегда считает схему `http`; нет Host allowlist и trusted-proxy/CIDR политики;
- [HTML macro](/Users/slowpilot/workspace/amber/ember/src/ember/html.am:17) не различает HTML, URL, JavaScript и CSS-контексты;
- нет CI, версий, тегов, LICENSE, CHANGELOG, SECURITY policy, package lock и воспроизводимого dependency resolution;
- нет structured telemetry, метрик, tracing, performance budgets, fuzz/load/soak suite;
- TLS и HTTP/2/3 остаются ответственностью обязательного trusted edge.

## Рекомендуемая граница Ember 1.0

Разумный первый production-контракт:

> Ember 1.0 — production-ready HTTP/API и server-rendered framework, разворачиваемый за TLS reverse proxy.

TLS и HTTP/2/3 можно оставить нижнему транспортному или edge-слою. Но keep-alive между proxy и Ember, graceful shutdown, trusted proxies, browser security primitives и observability должны попасть в 1.0.

## Рабочая дорожная карта

| Этап | Результат | Критерий выхода |
|---|---|---|
| 0. Контракт, 1 неделя — **выполнен 2026-07-19** | Зафиксировать HEAD fallback, trailing slash, status/body semantics, публичный API, edge deployment model и compatibility policy | Принят [ADR-0001](docs/adr/0001-ember-1-0-contract.md), опубликованы контракты и [definition of production-ready](docs/PRODUCTION_READINESS.md), решения закреплены self-test |
| 1. Correctness и lifecycle, 2–3 недели — **выполнен 2026-07-21** | Исправить streaming middleware, cancellation propagation, immutable snapshots, multi-value headers; добавить error hook и configurable server limits/timeouts | Все invariants покрыты unit/property tests; shutdown и cancellation не превращаются в 500 |
| 2. Production transport, 3–4 недели — **выполнен 2026-07-21** | Server handle, stop accepting, drain in-flight requests, shutdown deadline, keep-alive, overload policy, integration start/stop; корректные HEAD/204/304/1xx semantics | Graceful shutdown воспроизводим; нет потерянных ORM leases и зависших streams; HTTP conformance suite зелёный |
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

### Результат этапа 1

- `ember.Headers` сохраняет порядок и повторяемые поля, валидирует имена/значения и исключает неоднозначное framing.
- Streaming-safe middleware сохраняет тип response и повторяемые заголовки; cancellation/runtime control flow не превращается в `500`.
- Immutable snapshots усилены для routes, matches, request metadata и headers; `on_error` получает редактированный `ErrorEvent`.
- Все server limits/timeouts доступны через `App`, валидируются до bind.
- `test/stage1_selftest.am` покрывает invariants, отрицательные случаи и route/path round-trip property corpus.

### Результат этапа 2

- Публичный `ServerHandle` реализует readiness, `stop_accepting`, in-flight/stats, blocking/async serve, clean drain, deadline cancellation и идемпотентный shutdown.
- HTTP/1.1 transport поддерживает bounded keep-alive/pipelining, idle timeout, ограничение запросов на соединение и немедленный `503` при исчерпании hard capacity.
- Integration hooks запускаются до readiness, останавливаются после drain/cancellation в обратном порядке; startup failure выполняет unwind уже запущенных hooks. ORM pool закрывается только после освобождения request lease.
- Wire rules для `HEAD`, final `1xx`, `204`, `205`, `304`, `Content-Length`, `Transfer-Encoding`, trailers и malformed Host/CL-TE/obs-fold проверяются до/на границе transport.
- `test/stage2_selftest.am` и `amber-lang/tests/vm_net_http_tests.cpp` воспроизводят keep-alive, raw-socket conformance, overload, clean/forced shutdown и cancel/unwind без потерянных leases или зависших задач.
- Конкретный API и операционные ограничения опубликованы в [TRANSPORT.md](docs/TRANSPORT.md).

Тестирование должно развиваться параллельно с этапами 1–5:

- property tests для route matching и `path()` round-trip;
- corpus по [RFC 9110](https://www.rfc-editor.org/info/rfc9110/) и [RFC 9112](https://www.rfc-editor.org/rfc/rfc9112.html): CL/TE ambiguity, duplicate Host/Content-Length, bare LF, obs-fold, trailers, premature EOF;
- fuzzing percent decoding, query/JSON/multipart и HTTP framing; для C++-части подходит continuous fuzzing наподобие [ClusterFuzzLite](https://github.com/google/clusterfuzzlite);
- concurrency, cancellation, slowloris, slow reader/writer, client disconnect;
- load/soak профили для small JSON, 1K/4K routes, streaming, ORM pool exhaustion;
- compatibility matrix Ember × Amber compiler/runtime.

## Приоритеты

P0 до первого production deployment:

- Host/trusted-proxy policy;
- context-aware HTML safety;
- CI, conformance и fuzz corpus;
- structured logs, redaction и security baseline.

P1 до Ember 1.0:

- metrics/tracing и platform health/readiness endpoints;
- cookies, sessions, CSRF и bounded multipart;
- benchmarks и regression gates;
- package/release/compatibility contract;
- полноценная operational документация.

После 1.0 можно отложить WebSocket, HTTP/2/3 внутри процесса, direct TLS, hot reload, generators/resources, `.amv`, asset pipeline и динамически заменяемые route snapshots.

Оставшаяся оценка для production-ready общего web-профиля: примерно 16–24 инженерные недели. Самый значимый риск расписания теперь сосредоточен в security/HTML контрактах, observability и доказательствах RC, а не в базовом HTTP lifecycle.
