---
paths:
  - "lib/**/*.ex"
---

# OpenTelemetry - What Leaves the Instance in a Span

Every exported span passes through `Lightning.OpenTelemetry.FilteringExporter`
(`lib/lightning/open_telemetry/filtering_exporter.ex`). It keeps only
allowlisted attributes, clears status messages and drops links. It does not
touch span names or resource attributes, so anything put there is exported as
written. Operators are told this in the Tracing section of `DEPLOYMENT.md`.

## Span names

- Never build a span name from request, user or project data: no paths, ids,
  names, emails or parameters. Use a route template, a queue name, a table name
  or a fixed string.
- This applies to `OpenTelemetry.Tracer.with_span/3`, `start_span`, and
  `Tracer.update_name/1` alike.
- `LightningWeb.Telemetry.with_span/3` is not an OpenTelemetry span. It emits
  `:telemetry` events, which no OpenTelemetry handler listens to.
- The Phoenix instrumentation names a span after the raw request method. A
  `forward` or `match :*` route accepts any method, so the caller chooses part
  of the name. `/health_check` already does this, and `DEPLOYMENT.md` says so.
  A new route of either kind needs the same note.

## Span attributes

- An attribute is exported only if it is on the exporter's allowlist. Adding
  one means changing the allowlist and its pinning test in
  `test/lightning/open_telemetry/filtering_exporter_test.exs` together, and the
  attribute table in `DEPLOYMENT.md`.
- Before adding a key, check every value it can take. The filter decides by key,
  so a key that is safe for one value shape is exported with any shape.
- Never allowlist anything in the canary test's denied list
  (`test/lightning/open_telemetry/redaction_canary_test.exs`). That test fails
  if you do, on purpose.

## Route options

The Phoenix instrumentation copies a route's options into `phoenix.action`. The
exporter keeps `phoenix.action` only when it is an atom and drops anything else.
Keep route options as action atoms anyway, so traces still show the action.
Don't relax that check to let another value shape through.

## Configuration

`OTEL_TRACES_EXPORTER` replaces the filtering exporter and
`OTEL_SPAN_EVENT_COUNT_LIMIT` lets exception messages back in as span events.
`Lightning.Config.Bootstrap` refuses to boot with either set while tracing is
on. Do not set them in config, tests or scripts, and do not relax that check.
