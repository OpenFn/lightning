---
id: shared-dataclip-body-viewer
type: shared
title: Dataclip body viewer
status: not-started
owner:

trigger:
  old_route: any surface that mounts the DataclipViewer React component (assets/js/react/components/DataclipViewer.tsx), which fetches get /dataclip/body/:id (DataclipController.show)
  new_route:
  old_route_disposition: unchanged
  reachable_when:
    - the host has already decided a body should be shown; the component only takes a dataclip id (DataclipViewer.tsx:32) and knows nothing about wiping
    - dataclip-show renders it through `Viewers.dataclip_viewer` only when the dataclip is not wiped (dataclip_live/show.ex:122-144; viewers.ex:206-210)
    - run-show renders it for the selected step's input and output through `Viewers.step_dataclip_viewer`, only when the step has a dataclip that is not wiped (viewers.ex:243-288)
    - workflow-editor-run-viewer renders it in the Input and Output tabs whenever the selected step has a dataclip id (InputTabPanel.tsx:28-42; OutputTabPanel.tsx:28-42)
    - workflow-editor-manual-run renders it as the preview of a selected existing input (manual-run/SelectedDataclipView.tsx:167-170)

inherits:
  - shared-authenticated-session    # the endpoint sits behind :require_authenticated_user (router.ex:189-201)
  - shared-project-scope            # :view_dataclip is :access_project on the dataclip's own project (policies/dataclips.ex:20-22); role, support access and MFA semantics are owned there

url_params: []                      # the dataclip id is a path segment of the endpoint, supplied by the host, never by a page URL

config_variants:
  default: {}                       # read under this one

inventory:
  routes: []
  events: []
  js_hooks:
    - "ReactComponent DataclipViewer (HeexReactComponent island; viewers.ex:200-210, the attrs at :200-201 bind to the jsx-generated DataclipViewer/1, react.ex:70-80; test helper workflow_live_helpers.ex:688-691)"
  react_components:
    - react/components/DataclipViewer.tsx DataclipViewer
    - react/components/CodeViewer.tsx CodeViewer (read-only Monaco, copy button)
  policies:
    - Lightning.Policies.Dataclips :view_dataclip            # dataclip_controller.ex:19-24; policies/dataclips.ex:20-22
  workers: []
  api_endpoints:
    - get /dataclip/body/:id  DataclipController :show       # router.ex:201; dataclip_controller.ex:16-101
  emails: []
  config: []
  not_reachable_here:
    - DataclipController :search, :show_for_run, :update_name (dataclip_controller.ex:103-292); editor manual run only, owned by workflow-editor-manual-run
    - Viewers.step_dataclip_viewer wiped panel, "No input state could be saved for this run." and "Nothing yet" branches (viewers.ex:243-283); owned by run-show
    - InputTabPanel and OutputTabPanel placeholders "Select a step to view input data", "No ... state could be saved for this run.", "Nothing yet" (InputTabPanel.tsx:19-40; OutputTabPanel.tsx:19-40); owned by workflow-editor-run-viewer
    - CollectionPreviewViewer, a second CodeViewer host that passes a separate copyContent (CollectionPreviewViewer.tsx:49-62; viewers.ex:212-222); owned by project-settings-collections
    - DataclipScrubber.scrub_dataclip_bodies! (dataclip_scrubber.ex:48-109); the batch scrubber for the history export, not this endpoint
    - getDataclipBody (collaborative-editor/api/dataclips.ts:175-183), a second caller of the endpoint that loads a run's input for "Edit in sandbox" (EditInSandboxPicker.tsx:649-672); it gets the scrubbing and access rules here but none of the viewer behaviour

related:
  - dataclip-show                   # dataclip_live/show.ex:139-144
  - run-show                        # input and output tabs, viewers.ex:284-288; run_live/show.ex:263, :286
  - workflow-editor-run-viewer      # InputTabPanel.tsx:42; OutputTabPanel.tsx:42
  - workflow-editor-manual-run      # SelectedDataclipView.tsx:169
  - project-settings-collections    # CodeViewer only, through CollectionPreviewViewer.tsx:61
  - workflow-editor-versions-and-promote   # endpoint only, through getDataclipBody in EditInSandboxPicker.tsx:656 (surface placement unverified)
  - lib/lightning_web/controllers/dataclip_controller.ex
  - lib/lightning/dataclip_scrubber.ex
