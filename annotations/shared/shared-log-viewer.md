---
id: shared-log-viewer
type: shared
title: Run log viewer
status: not-started
owner:

trigger:
  old_route: any surface that mounts the log viewer component (assets/js/log-viewer/component.tsx) with its store (assets/js/log-viewer/store.ts)
  new_route:
  old_route_disposition: unchanged
  reachable_when:
    - the host has already decided the viewer may see the run; the component checks nothing itself
    - run-show renders it through `Viewers.log_viewer` and the `LogViewer` hook (show.ex:275-283; viewers.ex:52-117; log-viewer/index.ts:13-60)
    - the workflow editor run viewer renders it through `LogTabPanel`, only while the "Log" tab is active (RunViewerPanel.tsx:109; LogTabPanel.tsx:214-239)

inherits:
  - shared-project-scope            # who can open run-show; not repeated here
  - shared-authenticated-session    # the preference write needs a signed-in user

url_params: []                      # the `step` param that selects a step on run-show is owned by run-show; this file only reacts to the selected step

config_variants:
  default: {}                       # verified against this

inventory:
  routes: []
  events:
    - "RunLive.Show#save-log-filter (injected by RunLive.Streaming, streaming.ex:214-227)"
    - "RunChannel fetch:logs (run_channel.ex:277-293), the editor surface's initial load; the browser join is owned by workflow-editor-run-viewer"
    - "RunChannel push \"logs\" on LogAppended (run_channel.ex:315-318), the editor surface's live feed"
    - "push_event logs-<run_id> from RunLive.Show (streaming.ex:113-118, :140-150), the run page's feed; live delivery owned by flow-run-show-live-updates"
  js_hooks:
    - LogViewer                     # assets/js/log-viewer/index.ts; registered at app.js:35, :56; viewers.ex:95
  react_components:
    - log-viewer/component.tsx LogViewer (Monaco, read-only)
    - log-viewer/useMonacoSync.ts
    - collaborative-editor/components/run-viewer/LogTabPanel.tsx (editor host; its waiting animation is owned by workflow-editor-run-viewer)
    - collaborative-editor/components/run-viewer/LogLevelFilter.tsx
  policies:
    - Lightning.Policies.ProjectUsers :access_project   # evaluated by the hosts (shared-project-scope for run-show; RunChannel join, run_channel.ex:76, for the editor)
  workers: []
  api_endpoints: []
  emails: []
  config:
    - user.preferences.desired_log_level              # viewers.ex:54-60; streaming.ex:219-224
  not_reachable_here:
    - Viewers.log_viewer `:if={@current_user}` false branch (viewers.ex:84); run-show always passes current_user (show.ex:282)
    - LiveView waiting messages "Waiting for worker", "Creating runtime & installing adaptors", "Nothing yet" (viewers.ex:61-67); run-show only, owned by run-show S14
    - LogTabPanel typewriter waiting overlay (LogTabPanel.tsx:12-211, :331-360); editor only, owned by workflow-editor-run-viewer

related:
  - run-show
  - workflow-editor-run-viewer
  - workflow-editor-ide             # hosts RunViewerPanel in the full-screen IDE (FullScreenIDE.tsx:75, :1287)
flows:
  - flow-run-show-live-updates      # referenced; owns lines arriving live on run-show and the dedupe while loading (its S06, S07, S09)
---

## 1. Purpose

Anyone diagnosing a run reads what the job printed, because that is usually where the cause of a
failure is. The log viewer shows a run's log lines in order, lets people cut the noise by level, and
points at the lines of the step they selected. Without it, a long log from a multi-step workflow
would be unreadable, and people would scroll past the line that explains why health data didn't
arrive.

## 2. What it does

- Anyone who can open a run reads its log lines in time order, each prefixed with its source
- Anyone reads JSON a job logged as indented, multi-line text
- Anyone filters lines by level (debug, info, warn, error), starting at info
- On the run page, the chosen level is saved and applied to every run the person opens next
- Anyone who selects a step sees that step's lines marked and scrolled into view
- Anyone opening a finished run that logged nothing is told so

## 3. Who can do what

