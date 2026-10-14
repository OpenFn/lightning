---
id: shared-usage-limits-banner
type: shared
title: Usage limits banner (and book-a-demo banner)
status: not-started
owner:

trigger:
  old_route: any LiveView that mounts {LightningWeb.Hooks, :check_limits} and renders the `:banner` slot
  new_route:
  old_route_disposition: unchanged
  reachable_when:
    - a non-default usage limiter adapter is configured, or the book-a-demo banner is enabled

inherits: []

url_params: []

config_variants:
  default: { Lightning.Extensions.usage_limiter: Lightning.Extensions.UsageLimiter }   # always :ok, no banner
  usage-limited: { Lightning.Extensions.usage_limiter: <hosted adapter returning {:error, _, %{position: :banner}}> }
  book-demo-banner: { lightning.book_demo_banner.enabled: true }

inventory:
  routes: []
  events: []
  js_hooks: []
  policies: []
  workers: []
  api_endpoints: []
  emails: []
  config:
    - :lightning, Lightning.Extensions, :usage_limiter
    - :lightning, :book_demo_banner
  not_reachable_here: []

related:
  - lib/lightning_web/live/live_helpers.ex
  - lib/lightning/extensions/usage_limiter.ex
flows: []
---

## 1. Purpose

On hosted instances, a project that has hit a plan limit (runs, for example) needs to say so on
every project page, so the people working in it understand why things are being held back and
what to do. Self-hosted instances run with a limiter that never objects, so the banner never shows.

## 2. What it does

- Project pages show the limiter's banner when the project is over a limit
- Pages show nothing extra when the project is within its limits
- Users on instances with the book-a-demo banner enabled see it until they dismiss it

## 3. Who can do what

| Action | Viewer | Editor | Admin | Owner | Superuser | Support |
|--------|--------|--------|-------|-------|-----------|---------|
| See the limits banner | yes | yes | yes | yes | yes | yes |

**Preconditions beyond role**
- The page must have a `project` assign when `:check_limits` runs (`lib/lightning_web/hooks.ex:241-249`).

## 4. What it touches

**Reads**: whatever the configured limiter reads (`lib/lightning/services/usage_limiter.ex:10-12`); `users.preferences` for the demo banner

**Writes**: none

**Immediate side effects**
- none

**Deferred side effects**
- none

**External, non-transactional effects**
- none in the default adapter; a hosted adapter may call out

**Depends on config**
- `config/config.exs:41-43` usage limiter adapter; `lib/lightning/config.ex:268` book-demo flag

**Product limits**
- Limits are defined by the adapter, not in this repo

## 5. Scenarios

```gherkin
Feature: Usage limits banner
  In order to understand why my project is being held back
  As anyone working in a project
  I want to see a banner when the project is over a plan limit

  @S01 @pending @variant:usage-limited
  Scenario: Over-limit project shows the limiter's banner
    # Value: people learn they've hit a plan limit before they lose time wondering why runs stopped.
    Given the usage limiter reports project "Malawi HIV" is over its run limit
    When I open the project's workflows page
    Then I see the limiter's banner text
    # lib/lightning_web/live/live_helpers.ex:200-210
    # test/lightning_web/live/workflow_live/index_test.exs:47-60 asserts "Some banner text"

  @S02 @pending
  Scenario: Within-limit project shows no banner
    # Value: nobody is nagged when nothing is wrong.
    Given the default usage limiter
    When I open the project's workflows page
    Then I see no limits banner
    # lib/lightning/extensions/usage_limiter.ex:8
```

## 6. Unclear value

### 6.1 Possible bugs

| What | Where | What a user sees | Disposition |
|------|-------|------------------|-------------|
| The limits banner and the book-a-demo banner share the `:banner` assign; the limits check overwrites the demo banner when both apply | `lib/lightning_web/init_assigns.ex:44-51`, `live_helpers.ex:208-209` | only one banner, whichever was assigned last | decide |

### 6.2 Quirks and implementation details

| What | Where | Disposition |
|------|-------|-------------|
| The limiter decides where the message goes (`position`), so it can target any assign, not only the banner | `live_helpers.ex:208-209` | decide |
| Limits are checked once at mount; a page left open does not pick up a limit being reached | `hooks.ex:241-249` | decide |

### 6.3 Unreachable or dead code

| What | Where | Why unreachable |
|------|-------|-----------------|
| Banner rendering path | `live_helpers.ex:208-209` | default adapter always returns `:ok`; only reachable with a hosted adapter |

### 6.4 Performance and operational limits

none

### 6.5 Things seen but not understood

none

## 7. Not migrating

| Item | Reason | Decided by | Date |
|------|--------|------------|------|

## 8. Open questions

- The real banner copy and limits live in the hosted adapter, outside this repo. Who owns that list for the rebuild?