flows: []
---

## 1. Purpose

Anyone diagnosing a run or preparing a manual run needs to read exactly what data went into or came
out of a step, or what a source system sent to a webhook. This viewer loads one dataclip's body,
formats it for reading and lets people copy it, while masking the credential and webhook secrets
that commonly end up echoed in that data. Without it, people would either be unable to see the
payload at all or would expose secrets to everyone who can read the project.

## 2. What it does

- Anyone who can open a host page reads a dataclip's body, formatted, in a read-only viewer
- Anyone copies the body to the clipboard
- Anyone sees a webhook request's data and request metadata together, with the webhook's secret masked
- Anyone sees a step's output with the credential values used in that run masked
- Nobody without access to the dataclip's own project can load its body, from any page
- Anyone is told when a body is missing or could not be loaded

## 3. Who can do what

Source: `Lightning.Policies.Dataclips :view_dataclip` (`dataclip_controller.ex:19-30`), which
delegates to `ProjectUsers :access_project` on the dataclip's project (`policies/dataclips.ex:20-22`;
`project_users.ex:134-136`, `:190-191`; `projects/scope.ex:112-120`, `:149-152`, `:166-169`, `:196-198`).

| Action | Viewer | Editor | Admin | Owner | Superuser (no row) | Support (no row) |
|--------|--------|--------|-------|-------|--------------------|------------------|
| Load a body (visibility) | yes | yes | yes | yes | no | yes, when the project allows support access |
| Copy a loaded body | yes | yes | yes | yes | no | yes, when the project allows support access |

**Preconditions beyond role**
- The check is made against the dataclip's own project, not the page the viewer sits on (`policies/dataclips.ex:20-22`; `scope.ex:167`).
- Refused (403) when the project is scheduled for deletion (`scope.ex:149-152`; `dataclip_controller_test.exs:262-288`).
- Refused (403) when the project requires MFA and the user has not enrolled (`project_users.ex:134`; `scope.ex:221-224`; `project_mfa_enforcement_test.exs:150-160`, `:184-192`).
- Signed-out requests are sent to log in (`router.ex:189-190`; `dataclip_controller_test.exs:319-325`); unconfirmed accounts past the deadline are refused (`confirmation_lockout_recovery_test.exs:212-231`; owned by shared-authenticated-session).

## 4. What it touches

**Reads**
- `dataclips` without `body` and `request` for the policy check (`dataclip_controller.ex:17`; `invocation.ex:216-217`)
- `dataclips.body` as text, built in Postgres; `http_request` and `kafka` rows are wrapped as `{"data": body, "request": request}` (`dataclip_controller.ex:58`; `invocation.ex:128-143`; `query.ex:346-363`)
- For a `step_result`: the `steps` whose output it is, the credentials of every step in the same run that started no later than that step, with their current `credential_bodies` for the project env, and the webhook auth methods of the trigger that started the run (`dataclip_scrubber.ex:26-38`, `:215-231`, `:237-248`; `credentials.ex:1175-1187`, `:1209-1218`)
- For an `http_request`: the webhook auth methods of the trigger behind the work order it started (`dataclip_scrubber.ex:40-41`, `:270-279`; `webhook_auth_method.ex:128-166`)
- `projects`, `project_users`, `users` for the policy (owned by shared-project-scope)

**Writes**
- none

