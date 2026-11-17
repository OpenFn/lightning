---
id: flow-workflow-api-edit-conflict
type: flow
title: Workflow changed through the API while open in the editor
owner:

trigger:
  entry: capability:api-workflows-update
  exit: workflow-editor-canvas
  surfaces:
    - workflow-editor-canvas # any editor panel; joining the room starts a Session that tracks presence (session.ex:125-133)
    - capability:api-workflows-update # PUT/PATCH /api/projects/:project_id/workflows/:id (router.ex:139-140; workflows_controller.ex:250-277)
    - controller:api-workflows-update # 409 back to the API caller (workflows_controller.ex:263, :279-283; api/fallback_controller.ex:55-65)
    - workflow-editor-canvas # after the editor closes: the API write lands and the next editor opens on it
    - workflow-editor-run-viewer # added by lead (link lint)
    - workflow-editor-new # added by lead (link lint)
    - workflow-editor-ai-assistant # added by lead (link lint)
    - workflow-editor-versions-and-promote # added by lead (link lint)
    - workflow-editor-ide # added by lead (link lint)
  reachable_when:
    - API side:
        a bearer token whose user may :edit_workflow on the project
        (router.ex:51-55, :139-140; workflows_controller.ex:99-100, :253-262)
    - editor side:
        somebody holds a collaboration Session on the workflow id, in any view
        (latest, version, release or run) (workflow_channel.ex:62-72;
        collaboration.ex:39-72; workflow_resolver.ex:161-199)

inherits:
  - shared-editor-session # join, presence avatars, persisted drafts, stale-draft reset (its S04); not repeated here

url_params: []

config_variants:
  default: {} # read under this variant; no hop reads config for the conflict itself

inventory:
  routes:
    - PUT   /api/projects/:project_id/workflows/:id  API.WorkflowsController
      :update
    - PATCH /api/projects/:project_id/workflows/:id  API.WorkflowsController
      :update
  events: []
  js_hooks: []
  policies:
    - Lightning.Policies.ProjectUsers (:edit_workflow)
  workers: []
  api_endpoints:
    - API.WorkflowsController#update
  emails: []
  config: []
  not_reachable_here:
    - Presence.list_presences_for/1, build_presences_summary/2,
      new_user_presence/3 (presence.ex:37-43, :113-119, :176-212); not used by
      the conflict check (see 6.3)
    - API.WorkflowsController#create, #index, #show (no presence check; not this flow)
    - Lightning.Projects.Provisioner workflow writes (provisioner.ex:93-172); no
      presence check (see 6.5)

related:
  - lib/lightning_web/controllers/api/workflows_controller.ex
  - lib/lightning_web/controllers/api/fallback_controller.ex
  - lib/lightning/workflows/presence.ex
  - lib/lightning/collaboration.ex
  - lib/lightning/collaboration/session.ex
  - lib/lightning/collaboration/persistence.ex
  - lib/lightning/collaboration/workflow_reconciler.ex
  - lib/lightning/collaboration/workflow_resolver.ex
  - lib/lightning/workflows.ex
  - lib/lightning_web/channels/workflow_channel.ex
  - test/lightning_web/controllers/api/workflows/refusals_test.exs
  - test/lightning/collaboration/session_test.exs
flows: []
---

## 1. Purpose

Teams update workflows from scripts and integrations through the workflows API
while colleagues may have the same workflow open in the editor. The API refuses
the write while anyone holds it open, so a script cannot overwrite a workflow
under someone mid-edit, or have its change silently undone by that person's next
save. The API caller needs a clear refusal it can retry later.

## 2. What it does

