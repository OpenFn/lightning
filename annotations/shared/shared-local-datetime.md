---
id: shared-local-datetime
type: shared
title: Local date and time display
status: not-started
owner:

trigger:
  old_route: any LiveView that renders LightningWeb.Components.Common.datetime/1
  new_route:
  old_route_disposition: unchanged
  reachable_when:
    - the host page renders a timestamp through `Common.datetime` (common.ex:399-498)
    - the browser has JavaScript enabled; without it the LocalTimeConverter hook never runs (assets/js/hooks/index.ts:998-1062)

inherits: []                        # the host page's access gates apply; this component adds none

url_params: []

config_variants:
  default: {}                       # verified against this; the component reads no app config

inventory:
  routes: []
  events: []
  js_hooks:
    - LocalTimeConverter            # assets/js/hooks/index.ts:998-1062
    - Copy                          # assets/js/hooks/index.ts:738-817, data-content path only
    - Tooltip                       # assets/js/hooks/index.ts:566-630, via Common.wrapper_tooltip (common.ex:377-397); "Copied!" swap only
  policies: []
  workers: []
  api_endpoints: []
  emails: []
  config: []
  not_reachable_here:
    - Copy hook `data-to` target lookup (index.ts:749-761); datetime always sets data-content (common.ex:467, :490)
    - Copy hook `phx-then` execution (index.ts:801-806); datetime never sets phx-then
    - Tooltip hook `data-interactive` and `data-allow-html` options (index.ts:577-582); wrapper_tooltip does not set them

related:
  # views with an annotation; the first four already inherit this id
  - project-settings-history-exports   # data_tables.ex:310
  - history-channel-logs                # channel_logs_component.ex:176
  - run-show                            # run_live/show.ex:154, :162
  - channel-request-show                # channel_request_live/show.ex:228, :236
  - history-work-orders                 # workorder_component.ex:232, :235, :371-398; components.ex:464 via run_item (workorder_component.ex:429)
  - workflows-index                     # workflow_live/dashboard_components.ex:250, :340, :480
  # views not yet annotated; ids are proposals
  - projects-dashboard                  # dashboard_live/components.ex:136-139
  - profile                             # profile_live/components.ex:17
  - profile-tokens                      # tokens_live/index.html.heex:88, :95
  - settings-audit                      # audit_live/index.html.heex:21
  - dataclip-show                       # dataclip_live/show.ex:92, :100, :109
  - channels-index                      # channel_live/index.ex:382
flows: []
---

## 1. Purpose

Lightning stores every timestamp in UTC, but the people reading History, a run, an export list
or an audit trail are spread across time zones. This component shows each timestamp in the
viewer's own time zone so they can place an event in their day, and keeps the exact UTC value one
hover or click away so they can quote it to a colleague, a support ticket or a log search.
Without it, people do time zone arithmetic in their heads and get it wrong.

## 2. What it does

- Anyone sees a timestamp converted to their browser's time zone
- Anyone sees the year when a timestamp is from a different year
- Anyone sees seconds where the host page asks for detailed relative time
- Anyone hovering a timestamp sees the exact UTC value
- Anyone clicking a timestamp copies the exact UTC value and is told it was copied
- Anyone sees a placeholder when the host page passes no timestamp

## 3. Who can do what

| Action | Viewer | Editor | Admin | Owner | Superuser | Support |
|--------|--------|--------|-------|-------|-----------|---------|
| See a timestamp | yes | yes | yes | yes | yes | yes |
| See the UTC tooltip | yes | yes | yes | yes | yes | yes |
| Copy the UTC timestamp | yes | yes | yes | yes | yes | yes |

**Preconditions beyond role**
- Visibility is whatever the host page allows; the component checks nothing (common.ex:422-498).
- Copying uses the browser clipboard, so the browser must allow `navigator.clipboard.writeText` or `document.execCommand('copy')` (index.ts:763-777, :782-799).

## 4. What it touches

**Reads**: none; the host page passes the value in (`attr :datetime`, common.ex:399)

**Writes**: none

**Immediate side effects** (in the same request)
- none

**Deferred side effects** (later, elsewhere)
- none

**External, non-transactional effects**
- Writes the UTC string to the viewer's clipboard on click (index.ts:763-777)

