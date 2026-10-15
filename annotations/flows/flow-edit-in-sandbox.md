---
id: flow-edit-in-sandbox
type: flow
title: Edit a workflow in a sandbox
status: not-started
owner:

trigger:
  entry: workflow-editor-versions-and-promote    # header "Edit in sandbox" and EditInSandboxPicker (Header.tsx:836-858; EditInSandboxPicker.tsx:376-1127)
  exit: workflow-editor-canvas                   # the sandbox's copy of the same workflow
  surfaces:
    - workflow-editor-versions-and-promote       # picker: create a sandbox (with no input, the open run's reviewed input, or a saved input) or continue in one
    - workflow-editor-canvas                     # the sandbox's copy, opened by a LiveView navigate (react-component.tsx:80-86; EditInSandboxPicker.tsx:384-393)
    - workflow-editor-manual-run                 # only when an input was carried: panel=run&dataclip=<id> (EditInSandboxPicker.tsx:355-365)
    - sandboxes-index   # added by lead (link lint)
  reachable_when:
    - experimental features on for the viewer (Header.tsx:255-259)
    - the open workflow is live, saved, and not in a sandbox (Header.tsx:836)
    - no version is pinned (Header.tsx:850)
    - the viewer is editor or above on the open project to list or create (workflow_channel.ex:343-364, :367-406, :1979-1989)

inherits:
  - shared-authenticated-session
  - shared-project-scope            # S03 is where a join lands for someone not on the chosen sandbox; mount gates on the sandbox editor
  - shared-editor-session           # S20 the leave warning skipped on the way out
  - shared-dataclip-body-viewer     # access and scrubbing of the run input fetched for review (EditInSandboxPicker.tsx:649-656)

url_params:
  - name: panel=run
    set_by: EditInSandboxPicker, only when the create reply carries a dataclip id (EditInSandboxPicker.tsx:355-365)
    effect: the sandbox editor opens the run panel; with no job or trigger in the URL it opens on the first trigger (WorkflowEditor.tsx:121-155)
  - name: dataclip
    set_by: EditInSandboxPicker, the sandbox's copy of the carried input (EditInSandboxPicker.tsx:363; workflow_channel.ex:395-402)
    effect: preselected once in the run panel, then removed from the URL (ManualRunPanel.tsx:317-337; owned by workflow-editor-manual-run S24)

config_variants:
  experimental-features: { user.preferences.experimental_features: true }   # the flow only exists under this one; read under it
  sandbox-limited: { Lightning.Extensions.UsageLimiter: "limit_action(:new_sandbox) returns {:error, _, %Message{}}" }   # create refused, join allowed; owned by workflow-editor-versions-and-promote S28

inventory:
  routes:
    - live /projects/:project_id/w/:id  WorkflowLive.Collaborate :edit   # router.ex:303; both ends of the flow
  events:
    - WorkflowChannel#edit_in_sandbox      # workflow_channel.ex:367-406; picker detail owned by workflow-editor-versions-and-promote, this file owns what follows the reply
    - WorkflowChannel#list_sandboxes       # workflow_channel.ex:343-364; listing owned by workflow-editor-versions-and-promote S26, this file owns the join landing
  js_hooks:
    - ReactComponent redirect (react-component.tsx:80-86), passed to the editor as LiveViewActions (CollaborativeEditor.tsx:435, :456)
  policies:
    - Lightning.Policies.Sandboxes :provision_sandbox (policies/sandboxes.ex:94-96)
    - Lightning.Policies.ProjectUsers :access_project on the sandbox, through the mount and channel join (shared-project-scope)
  workers: []
  api_endpoints:
    - get /projects/:project_id/runs/:run_id/dataclip  DataclipController :show_for_run   # dataclip_controller.ex:211-244; called at EditInSandboxPicker.tsx:649
    - get /dataclip/body/:id  DataclipController :show                                 # router.ex:201; called at EditInSandboxPicker.tsx:656; owned by shared-dataclip-body-viewer
    - get /projects/:project_id/jobs/:job_id/dataclips  DataclipController :search      # dataclip_controller.ex:114-160; in the sandbox, where the carried input is found (ManualRunPanel.tsx:298-337)
  emails: []
  config:
    - user.preferences.experimental_features
    - Lightning.Config.max_sandbox_nesting_depth   # sandboxes.ex:268-271; refusal copy at workflow_channel.ex:1624-1631
    - Lightning.Config.max_dataclip_size_bytes     # reviewed input cap (sandboxes.ex:233-235)
  not_reachable_here:
    - the picker's choices, review step, name errors, limit lock and permission tooltip; owned by workflow-editor-versions-and-promote S21-S30
    - Sandboxes.provision/3 clone details (members, credentials, keychains, collections, triggers off); owned by sandboxes-index S07-S09 and following
    - the hard-navigation fallback with no LiveView (EditInSandboxPicker.tsx:367-374); listed in workflow-editor-versions-and-promote 6.2