**Immediate side effects**
- Response headers `Cache-Control: private, max-age=86400`, `Vary: Accept-Encoding, Cookie`, `Last-Modified` from `updated_at` (`dataclip_controller.ex:72-77`)

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
Feature: Dataclip body viewer
  In order to see exactly what data a step or a webhook handled
  As anyone who can open a run, a dataclip or the workflow editor
  I want to read and copy a dataclip's body without exposing secrets

  @S01 @pending
  Scenario: The body is shown formatted and read-only
    # Value: people read the payload in a form they can scan, without any risk of changing stored data.
    Given a global dataclip whose body is {"patients":[{"id":1}]}
    When a host page shows it in the dataclip body viewer
    Then the viewer shows the body as JSON indented by two spaces
    And the viewer does not accept typing
    # DataclipViewer.tsx:32-46, :58; CodeViewer.tsx:79-100 (readOnly :85, tabSize :87, wordWrap :98)
    # DataclipViewer.test.tsx:67-77; hosts: dataclip_live/show.ex:139-144, viewers.ex:284-288, InputTabPanel.tsx:42, OutputTabPanel.tsx:42, SelectedDataclipView.tsx:169

  @S02 @pending
  Scenario: The body can be copied
    # Value: people lift the payload into a manual run, a test or a bug report without retyping it.
    Given the dataclip body viewer has loaded a body
    When I click the "Copy to clipboard" button
    Then the clipboard holds the body as displayed
    And the button is labelled "Copied to clipboard" for two seconds
    # CodeViewer.tsx:11-37, :41-46
    # CodeViewer.test.tsx:79-85, :109-125, :152-180

  @S03 @pending
  Scenario: A webhook request shows its data and request together, with the webhook secret masked
    # Value: people see what a source system actually sent without exposing the secret it authenticates with.
    Given workflow "Intake" has a webhook trigger protected by basic auth "webhook_user" with password "webhook_secret_pass"
    And a request to that webhook stored an http_request dataclip with an "authorization" header and data "test payload"
    When a host page shows that dataclip in the body viewer
    Then the viewer shows "data" and "request" keys
    And it shows "test payload"
    And it does not show "webhook_secret_pass" or the base64 of "webhook_user:webhook_secret_pass"
    And it shows "***" in their place
    # query.ex:346-363; dataclip_controller.ex:57-70; dataclip_scrubber.ex:40-41, :111-135; scrubber.ex:129-133, :144-167
    # dataclip_controller_test.exs:111-162

  @S04 @pending
  Scenario: A step's output masks credential values used earlier in the same run
    # Value: a job that echoes its own or an earlier step's configuration does not leak credential secrets to everyone who can read the project.
    Given a run where step "Login" used a credential with value "55"
    And step "Fetch" ran after it with a credential whose values include 123456 and "bar"
    And step "Post" ran after "Fetch" with another credential
    And "Fetch" produced an output dataclip containing 123456, 125534 and "some-bars"
    When a host page shows that output in the body viewer
    Then 123456 is shown as "***", 125534 as "12***34" and "some-bars" as "some-***s"
    And values in no credential, such as true, are shown unchanged
    # dataclip_controller.ex:62-70; dataclip_scrubber.ex:26-38, :215-231 (started_at <= at :227); scrubber.ex:50-55
    # dataclip_controller_test.exs:5-100 (setup), :164-178
    # the webhook auth methods of the run's trigger are also masked in step outputs (dataclip_scrubber.ex:37, :237-248); no test covers that

  @S05 @pending
  Scenario Outline: The body is refused to anyone without access to the dataclip's project
    # Value: a dataclip id seen in a link or a shared screen does not expose another project's data, or data on a project the user may no longer read.
    Given dataclip "D" on project "Kenya TB" with body {"patient":"record"}
    And <who>
    When the body viewer asks for "D"
    Then the response is 403 and carries no part of the body
    And the viewer shows "Failed to load content" with no copy button
    # dataclip_controller.ex:16-30; policies/dataclips.ex:20-22; DataclipViewer.tsx:18-23, :51-53; CodeViewer.tsx:41
    # dataclip_controller_test.exs:241-249, :262-288; project_mfa_enforcement_test.exs:150-160

    Examples:
      | who                                                                 |
      | I am not a member of "Kenya TB"                                     |
      | I am a viewer and "Kenya TB" is scheduled for deletion              |
      | "Kenya TB" requires MFA and I am a member who has not enrolled      |

  @S06 @pending
  Scenario Outline: A body that cannot be loaded says so
    # Value: people don't read an empty viewer as an empty payload.
    Given the body request for the dataclip <outcome>
    When the body viewer loads
    Then the viewer shows <message>
    # DataclipViewer.tsx:10-30, :48-53
    # DataclipViewer.test.tsx:84-123; dataclip_controller_test.exs:251-255 (404 for an unknown id)

    Examples:
      | outcome                      | message                   |
      | answers 404                  | "Dataclip not found"      |
      | answers 500                  | "Failed to load content"  |
      | fails on the network         | "Failed to load content"  |