**Depends on config**
- none in the app; the displayed value depends on the browser's time zone (`new Date`, index.ts:1017-1018) and is always English, 12-hour (`enUS`, index.ts:947-969, :971-996)

**Product limits**
- none

## 5. Scenarios

```gherkin
Feature: Local date and time display
  In order to know when something happened without converting time zones
  As anyone reading a timestamp in Lightning
  I want timestamps in my local time, with the exact UTC value on hover and on click

  @S01 @pending
  Scenario: A timestamp is shown in the viewer's time zone
    # Value: people place a run or export in their own working day without time zone arithmetic.
    Given my browser's time zone is "Africa/Blantyre" (UTC+2)
    And a host page renders a timestamp of "2026-10-14 08:30:00 UTC" with the default format
    And today is 2026-10-14 in that time zone
    When the page loads
    Then the timestamp reads "today at 10:30 AM"
    # common.ex:404-406 default :relative; common.ex:454-457 data-format, data-iso-timestamp
    # index.ts:1007-1013, :1036-1039 formatRelative with relativeLocale; index.ts:1046-1050 replaces the text
    # index.ts:950-955 'today at' p

  @S02 @pending
  Scenario: A timestamp from another year shows the year
    # Value: an old timestamp is not mistaken for one from this year.
    Given a host page renders a timestamp of "2024-03-05 08:30:00 UTC" with the default format
    And the current year is 2026
    When the page loads
    Then the timestamp starts with "2024-03-05,"
    # index.ts:956-960 other: 'yyyy-MM-dd, p' when the year differs, 'MMMM do, p' otherwise

  @S03 @pending
  Scenario: Detailed relative time shows seconds
    # Value: on a run's timeline (created, claimed, started, finished) people can see how long it queued and ran, which minute resolution hides.
    Given a host page renders a timestamp of "2026-10-14 08:30:07 UTC" with the format "relative_detailed"
    And my browser's time zone is UTC
    And today is 2026-10-14
    When the page loads
    Then the timestamp reads "today at 8:30:07 AM"
    # index.ts:1026-1030, :975-980; used by workorder_component.ex:371-398
    # test/lightning_web/live/work_order_live_test.exs:599-600 asserts the data-iso-timestamp for claimed and started

  @S04 @pending
  Scenario: Hovering a timestamp shows the exact UTC value
    # Value: people get an unambiguous time to quote to colleagues in other time zones or to match against server logs.
    Given a host page renders a timestamp of "2026-10-14 08:30:07 UTC"
    When I hover the timestamp
    Then a tooltip shows "2026-10-14 08:30:07 UTC"
    And the tooltip says "Click to copy timestamp"
    # common.ex:447-452 wrapper_tooltip with the UTC string and subtitle; common.ex:377-397; index.ts:584-592
    # test/lightning_web/live/dashboard_live_test.exs:531-537 asserts data-iso-timestamp in "%Y-%m-%d %H:%M:%S UTC" form

  @S05 @pending
  Scenario: Clicking a timestamp copies the UTC value
    # Value: people paste the exact time into a support ticket or log search instead of retyping a converted time.
    Given a host page renders a timestamp of "2026-10-14 08:30:07 UTC"
    When I click the timestamp
    Then my clipboard contains "2026-10-14 08:30:07 UTC"
    And the tooltip briefly reads "Copied!"
    # common.ex:440, :466-467 Copy hook with data-content = UTC string
    # index.ts:742-777 copy; index.ts:808-816 show-copied; index.ts:595-606 "Copied!" for 1.5s

  @S06 @pending
  Scenario: Sub-second timestamps keep milliseconds
    # Value: two events in the same second can still be told apart and ordered when matched against logs.
    Given a host page renders a DateTime of "2026-10-14 08:30:07.123456Z"
    When I hover the timestamp
    Then the tooltip shows "2026-10-14 08:30:07.123 UTC"
    And clicking it copies "2026-10-14 08:30:07.123 UTC"
    # common.ex:425-429 microseconds truncated to milliseconds for %DateTime{} with microseconds > 0

  @S07 @pending
  Scenario: A missing timestamp shows a placeholder
    # Value: something that hasn't happened yet reads as not happened, not as a blank cell or a bogus date.
    Given a host page renders the component with no timestamp
    When the page loads
    Then I see "--" in grey
    And there is no tooltip and nothing to copy
    # common.ex:444-445
```