1. Someone has a workflow open in the editor.
2. A script or integration with editor rights tries to update that workflow
   through the workflows API.
   - The API refuses with a 409 `being_edited` conflict ("This workflow is open
     in the editor."), saves nothing, and the person in the editor sees nothing.
3. Once everyone has closed the workflow, the same call goes through.
4. The next person to open the editor sees the API's version, and any unsaved
   draft left from before is gone.

**Straightforwardness: 3 of 5.** A simple lock on paper, but what counts as
"being edited" is much broader than the message suggests, and other ways of
changing the workflow skip the lock entirely.

### Most surprising behaviours

- **(2)** Any session on the workflow counts as it being open: an old version, a
  run, even the API caller's own idle tab. The script can be told someone is
  editing when nobody is typing. (6.1, 6.2)
- **(2)** Deploys from the CLI and GitHub sync don't check the lock at all; they
  write straight into the open editor, so only this one API is protected. (6.5)
- **(3)** A tab closed without a clean disconnect keeps blocking the API for a
  while after the last person has left. (6.4)
- **(3)** Unsaved edits someone left in a closed editor are silently dropped
  once the API saves its change. (S03)

## 3. Who can do what

Source: `lib/lightning/policies/project_users.ex:39-42`, `:166-172` via
`workflows_controller.ex:99-100`, `:253-262` (who may call the API);
`workflow_channel.ex:62-72`, `:2255-2300` and `policies/workflows.ex:14-21` (who
can open the editor). The conflict check counts any session on the workflow id
(`presence.ex:124-129`).

| Action                            | Viewer                | Editor | Admin | Owner | Superuser (no row) | Support (no row)               |
| --------------------------------- | --------------------- | ------ | ----- | ----- | ------------------ | ------------------------------ |
| Update a workflow through the API | no (403)              | yes    | yes   | yes   | no (403)           | yes, when support access is on |
| Be told about a refused API write | n/a (API caller only) |        |       |       |                    |                                |

**Preconditions beyond role**

- The token's grant, the caller's standing and role on the path's project, and
  the workflow lookup all run before the conflict check, so a caller without
  edit rights, or a workflow in another project, gets 403 or 404, never 409. The
  conflict check runs before the body is read, so an open workflow answers 409
  even to a body that isn't valid (`workflows_controller.ex:99-100`, `:253-264`;
  `refusals_test.exs:283-295`).
