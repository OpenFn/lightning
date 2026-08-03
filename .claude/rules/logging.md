# Logging - Logger Levels and Sentry Noise

This guideline covers how to choose `Logger` levels in the Lightning Phoenix app so that real bugs stay visible and Sentry stays signal-rich.

## Level Policy

- **`Logger.info` / `Logger.warning`** - expected, user-actionable, or transient conditions. Examples: a user must re-authorise a credential, a project is misconfigured, an upstream provider returned 429/503.
- **`Logger.error`** - reserve for genuine application faults and invariant violations (the things you actually want to be paged about).

## Why It Matters

Sentry's `LoggerHandler` is configured with `level: :error` and `capture_log_messages: true` in `lib/lightning/application.ex`. That means **every `Logger.error` becomes a Sentry error event** - including bare log messages, not just exceptions.

Using `:error` for non-faults creates Sentry noise that buries real bugs. Downgrading to `info`/`warning` keeps the line visible in the logs (important for self-hosted / logs-only operators - the plain-text formatter in `config/config.exs` includes `:run_id`) without paging anyone.

## Single Log Site

Log a given condition at exactly **one** site, not at every layer it propagates through.

For credential resolution that site is `Lightning.Credentials.Resolver` (`lib/lightning/credentials/resolver.ex`) - the run-credential-resolution layer - **not** `LightningWeb.Channels.RunChannel`, which only formats the error and replies.

## Worked Example: Credential Resolution

| Reason | Level | Rationale |
| --- | --- | --- |
| `project_not_found` | `error` | Genuine invariant violation |
| `environment_not_configured` | `warning` | User-actionable config |
| `environment_mismatch` | `warning` | User-actionable config |
| `reauthorization_required` | `info` | User / IdP state |
| `temporary_failure` | `info` | Transient provider error |