## 6. Unclear value

### 6.1 Possible bugs

| What | Where | What a user sees | Disposition |
|------|-------|------------------|-------------|
| The value handed to `new Date()` is "YYYY-MM-DD HH:MM:SS UTC", not ISO 8601, so parsing is up to the browser engine; if one returns Invalid Date, `format` throws, the error is swallowed and the placeholder stays. Not verified in any browser | `common.ex:428`, `:432`; `index.ts:1018`, `:1051-1053` | a grey bar where the time should be (tooltip branch, `common.ex:469`) | fix |
| The DOM id is random on every render, so any re-render of the host (a live update on History, for example) replaces the element and remounts all three hooks | `common.ex:438`, `:449`, `:454`, `:460` | an open tooltip or the "Copied!" message can vanish when the row updates; not verified in a browser | fix |
| The execCommand fallback treats any non-throwing call as success, but `execCommand('copy')` signals failure by returning false | `index.ts:790-793` | "Copied!" when nothing was copied | fix |

### 6.2 Quirks and implementation details

| What | Where | Disposition |
|------|-------|-------------|
| The doc says `:relative` shows "2 hours ago"; it actually shows calendar-relative text ("today at 10:30 AM", "last Monday at ...") | `common.ex:411-413`; `index.ts:947-969` | decide |
| Display is always English with a 12-hour clock, whatever the viewer's locale | `index.ts:2`, `:947-948`, `:1023`, `:1033` | decide |
| Relative text is computed on mount and update only; "today at" stays "today" after midnight until the host re-renders | `index.ts:999-1005`, `:1017` | decide |
| Before the hook runs, the tooltip branch shows a grey 20-character bar with transparent server text, so there is no flash of the UTC value | `common.ex:469-471`; `index.ts:1049` | preserve |
| `time_only` shows the clock time without a date; used only for step start times inside a run on History | `index.ts:1032-1034`; `run_live/components.ex:464` | decide |
| Clicking a timestamp stops propagation, so on a row that navigates on click (projects dashboard) clicking the timestamp copies instead of opening the project | `index.ts:743-744`; `dashboard_live/components.ex:111-115`, `:136-139` | decide |
| The timestamp is `select-none`, so click-to-copy is the only way to take the text | `common.ex:462`, `:485` | decide |
| The millisecond branch matches only `%DateTime{}`; a `NaiveDateTime` with microseconds is shown to the second | `common.ex:426-432` | decide |
| A run's "Started" and "Finished" skip the component when nil, so run-show shows empty rather than "--" (owned by run-show 6.2) | `run_live/show.ex:153-163` | decide |

### 6.3 Unreachable or dead code

| What | Where | Why unreachable |
|------|-------|-----------------|
| `:detailed` format | `common.ex:406`; `index.ts:1022-1024` | no caller passes `format={:detailed}` (grep of `lib/lightning_web`) |
| `show_tooltip={false}` branch | `common.ex:475-492` | no caller sets it; only the doc example does (`common.ex:420`) |
| `id` attr | `common.ex:400`, `:438` | no caller passes it, and the component overwrites it with a random id anyway |

### 6.4 Performance and operational limits

| What | Where | User-visible? | Disposition |
|------|-------|---------------|-------------|
| "Copied!" shows for 1.5 seconds before the UTC tooltip returns | `index.ts:600-605` | yes | preserve |

### 6.5 Things seen but not understood

- `MiniHistory` in the collaborative editor imports `relativeLocale` from the hooks module and formats run times itself rather than through this component (`assets/js/collaborative-editor/components/diagram/MiniHistory.tsx:32`, `:246`). Whether the editor's run times should follow this annotation is not settled here.

## 7. Not migrating

| Item | Reason | Decided by | Date |
|------|--------|------------|------|

## 8. Open questions

- Should timestamps follow the viewer's locale (24-hour clock, translated words), or stay English 12-hour as today?
- Should the editor's MiniHistory run times (workflow-editor-run-viewer) be held to the same formats as this component?

## Proposed flows

none

## Proposed shared

none