related:
  - workflow-editor-versions-and-promote
  - sandboxes-index
  - workflow-editor-manual-run
  - flow-sandbox-merge                    # the way back: Promote from the sandbox's copy
  - lib/lightning_web/channels/workflow_channel.ex
  - lib/lightning/projects.ex
  - lib/lightning/projects/sandboxes.ex
  - lib/lightning/projects/environment.ex
  - lib/lightning/credentials/resolver.ex
  - lib/lightning/workflows.ex
  - lib/lightning_web/controllers/dataclip_controller.ex
  - lib/lightning/invocation/query.ex
  - assets/js/collaborative-editor/components/EditInSandboxPicker.tsx
  - assets/js/collaborative-editor/components/Header.tsx
  - assets/js/collaborative-editor/components/WorkflowEditor.tsx
  - assets/js/collaborative-editor/components/ManualRunPanel.tsx
  - assets/js/collaborative-editor/hooks/useDiscardGuard.tsx
  - assets/js/react/hooks/react-component.tsx
  - test/lightning_web/channels/workflow_channel_test.exs
  - test/lightning/projects_test.exs
  - assets/test/collaborative-editor/components/EditInSandboxPicker.test.tsx
  - assets/test/collaborative-editor/components/ManualRunPanel.test.tsx
flows:
  - flow-sandbox-merge
---

## 1. Purpose

People who look after a production workflow need to change it without touching what is live.
From the live workflow they fork it, or pick up an existing fork, and land on the copy ready to
edit, with the input that showed the problem already selected to run. Without this they would
edit production in place, or rebuild the context (sandbox, workflow, test data) by hand before
they could start, and might test against production systems by accident.

## 2. What it does

1. An editor looking at a live workflow chooses "Edit in sandbox" (only with experimental features turned on).
2. They either create a new sandbox or continue in an existing one that has a copy of this workflow.
   - A new sandbox can carry a starting input: the open run's input after they review it, or a saved input, which is copied into the sandbox.
   - If the workflow's copy can't be found, they see "Could not create a sandbox" and no stray sandbox is left behind.
3. They land in the editor on the sandbox's copy of the same workflow, editable, with its triggers off and production untouched.
   - If they carried an input, the run panel opens with it already selected; continuing in an existing sandbox carries nothing.
4. Runs in the new sandbox use the credentials' sandbox ("dev") values, not production's.
5. When they're done, "Promote" hands them on to merging the sandbox back.

**Straightforwardness: 3 of 5.** The idea is simple once explained, but where unsaved edits end up and which credentials a sandbox run uses both catch people out.

### Most surprising behaviours

- **(2)** If you have unsaved edits and choose "Save and switch", the sandbox is copied before the save, so your edits go to production and are missing from the sandbox you made for them. (6.1)
- **(2)** Runs in a sandbox made this way can't use a credential that has no "dev" value, so a fix tried with production data may simply fail until someone adds one. (S05, 6.5)
- **(3)** The list of sandboxes to continue in includes ones you aren't a member of; picking one doesn't get you in. (3)
- **(4)** The run panel opens titled "Pick a custom input" even though your carried input is already selected. (6.1)

## 3. Who can do what

Columns are the viewer's role on the project named in the row. Sources: `policies/sandboxes.ex:60-75`, `:94-96`;
`workflow_channel.ex:343-364`, `:367-406`, `:1979-1989`, `:1516-1528`; sandbox membership on create from sandboxes-index S08 (`sandboxes.ex:1065-1084`).

| Action | Viewer | Editor | Admin | Owner | Superuser (no row) | Support (no row) |
|--------|--------|--------|-------|-------|--------------------|------------------|
| Start the flow (flag on): role on the open project | no | yes | yes | yes | no | no |
| Land on a new sandbox's copy | n/a | yes, as owner of the new sandbox | yes, as owner | yes, as owner | n/a | n/a |
| Land on a listed sandbox's copy: role on that sandbox | yes, read-only | yes | yes | yes | no | no |
| Edit the landed copy: role on the sandbox | no | yes | yes | yes | no | no |