The component evaluates no policy. Visibility comes from the host: run-show via shared-project-scope
(`project_users.ex:29-50`, `:134`, `:160-169`), the editor run viewer via the RunChannel browser join
(`run_channel.ex:67-95`, `Permissions.can(ProjectUsers, :access_project, ...)` at `:76`).

| Action | Viewer | Editor | Admin | Owner | Superuser | Support |
|--------|--------|--------|-------|-------|-----------|---------|
| See the log | yes | yes | yes | yes | no | yes, when support access is on |
| Change the level filter | yes | yes | yes | yes | no | yes, when support access is on |
| Save the level as a preference (run page) | yes | yes | yes | yes | no | yes, when support access is on |

**Preconditions beyond role**
- The level preference is the signed-in user's own; `save-log-filter` writes only `socket.assigns.current_user` (`streaming.ex:219-224`).
- The editor surface needs the browser to have joined `run:<run_id>`; with no channel it shows no lines (`LogTabPanel.tsx:260-268`).

## 4. What it touches

**Reads**: `log_lines` for the run, ordered by `timestamp` (`runs.ex:569-573`); run-show streams them in chunks of 100 (`show.ex:3`; `streaming.ex:181-195`), the editor fetches them in one reply (`run_channel.ex:277-293`). Lines carry `id, source, level, message, timestamp, step_id, run_id` (`log_line.ex:30-31`). `users.preferences.desired_log_level` (`viewers.ex:54-60`)

**Writes**: `users.preferences` (merge of `desired_log_level`) on `save-log-filter` (`streaming.ex:214-227`; `accounts.ex:1417-1424`; `user.ex:383-386`)

**Immediate side effects**
- none (the preference update broadcasts nothing)

**Deferred side effects**
- none

**External, non-transactional effects**
- none

**Depends on config**
- none

**Product limits**
- none

## 5. Scenarios

```gherkin
Feature: Run log viewer
  In order to find out why a run behaved as it did
  As anyone who can open a run
  I want to read, filter and navigate its log

  @S01 @pending
  Scenario: Every logged line is shown once, in time order, with its source
    # Value: people read what happened in the order it happened, without duplicates that suggest a step ran twice.
    Given a finished run whose job logged "Posted batch 1" at 10:00:02 and "Fetched 12 patients" at 10:00:01 from source "JOB"
    And the line "Fetched 12 patients" is delivered to the viewer twice
    When I open its log on the run page or in the workflow editor run viewer
    Then I see "JOB Fetched 12 patients" followed by "JOB Posted batch 1"
    And "Fetched 12 patients" appears once
    # store.ts:130-133, :135-144, :158-173; component.tsx:94-117; useMonacoSync.ts:20-67
    # hosts: log-viewer/index.ts:35-44 (run page); LogTabPanel.tsx:270-296 (editor)
    # store.test.ts:22-38 (formatting), :40-70 (dedupe by id), :72-106 (sort), :126-144 (source prefix)

  @S02 @pending
  Scenario: JSON a job logged is shown indented
    # Value: a job that logs a payload can be read field by field instead of as one long line.
    Given a finished run whose job logged '{"patients":12,"status":"ok"}'
    When I open its log
    Then the line is shown across several lines with two-space indentation
    And a message that only looks like JSON but does not parse is shown as logged
    # store.ts:106-128, :130-133
    # store.test.ts:270-305

  @S03 @pending
  Scenario: The level filter hides lower-level lines
    # Value: people chasing an error can hide debug noise, and can bring it back when they need the detail.
    Given a finished run that logged a "debug" line and an "info" line
    And I have never chosen a log level
    When I open its log
    Then the filter reads "info" and only the "info" line is shown
    When I choose "debug"
    Then both lines are shown
    When I choose "warn"
    Then neither line is shown
    # store.ts:26-44, :135-144, :151-153, :185-216; viewers.ex:54-60, :124-198; LogLevelFilter.tsx:3, :62-72; LogTabPanel.tsx:84-90
    # store.test.ts:160-207; component.test.tsx:207; LogTabPanel.test.tsx:387-434

  @S04 @pending
  Scenario: On the run page the chosen level is remembered
    # Value: people who only care about warnings and errors don't have to re-filter every run they open.
    Given I am on the run page for run "R1"
    When I choose "debug" in the log filter
    Then my preference "desired_log_level" is "debug"
    And when I open the run page for run "R2", the filter reads "debug" and debug lines are shown
    # viewers.ex:54-60, :99, :167-171; streaming.ex:214-227; accounts.ex:1417-1424; log-viewer/index.ts:31, :47-49
    # no test covers save-log-filter

  @S05 @pending
  Scenario: Selecting a step marks its lines and brings them into view
    # Value: in a long log, people find the failing step's output without scrolling through every step.
    Given a finished run whose steps "Fetch" and "Transform" each logged several lines, "Fetch" first
    And the log has finished loading
    When I select "Transform"
    Then "Transform"'s lines are marked in the gutter
    And the log scrolls so that "Transform"'s first line is near the top
    When I clear the step selection
    Then no lines are marked
    # store.ts:46-95, :185-216; component.tsx:51-78; app.css:1004-1006
    # hosts: viewers.ex:98, log-viewer/index.ts:30, :48 (run page); LogTabPanel.tsx:242-244 (editor)
    # store.test.ts:215-266 asserts only that ranges exist, then clear

  @S06 @pending
  Scenario: A finished run that logged nothing says so
    # Value: people can tell a run that logged nothing from a log that is still loading.
    Given a run in state "lost" with no log lines
    When I open its log on the run page or in the workflow editor run viewer
    Then I see "No logs were received for this run."
    And no level filter is shown on the run page
    # viewers.ex:70-77; run.ex:46-55 (final states); LogTabPanel.tsx:305-306, :362-366; isFinalState in types/history.ts:92-94
    # viewer_test.exs:15-38
```