- The caller's own open editor tab blocks their own API write; presence is not
  filtered by user (`presence.ex:124-129`; tests `refusals_test.exs:236-265`
  track the caller's own user).

## 4. What it touches

**Reads**

- Hop 1, editor: on join, `Session.init` tracks presence on
  `workflow-<id>:presence` with the user and `joined_at` (`session.ex:125-133`;
  `presence.ex:64-74`, `:237`)
- Hop 2, API: `projects`, `project_users` (`workflows_controller.ex:253-262`,
  via `API.Target`, `api/target.ex:44-50`); `workflows`, `jobs`, `triggers`,
  `edges` (`workflows_controller.ex:259-261`); the Phoenix.Presence list for the
  topic (`presence.ex:124-129`)

**Writes**

- Hop 2 when refused: none (`workflows_controller.ex:263`, `:279-283`)
- Hop 3 when nobody holds it: `workflows` (`lock_version` bumped by
  `optimistic_lock`), `jobs`, `triggers`, `edges`, `workflow_snapshots`,
  `audit_events` on state change (`workflows_controller.ex:287-294`;
  `workflows.ex:200-257`, `:328-351`; `workflow.ex:98`)

**Immediate side effects** (in the same request)

- Hop 2: none; no broadcast, log or message to the open editor
- Hop 3: `WorkflowUpdated` on `workflow_events:<project_id>` and save telemetry
  (`workflows.ex:513-516`); reconcile into the live document is a logged no-op
  because no document is open (`workflows.ex:521-526`;
  `workflow_reconciler.ex:39-48`)

**Deferred side effects** (later, elsewhere)

- Lock release: presence drops when the Session stops, which follows its channel
  process going down (`session.ex:140-158`, `:457-473`); Phoenix.Presence also
  drops it when the tracked process exits
- Hop 4: the next editor to open finds the persisted draft's `lock_version`
  behind the database and rebuilds the document from the database
  (`persistence.ex:114-135`, `:146-149`; owned by shared-editor-session S04)

**External, non-transactional effects**

- none

**Depends on config**

- none

**Product limits**

- The lock lasts as long as any editor session on the workflow
  (`presence.ex:124-129`; `session.ex:457-473`)

## 5. Scenarios

```gherkin
Feature: Workflow changed through the API while open in the editor
  In order to keep scripted updates and people editing in the app from overwriting each other
  As an API client updating a workflow
  I want my write refused while someone has the workflow open

  @S01
  Scenario Outline: An API update is refused while the workflow is open in the editor
    # Value: a script can't overwrite a workflow under someone who is editing it, or have its change undone by their next save.
    Given "amara@example.org" has "Intake" open in the editor
    And I hold an API token for an editor on the project
    When I send a <method> to "/api/projects/<project_id>/workflows/<Intake id>" renaming it to "Intake v2"
    Then the response status is 409
    And the response body is a problem document with status 409, title "Conflict", code "being_edited" and detail "This workflow is open in the editor."
    And "Intake" is still named "Intake" with its lock version unchanged
    And the open editor still shows "Intake" with no new message
    # session.ex:125-133; presence.ex:64-74, :124-129; workflows_controller.ex:250-283; api/fallback_controller.ex:55-65; api/codes.ex:29
    # refusals_test.exs:236-265 (PATCH), :300-331 (PUT); both simulate the editor with Presence.track_user_presence, not a real Session
    Examples:
      | method |
      | PATCH  |
      | PUT    |

  @S02
  Scenario: The lock lifts when the editor closes
    # Value: automated updates resume once nobody is editing, without anyone having to release a lock by hand.
    Given "amara@example.org" had "Intake" open in the editor
    And my PATCH renaming it to "Intake v2" was refused with 409
    When "amara@example.org" closes the tab
    And I send the same PATCH again
    Then the response status is 200
    And the response body's workflow is named "Intake v2"
    # session.ex:140-158, :457-473; workflows_controller.ex:263-277; workflows.ex:200-257
    # session_test.exs:147-182 asserts presence is listed while sessions live; no test asserts it drops

  @S03
  Scenario: The next person to open the editor sees the API's change, not an old draft
    # Value: a draft left in the editor can't be saved back over a change made through the API.
    Given "amara@example.org" renamed a job in "Intake" without saving and closed the tab
    And I renamed "Intake" to "Intake v2" through the API
    When "amara@example.org" opens "Intake" in the editor again
    Then the editor shows "Intake v2"
    And the unsaved job rename is gone
    # workflow.ex:98; workflow_reconciler.ex:44-48; persistence.ex:114-135, :146-149
    # mechanism owned by shared-editor-session S04; this asserts the API entry into it

  @S04
  Scenario: An API update that lost a race with another save is refused with a conflict
    # Value: a script whose write was overtaken by another save is told to fetch the workflow again, instead of getting a server error.
    Given I hold an API token for an editor on the project
    And another save of "Intake" is committed after my request read it and before it wrote
    When I send a PATCH to "/api/projects/<project_id>/workflows/<Intake id>" renaming it to "Intake v2"
    Then the response status is 409 with code "concurrent_edit"
    And the detail reads "Another request changed or deleted this record. Fetch it again and retry."
    # workflows.ex:329-335, :476-483; api/fallback_controller.ex:51-62; api/codes.ex:30-32; workflows_controller.ex:255-285
```

## 6. Unclear value

### 6.1 Possible bugs

| What                                                                                                                                                       | Where                                                                                                             | What a user sees                                                      | Disposition                                        |
| ---------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------- | -------------------------------------------------- |
| The 409 detail says the workflow is "open in the editor", and any session counts: someone looking at an old version or a run, or the caller's own idle tab | `api/codes.ex:29`; `workflow_channel.ex:67-72` (`view_only?` sessions still track presence, `session.ex:125-133`) | an API caller told someone has the workflow open when nobody can edit | decide (tied to the 6.2 row on read-only sessions) |

### 6.2 Quirks and implementation details

| What                                                                                                                                                                                                                                                                    | Where                                                                                     | Disposition |
| ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------- | ----------- |
| Presence is tracked on the workflow id whatever the view, so version, release and run views count as the workflow being open                                                                                                                                            | `session.ex:125-133`; `workflow_resolver.ex:161-199`; `workflow_channel.ex:2152-2160`     | decide      |
| The gate is check-then-act: presence is read, then the save runs with reconcile on; an editor joining in between gets the API change reconciled into its live document without the `workflow_saved` baseline refresh (same gap as flow-toggle-workflow-open-editor 6.1) | `workflows_controller.ex:263-274`; `workflows.ex:521-526`; `workflow_reconciler.ex:50-55` | decide      |
| Presence is a cluster-wide CRDT, so an editor on another node blocks the call once its join has replicated                                                                                                                                                              | `presence.ex:8-10`, `:124-129`                                                            | preserve    |
| `track_user_presence` also subscribes the Session to the presence topic; every join and leave on the workflow lands in the Session's catch-all and is logged at debug                                                                                                   | `presence.ex:73`; `session.ex:477-481`                                                    | decide      |
| The 409 is a fixed message that names neither the workflow nor who has it open                                                                                                                                                                                          | `api/codes.ex:29`; `api/problem.ex:96-110`                                                | preserve    |

### 6.3 Unreachable or dead code

| What                                                                                                             | Where                                              | Why unreachable                                                                                                                      |
| ---------------------------------------------------------------------------------------------------------------- | -------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------ |
| `Presence.list_presences_for/1`, `build_presences_summary/2`, `new_user_presence/3` and the `%Presence{}` struct | `presence.ex:16`, `:37-43`, `:113-119`, `:176-235` | no caller in `lib/`; only `session_test.exs:178` uses `list_presences_for`. Leftover from the LiveView editor's edit-priority banner |
| `untrack_user_presence/3` with a `%Workflow{}`                                                                   | `presence.ex:96-98`                                | the Session passes the id (`session.ex:152-156`)                                                                                     |

### 6.4 Performance and operational limits

| What                                                                                                            | Where                        | User-visible?                                     | Disposition |
| --------------------------------------------------------------------------------------------------------------- | ---------------------------- | ------------------------------------------------- | ----------- |
| A tab closed without a clean disconnect holds the lock until the socket times out and the channel process exits | `session.ex:104`, `:457-473` | yes, a 409 for a while after the last person left | preserve    |

### 6.5 Things seen but not understood

- The canvas S29 Value line says "a deploy" can't overwrite an open workflow,
  but the CLI deploy and GitHub sync go through `/api/provision`
  (`router.ex:133-134`), whose provisioner reconciles into the live document
  instead of checking presence (`provisioner.ex:93-104`, `:157-161`). Only the
  workflows API is gated.
- `POST /api/projects/:project_id/workflows` with the id of a brand-new workflow
  still open unsaved in the editor (a Session already tracks presence on that
  id, `workflow_resolver.ex:82-95`) has no presence check
  (`workflows_controller.ex:168-191`); what the open editor does when that id
  then appears in the database is unread.
- Neither controller test starts a real Session; they track presence on the test
  process (`refusals_test.exs:249`, `:315`). No test joins the channel and then
  calls the API.

## 7. Not migrating

| Item | Reason | Decided by | Date |
| ---- | ------ | ---------- | ---- |

## 8. Open questions

- Should version and run views count as the workflow being open (see 6.1, 6.2)?
- Should the open editor be told that an API write was refused, or offered a way
  to release the lock?
- Should `/api/provision` honour the same lock, or is reconciling into the live
  document the intended behaviour for deploys (see 6.5)?

## Proposed flows

none

## Proposed shared

none

<!--
Summary
- Scenarios: 3 (S01 outline with 2 examples)
- Section 6: 6.1 one, 6.2 five, 6.3 two, 6.4 one, 6.5 three
- Flows: none proposed; referenced flow-toggle-workflow-open-editor (6.2)
- Shared: inherits shared-editor-session; none proposed
- Unsure: surfaces lists capability:api-workflows-update and controller:api-workflows-update for the same action because no capability annotation exists yet; the provisioner gap may deserve its own flow
-->