**Preconditions beyond role**
- Support access is never honoured by sandbox actions (`policies/sandboxes.ex:71-75`).
- A listed sandbox is offered whether or not the viewer is on it; without a membership the landing is shared-project-scope S03 (`projects.ex:2184-2202`; recorded in workflow-editor-versions-and-promote 6.1).
- A carried saved input must be named, not wiped, of type saved input, global or webhook request, and belong to the open project (`workflow_channel.ex:2027-2033`; `sandboxes.ex:166-189`).
- The plan's sandbox limit and the nesting cap gate creation only (`workflow_channel.ex:382`, `:2020-2025`; `sandboxes.ex:1015-1017`).

## 4. What it touches

**Reads**
- Hop 1, picker: `projects` (active sandboxes of the parent with their owner `project_users` and `users`), `workflows` by name in each (`projects.ex:2184-2217`); the open run's first input through `runs`, `steps`, `dataclips` (`dataclip_controller.ex:211-244`); its body (`router.ex:201`)
- Hop 1, create: the parent's `workflows`, `jobs`, `triggers`, `edges`, `project_credentials`, keychains, `collections`, the chosen `dataclips` row (`sandboxes.ex:1053-1060`, `:1574-1600`)
- Hop 2, sandbox editor: `projects`, `project_users`, `workflows` (mount and channel join, shared-project-scope); `dataclips` selectable for the first job, named project inputs included under the flag (`dataclip_controller.ex:114-160`; `query.ex:286-318`)

**Writes** (hop 1, create only; one transaction, `sandboxes.ex:1018-1051`)
- A `projects` row (env "dev", random colour, URL-safe name; `workflow_channel.ex:371-378`, `:2048-2056`) and everything `Sandboxes.provision/3` clones (sandboxes-index owns the detail)
- Every parent workflow copied as `state: :draft` with triggers off (`sandboxes.ex:1187-1205`, `:1257`)
- Starting input: a copy of the chosen saved input (`sandboxes.ex:1574-1609`), or a new `saved_input` from the reviewed body (`sandboxes.ex:1613-1620`)
- After commit, if the copy of the open workflow is missing: the sandbox is deleted again (`projects.ex:2400-2432`)

**Immediate side effects**
- Hop 1: `ProjectCreated` on `projects_events:all` (`projects.ex:572-574`); PromEx sandbox-created event (`sandboxes.ex:1045`)
- Hop 1, orphan cleanup: `ProjectDeleted` on `projects_events:all` (`projects.ex:916-925`); error log (`projects.ex:2412-2415`)
- Hop 2: `liveSocket` navigate to `/projects/<sandbox>/w/<copy>`, with `?panel=run&dataclip=<id>` when an input was carried (`EditInSandboxPicker.tsx:355-365`, `:384-393`; `react-component.tsx:80-86`)
- Hop 3, run panel: `dataclip` is stripped from the URL once honoured (`ManualRunPanel.tsx:317-321`)

**Deferred side effects**
- none

**External, non-transactional effects**
- none

**Depends on config**
- Experimental features flag on the viewer (entry, and named inputs in the sandbox run panel: `dataclip_controller.ex:146-150`)
- Usage limiter `:new_sandbox`; `max_sandbox_nesting_depth`; `max_dataclip_size_bytes`
- The sandbox's env "dev" decides which credential bodies its runs use (`environment.ex:71-77`; `resolver.ex:64-110`; `credentials.ex:1237-1240`)

**Product limits**
- The plan's sandbox limit and the nesting cap (owned by workflow-editor-versions-and-promote S28)

## 5. Scenarios