## 6. Unclear value

### 6.1 Possible bugs

| What | Where | What a user sees | Disposition |
|------|-------|------------------|-------------|
| Highlight ranges start one line early (a 0-based marker is passed to Monaco's 1-based `Range`) and `last.end <= nextMarker` is always true, so every later line of the step extends the first range across any lines in between (moved here from run-show 6.1) | `store.ts:78`, `:83-86`; `component.tsx:61-66` | the line before each step's first line is marked, and with run-level or parallel-branch lines interleaved, unrelated lines are marked too. Inferred from code | decide |
| Scroll to the selected step runs only when `stepId` changes; if the step is set before the lines arrive (opening a run page with `?step=`, or selecting a step before the editor's fetch returns), ranges are empty at that moment and nothing scrolls later | `component.tsx:51-57`; `log-viewer/index.ts:30`; `LogTabPanel.tsx:242-244` | the selected step's lines are marked but the log stays at the top. Inferred from code | fix |
| `save-log-filter` stores any client-sent string, and pattern-matches `{:ok, _}` on the update (moved here from run-show 6.1) | `streaming.ex:214-227`; `viewers.ex:56`, `:99`; `store.ts:26-44` | a forged level (for example "verbose") scores as unknown, so only `success` and `always` lines show on every run until changed; a failed update crashes the page | decide |
| The editor treats a failed `fetch:logs` (or a server-side transaction error, which replies `[]`) as an empty log | `LogTabPanel.tsx:283-285`, `:305-306`; `run_channel.ex:288-290` | a finished run that did log says "No logs were received for this run." Inferred from code | fix |
| The run page filter button is always `aria-expanded="true"` | `viewers.ex:142` | screen readers announce the level menu as open when it is closed | fix |

### 6.2 Quirks and implementation details

| What | Where | Disposition |
|------|-------|-------------|
| Lines at level `success` or `always` (or any unrecognised level) score above "error" and are shown whatever the filter (moved here from run-show 6.2) | `store.ts:26-44`; `log_line.ex:38-40` | decide |
| The editor's filter is not saved and always starts at "info", ignoring the preference the run page saves | `LogTabPanel.tsx:64-66`, `:84-90`; `store.ts:151-153` | decide |
| The run page applies a new level only after the server round trip re-renders `data-log-level` | `viewers.ex:99`, `:169`; `streaming.ex:226`; `log-viewer/index.ts:47-49` | preserve |
| The two hosts show different waiting copy for an unfinished run with no lines ("Waiting for worker" vs a typed "Waiting for a worker to establish a secure claim...") | `viewers.ex:61-67`; `LogTabPanel.tsx:17-41` | decide |
| There is no copy control; the read-only Monaco editor lets people select and copy text, which includes the source prefixes and the prettified JSON | `component.tsx:94-117`; `store.ts:130-133` | preserve |
| Lines with equal timestamps keep arrival order (stable sort) | `store.ts:167` | preserve |
| The source is coloured only when it is 2 to 4 capitals or slashes at the start of a line | `component.tsx:80-92` | preserve |
| The step marker is a thin yellow gutter bar, not a row background | `app.css:1004-1006`; `component.tsx:64-67` | preserve |
| Ranges and the filter are computed over the filtered text, so lines hidden by the level never count toward highlighting | `store.ts:58-61` | preserve |
| Long lines wrap; no folding, no minimap | `component.tsx:103-117` | preserve |

### 6.3 Unreachable or dead code

| What | Where | Why unreachable |
|------|-------|-----------------|
| The highlight event dispatch in `LogViewer.updated` | `log-viewer/index.ts:50-54` | commented out |
| Filter hidden when `current_user` is nil | `viewers.ex:84` | the only LiveView host always passes a user (`show.ex:282`) |
| The dev components page's log viewer variation | `components_live.ex:68-73`; `router.ex:370-379` | dev build only; it passes a `%Run{}` struct as `run_state`, so the final-state branch never renders |
| `log_viewer` doc example with `stream` and `highlight_id` attrs | `viewers.ex:30-36` | describes attrs the component no longer has |

### 6.4 Performance and operational limits

| What | Where | User-visible? | Disposition |
|------|-------|---------------|-------------|
| No cap on lines; every delivery re-sorts and re-stringifies the whole log, and highlight ranges are recomputed over every line | `store.ts:158-173`, `:185-216` | yes, on very long logs (also run-show 6.4, flow-run-show-live-updates 6.4) | decide |
| The editor loads the whole stored log in one channel reply | `run_channel.ex:277-293` | yes, on very long logs | decide |
| The editor never unmounts the Monaco root, while `LogTabPanel` itself unmounts on every switch away from the "Log" tab, so each return leaves an editor behind and refetches the whole log | `LogTabPanel.tsx:214-239`, `:247-301`; `RunViewerPanel.tsx:109` | no | decide |
| `useRef(createLogStore())` builds and subscribes a throwaway store on every render | `LogTabPanel.tsx:56` | no | decide |

### 6.5 Things seen but not understood

- The run page passes the selected step and level to the hook through data attributes on a `phx-update="ignore"` container (`viewers.ex:95-99`; `log-viewer/index.ts:47-49`). This relies on LiveView still patching the ignored container's own attributes; not checked in a browser.
- Whether the first `logs-<run_id>` event reaches a `LogViewer` hook created in the same patch, on a finished run switching from "No logs were received" to the viewer, was not verified (run-show 6.5, flow-run-show-live-updates 6.5).
- The lead's scope names "copy"; no copy button or clipboard call exists in either host (`assets/js/log-viewer/`, `components/run-viewer/`). Only Monaco's own selection copy was found (6.2).

## 7. Not migrating

| Item | Reason | Decided by | Date |
|------|--------|------------|------|

## 8. Open questions

- Should step highlighting be exact, and should run-level lines between a step's lines be marked (6.1)?
- Should the level be validated against the four offered levels, and should `success` and `always` lines obey the filter (6.1, 6.2)?
- Should the editor run viewer read and save the same level preference as the run page (6.2)?
- Does the rebuild need an explicit copy control, or is selection copy enough (6.2)?
- Should very long logs be capped or paged (6.4)?
- run-show S10 to S13 restate S01, S03 to S06 here, and its 6.1 and 6.2 rows on highlighting, `save-log-filter` and level scoring are now owned here; should run-show reduce them to inheritance?

## Proposed flows

- none (referenced: flow-run-show-live-updates, which owns lines arriving live on run-show; this file only owns how the store orders, dedupes, filters and marks them)

## Proposed shared

- none