```

## 6. Unclear value

### 6.1 Possible bugs

| What | Where | What a user sees | Disposition |
|------|-------|------------------|-------------|
| The viewer re-formats the body with `JSON.parse` and `JSON.stringify`, so integers beyond 2^53 are rounded, decimals like `1.0` lose their fraction, and numbers beyond the double range become `null`; the copy button copies the altered text. The server text from `jsonb` is exact (moved here from dataclip-show 6.1, which read it from code) | `DataclipViewer.tsx:41-46`; `CodeViewer.tsx:13`; `query.ex:354-355` | an id 12345678901234567890 shows and copies as 12345678901234567000 | fix |
| A masked number leaves invalid JSON (`"integer": ***`), so `JSON.parse` fails and the whole body is shown as the raw single-line `jsonb` text, unindented | `scrubber.ex:50-55`; `DataclipViewer.tsx:44-45`; `dataclip_controller_test.exs:172` asserts `"integer": ***` | any step output that contained a numeric credential value is one long wrapped line. Inferred from code | fix |
| Masking runs on the `jsonb` text, where a secret's newlines, quotes and backslashes are escaped, so a secret containing any of them (a PEM private key, a password with `"`) never matches | `query.ex:355`; `scrubber.ex:50-55`, `:129-133`; `credentials.ex:1121-1123` | the secret is shown in full in a step's output. Inferred from code | fix |
| Masking uses the credential's current values, not the values the run used | `dataclip_scrubber.ex:31-36`; `credentials.ex:1175-1187` | after a credential is rotated, old outputs show the old secret unmasked. Inferred from code | decide |
| No ignore flag or abort in the fetch effect, and content is not cleared when the id changes | `DataclipViewer.tsx:35-56` | switching steps quickly can leave the previous step's body showing, or a slower earlier response can overwrite the later one, under the newly selected step. Inferred from code | fix |
| The viewer has no notion of a wiped dataclip; hosts that don't check `wiped_at` show what the endpoint returns for a wiped row | `InputTabPanel.tsx:28-42`; `OutputTabPanel.tsx:28-42`; `query.ex:365-373`; `dataclip_controller.ex:77` | in the workflow editor run viewer, a wiped output reads `null` and a wiped webhook input reads `{"data": null, "request": null}`, with no retention message. Inferred from code | fix |
| A cached body survives a wipe and a loss of access: `max-age=86400` lets the browser reuse it without asking, and the wipe does not bump `updated_at`, so a revalidation answers 304 | `dataclip_controller.ex:14`, `:33-45`, `:72-90`; `query.ex:365-373` | for up to a day in the same browser session, a wiped body, or one from a project the user was removed from, can still show. Inferred from code | decide |
| The copy button hides only for "Failed to load content"; for "Dataclip not found" it shows and copies that message (moved here from dataclip-show 6.1) | `CodeViewer.tsx:41`; `DataclipViewer.tsx:48-50` | a copy button that puts an error message on the clipboard | fix |

### 6.2 Quirks and implementation details