```gherkin
Feature: Edit a workflow in a sandbox
  In order to change a production workflow without touching what is live
  As an editor on the project
  I want to move from the live workflow to its copy in a sandbox, ready to edit and run

  @S01 @pending @variant:experimental-features
  Scenario: A new sandbox opens on its copy of the workflow, ready to edit
    # Value: the change starts at once on a copy, and production stays exactly as it was.
    Given "Intake" is live in project "Malawi HIV" and I am an editor there
    When I choose "Edit in sandbox", type "Trying dates" and choose "Create sandbox"
    Then I am in the workflow editor for "Intake" in sandbox "trying-dates"
    And the header shows the sandbox path and a "Promote" button, and no "Edit in sandbox" button
    And the canvas can be edited
    And its triggers are off
    And "Intake" in "Malawi HIV" is still live with its triggers as they were
    # workflow_channel.ex:367-406, :2048-2056; projects.ex:2400-2412; sandboxes.ex:1187-1205, :1257
    # EditInSandboxPicker.tsx:384-393, :589-603; Header.tsx:820-836; workflows.ex:166-170; workflow_channel.ex:1507-1510
    # workflow_channel_test.exs:914-950; projects_test.exs:4405-4430; workflow-editor-canvas S19 for the path

  @S02 @pending @variant:experimental-features
  Scenario: The run's reviewed input arrives selected in the sandbox's run panel
    # Value: a fix is tried against the data that broke production, without hunting for it in the sandbox.
    Given run "a1b2c3" is open in "Intake" and its input was kept
    When I start a new sandbox from "This run's input" and create it after reviewing the input
    Then I land on "Intake" in the new sandbox with the run panel open
    And "Input from run a1b2c3" is selected on the "Existing" tab, with my edits from the review
    And "dataclip" is no longer in the URL
    And the run's original input in "Malawi HIV" is unchanged
    # EditInSandboxPicker.tsx:355-365, :589-603, :686-699; workflow_channel.ex:395-402; sandboxes.ex:1613-1620
    # WorkflowEditor.tsx:121-155; ManualRunPanel.tsx:201-208, :298-337; dataclip_controller.ex:146-150; query.ex:286-318
    # EditInSandboxPicker.test.tsx:840-870 (path only); workflow_channel_test.exs:781-803; ManualRunPanel.test.tsx:408-442 (selection only)

  @S03 @pending @variant:experimental-features
  Scenario: A saved input arrives as the sandbox's own copy, selected to run
    # Value: a reusable test input travels with the fork, and changing it in the sandbox can't alter the parent's.
    Given "Malawi HIV" has saved input "Sample patient"
    When I start a new sandbox from "A saved input" with "Sample patient"
    Then I land on "Intake" in the new sandbox with the run panel open and "Sample patient" selected
    And the selected input belongs to the sandbox, not to "Malawi HIV"
    # EditInSandboxPicker.tsx:624-627; workflow_channel.ex:383, :2027-2033; sandboxes.ex:1574-1609
    # workflow_channel_test.exs:804-830 (copy has a new id, in the sandbox)

  @S04 @pending @variant:experimental-features
  Scenario: Continuing in an existing sandbox opens its copy of the same workflow
    # Value: people pick up a colleague's fork at the workflow they were looking at, not at the sandbox's front page.
    Given sandbox "fix-dates" of "Malawi HIV" has a copy of "Intake" and I am an editor on it
    When I choose "Edit in sandbox" and continue in "fix-dates"
    Then I am in the workflow editor for the "Intake" copy in "fix-dates"
    And no input is carried and the run panel is not opened
    And no new sandbox is created
    # workflow_channel.ex:343-364, :2070-2080; projects.ex:2184-2217; EditInSandboxPicker.tsx:701-710, :355-365
    # EditInSandboxPicker.test.tsx:1563-1582; workflow_channel_test.exs:581-697

  @S05 @pending @variant:experimental-features
  Scenario: Runs in a sandbox made from the editor use the credentials' dev values
    # Value: trying a fix with production data does not reach production systems through the parent's credentials.
    Given job "Send to DHIS2" in "Intake" uses credential "DHIS2" with a "main" value and no "dev" value
    And I created a sandbox from "Intake" with "Edit in sandbox"
    When I run "Intake" in that sandbox
    Then the run cannot use "DHIS2" and reports that it has no value for environment "dev"
    # workflow_channel.ex:373-378; environment.ex:40-46, :71-77; resolver.ex:64-110; credentials.ex:1237-1240
    # run_channel.ex:584-601; error_formatter.ex:34-42; no test follows this end to end

  @S06 @pending @variant:experimental-features
  Scenario: A copy that cannot be found does not leave a sandbox behind
    # Value: a failed attempt does not use up the plan's sandbox allowance or leave a stray sandbox in the list.
    Given I have "Intake" open and a colleague deletes it before I create a sandbox
    When I create a sandbox named "Trying dates"
    Then I see "Could not create a sandbox"
    And I stay on "Intake"
    And "Malawi HIV" has no sandbox "trying-dates"
    # workflow_channel.ex:2058-2063 (name read from the row, deleted or not); workflows.ex:132-142, :177-186; project.ex:50
    # projects.ex:2400-2432; EditInSandboxPicker.tsx:604-617; workflow_channel.ex:1616-1621
    # projects_test.exs:4432-4458 (cleanup with a missing name)

  @S07 @pending @variant:experimental-features
  Scenario: The way back is Promote, handed to the sandbox merge flow
    # Value: the fork made here can be shipped back to production from where the work was done.
    Given I landed on "Intake" in a sandbox through "Edit in sandbox"
    When I choose "Promote"
    Then the flow "flow-sandbox-merge" has started
    # Header.tsx:820-834; owned by flow-sandbox-merge S06 onwards
```

## 6. Unclear value

### 6.1 Possible bugs

| What | Where | What a user sees | Disposition |
|------|-------|------------------|-------------|
| The sandbox is cloned from the database before the unsaved changes prompt; "Save and switch" then saves those changes to the parent, so the new sandbox never has them | `EditInSandboxPicker.tsx:589-603`; `useDiscardGuard.tsx:44-53`; `sandboxes.ex:1187-1205` | their edits go to production and are missing from the sandbox they were saved "for" (how many edits survive the live content lock was not traced: `workflow_channel.ex:1507-1510`) | decide |
| The run panel opened for a carried input falls back to the first trigger with the custom input entry point, so its title is "Pick a custom input" while the carried input is selected on the "Existing" tab. Read from code | `WorkflowEditor.tsx:146-153`; `ManualRunPanel.tsx:189-190`, `:329-334` | a title that tells them to pick a custom input when one is already chosen | fix |
| The orphan cleanup deletes a sandbox after the sandbox-created metric has fired | `sandboxes.ex:1045`; `projects.ex:2411-2429` | operators' sandbox-created count includes sandboxes that never existed for the user | decide |

### 6.2 Quirks and implementation details

| What | Where | Disposition |
|------|-------|-------------|
| `ProjectCreated` is broadcast inside the provisioning transaction, before it commits, and nothing in `lib/` subscribes to it | `projects.ex:562-575`; `sandboxes.ex:1018-1043` | decide |
| A failed copy reports the generic "An internal error occurred" | `workflow_channel.ex:1616-1621`; `EditInSandboxPicker.tsx:70-77` | decide |
| A copied saved input keeps the parent's name and type, and a webhook request keeps its request; a reviewed body always becomes a "saved input" | `sandboxes.ex:1574-1609`, `:1613-1620` | preserve |
| The carried input is found through the first job's selectable list, which only includes named project inputs under the flag; it is the flag that makes the carry-over work | `ManualRunPanel.tsx:201-208`; `dataclip_controller.ex:146-150`; `query.ex:286-318` | preserve |
| If the copy has no trigger the run panel does not open and `dataclip` stays in the URL | `WorkflowEditor.tsx:147-154`; `ManualRunPanel.tsx:317-321` | decide |
| The orphan cleanup deletes synchronously through `ProjectHook.handle_delete_project`, not the scheduled deletion other sandboxes go through | `projects.ex:909-927`, `:2417-2427` | preserve |

### 6.3 Unreachable or dead code

| What | Where | Why unreachable |
|------|-------|-----------------|
| none | | |

### 6.4 Performance and operational limits

| What | Where | User-visible? | Disposition |
|------|-------|---------------|-------------|
| Listing sandboxes to continue in loads every active sandbox of the parent with its owner, unpaginated | `projects.ex:2184-2202` | no | preserve |

### 6.5 Things seen but not understood

- Whether parent credentials usually carry a "dev" value was not checked; if they rarely do, S05 means most runs from an editor-made sandbox fail until someone adds one (`workflow_channel.ex:376`; `credentials.ex:1237-1240`).
- No test follows the whole flow: the create reply, the navigate path and the run panel preselection are each tested on their own (`workflow_channel_test.exs:781-830`; `EditInSandboxPicker.test.tsx:840-870`; `ManualRunPanel.test.tsx:408-501`).

## 7. Not migrating

| Item | Reason | Decided by | Date |
|------|--------|------------|------|

## 8. Open questions

- Should "Save and switch" when creating a sandbox save before the clone, so the edits reach the sandbox rather than the parent (6.1)?
- Should a sandbox made from the editor really be fixed to env "dev", given S05 (also workflow-editor-versions-and-promote 6.2)?
- Should the landing panel title match the carried input (6.1)?

## Proposed flows

none

## Proposed shared

none

Summary
- Scenarios: 7 (S01-S07, all `@pending`, all `@variant:experimental-features`).
- Section 6: 6.1 three, 6.2 six, 6.3 none, 6.4 one, 6.5 two.
- Flows referenced: flow-sandbox-merge (way back). None proposed.
- Shared referenced: shared-authenticated-session, shared-project-scope (S03), shared-editor-session (S20), shared-dataclip-body-viewer. None proposed.
- Unsure: S05's failure copy and whether parent credentials have "dev" values; the reach of the 6.1 "Save and switch" row under the live content lock; S06 relies on a deletion race.