| What | Where | Disposition |
|------|-------|-------------|
| Masking is plain substring replacement, so short credential values mask unrelated text and numbers (`some-bars` to `some-***s`, `125534` to `12***34`) | `scrubber.ex:50-55`; `dataclip_controller_test.exs:174-175` | decide |
| `saved_input`, `global` and `kafka` bodies are not masked; `kafka` is wrapped with its `request` like a webhook but the request is never masked (moved here from dataclip-show 6.2) | `dataclip_controller.ex:62-70`; `query.ex:353`; `dataclip_scrubber.ex:43-44`; `dataclip_controller_test.exs:302-317` | decide |
| The masking env is taken from the first credential row's project; all rows share one project, so it only matters if that ever changes | `dataclip_scrubber.ex:114-118` | preserve |
| Body keys appear in Postgres `jsonb` order, not the order the source sent them (moved here from dataclip-show 6.2) | `query.ex:346-363` | preserve |
| A stored body of `null` that is not wiped is sent and shown as the text `null` (moved here from dataclip-show 6.2) | `dataclip_controller.ex:77`; `dataclip_controller_test.exs:290-300` | preserve |
| While the body is loading the viewer is an empty editor with no copy button and no loading text; Monaco's own "Loading..." shows only while the editor bundle loads (moved here from dataclip-show 6.2) | `DataclipViewer.tsx:33`; `CodeViewer.tsx:41`, `:83` | decide |
| A 403 reads "Failed to load content" with no reason, the same as a network failure (moved here from dataclip-show 6.2) | `DataclipViewer.tsx:18-23`, `:51-53`; `dataclip_controller.ex:26-29` | decide |
| A malformed id raises a cast error before the policy runs (a 400 from the error handler, not a 404), which the viewer shows as "Failed to load content" | `dataclip_controller.ex:17`; `invocation.ex:217` | preserve |
| The copy button is an icon whose `title` is "Copy to clipboard" or "Copied!" and whose aria-label is "Copy to clipboard" or "Copied to clipboard"; it blurs itself on click | `CodeViewer.tsx:22-23`, `:41-46` | preserve |
| With no `navigator.clipboard` (an insecure origin), clicking copy does nothing and says nothing | `CodeViewer.tsx:15-37` | decide |
| The editor language is always `json`, word-wrapped, no minimap | `CodeViewer.tsx:79-100` | preserve |

### 6.3 Unreachable or dead code

| What | Where | Why unreachable |
|------|-------|-----------------|
| "Dataclip not found" on dataclip-show | `DataclipViewer.tsx:14-16`, `:48-50` | that page has already checked the dataclip exists; reachable there only if it is deleted between mount and fetch. Reachable in the editor hosts, which hold ids from earlier channel replies |
| Commented-out `Viewers.dataclip_viewer` in the dev components page | `live/dev/components_live.ex:48` | commented out |

### 6.4 Performance and operational limits

| What | Where | User-visible? | Disposition |
|------|-------|---------------|-------------|
| Bodies are cached privately for a day and answer `If-Modified-Since` with 304 against `updated_at` to the second; an unparseable date gets the body | `dataclip_controller.ex:14`, `:33-45`, `:72-101`; `dataclip_controller_test.exs:180-239` | no | preserve |
| The whole body is sent and loaded into the editor; no size cap or truncation (moved here from dataclip-show 6.4) | `dataclip_controller.ex:57-78`; `DataclipViewer.tsx:25` | yes, very large dataclips are slow to open | decide |
| The body is built as text in Postgres to avoid decoding it into an Elixir map; masking then splits it on newlines, of which `jsonb` text has none | `invocation.ex:128-143`; `scrubber.ex:129-133` | no | preserve |
| A `step_result` costs three queries per step behind it to resolve what to mask | `dataclip_scrubber.ex:26-38` | no | preserve |

### 6.5 Things seen but not understood

- dataclip-show 6.5 noted `attr :dataclipId, :map` on `dataclip_viewer`. The `jsx` macro defines `DataclipViewer/1` right after those attrs, so they declare the React island's props, not `dataclip_viewer`'s (`viewers.ex:200-210`; `react.ex:70-80`). `:map` is still the wrong type for a string id; it does not matter at runtime.
- Whether Monaco ever briefly shows the previous body under a new step in the LiveView hosts, where the island id is fixed per tab (`viewers.ex:286`), was not checked in a browser (see the race in 6.1).

## 7. Not migrating

| Item | Reason | Decided by | Date |
|------|--------|------------|------|

## 8. Open questions

- Should the viewer show the server's text as is, or format it without losing number precision (6.1)?
- Should masking keep the body valid JSON, and match secrets as they appear inside JSON strings (6.1)?
- Should masking use the credential values in force when the run happened (6.1)?
- Should the endpoint tell a wiped dataclip apart, so every host shows the retention message (6.1)?
- Is a day of private caching acceptable given wipes and access changes (6.1)?
- Should `saved_input` and `kafka` request bodies be masked, and should short secrets mask partial matches (6.2)?
- Should large bodies be capped or paged (6.4)?
- dataclip-show S03 to S06 and run-show S07's viewer steps restate S01 to S04 here; should they reduce to inheritance?

## Proposed flows

none

## Proposed shared

none (referenced: shared-project-scope, shared-authenticated-session)
