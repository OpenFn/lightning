---
id: flow-editor-credentials-broadcast
type: flow
title: A credential created elsewhere appears in an open editor
status: not-started
owner:

trigger:
  entry: workflow-editor-inspectors           # tab A; the only entry that broadcasts. credentials-index and project-settings-credentials are listed by the lead but send nothing (see 6.1)
  exit: workflow-editor-inspectors            # tab B, same workflow
  surfaces:
    - credentials-index                       # entry per lead scope; no broadcast, reaches tab B only through S03's refetch
    - project-settings-credentials            # entry per lead scope; same as above
    - workflow-editor-inspectors              # tab A: credential saved from "Configure connection" (collaborate.ex:393-430)
    - pubsub:workflow:collaborate:<workflow_id>#credentials_updated   # collaborate.ex:519-532
    - workflow-editor-inspectors              # tab B: channel forwards, store replaces the list (workflow_channel.ex:950-954; createCredentialStore.ts:295-303)
    - workflow-editor-ide   # added by lead (link lint)
  reachable_when:
    - sending side: the LiveView accepted `open_credential_modal` and rendered CredentialFormComponent with `on_save` (collaborate.ex:145-187, :289-324)
    - receiving side: a WorkflowChannel joined on exactly `workflow:collaborate:<workflow_id>`, i.e. the latest view of the same workflow, not a pinned version or release (workflow_channel.ex:44-55, :2152-2160)

inherits:
  - shared-editor-session                     # channel join, connection state, and the forwarders (workflow_channel.ex:950-969)
  - shared-adaptor-credential-config          # tab A's save, attach and reopen is its S11/S14; this flow owns only the other tab

url_params: []

config_variants:
  default: {}                                 # read under this variant; nothing on either hop reads config

inventory:
  routes:
    - live /projects/:project_id/w/:id  WorkflowLive.Collaborate :edit     # owned by workflow-editor-canvas
  events:
    - WorkflowLive.Collaborate handle_info {:credential_saved, _}          # collaborate.ex:393-430; owned by workflow-editor-inspectors, broadcast half asserted here
    - WorkflowChannel handle_info credentials_updated                      # workflow_channel.ex:950-954
    - WorkflowChannel "request_credentials"                                # workflow_channel.ex:119-132, :1273-1287
  js_hooks:
    - createCredentialStore channel.on("credentials_updated")              # createCredentialStore.ts:295-316
    - createCredentialStore requestCredentials on channel connect          # createCredentialStore.ts:306-308, :323-345; StoreProvider.tsx:233-246
  policies:
    - Lightning.Policies.ProjectUsers :create_project_credential           # project_users.ex:44; collaborate.ex:316-323
    - Lightning.Policies.Users :edit_credential                            # users.ex:40-44; collaborate.ex:156-162
    - Lightning.Policies.Credentials :create_keychain_credential           # owned by workflow-editor-inspectors
  workers: []
  api_endpoints: []
  emails: []
  config: []
  not_reachable_here:
    - CredentialFormComponent save without `on_save` (credentials-index, project-settings-credentials): flash and `push_navigate`, no broadcast (helpers.ex:160-169; credential_form_component.ex:1269-1276)
    - Credential scheduled deletion and keychain deletion from the credential list; owned by flow-credential-scheduled-deletion and shared-credential-index-component, no broadcast (credentials.ex:1036-1052, :2018-2030)
    - webhook_auth_methods_updated, the sibling broadcast on the same topic; owned by flow-webhook-auth-method-enforcement (collaborate.ex:534-561)

related:
  - lib/lightning_web/live/workflow_live/collaborate.ex
  - lib/lightning_web/live/credential_live/credential_form_component.ex
  - lib/lightning_web/live/credential_live/helpers.ex
  - lib/lightning_web/channels/workflow_channel.ex
  - lib/lightning_web/channels/workflow_json.ex
  - lib/lightning/projects.ex
  - lib/lightning/credentials.ex
  - assets/js/collaborative-editor/stores/createCredentialStore.ts
  - assets/js/collaborative-editor/contexts/StoreProvider.tsx
  - assets/js/collaborative-editor/components/inspector/JobForm.tsx
  - test/lightning_web/live/workflow_live/collaborate_test.exs
  - test/lightning_web/channels/workflow_channel_test.exs
flows:
  - flow-oauth-credential-authorize           # an OAuth credential saved from tab A reaches `credential_saved` through that flow
  - flow-credential-scheduled-deletion        # removal elsewhere; does not reach this flow (see 6.1)
---

## 1. Purpose

Several people build the same workflow at once. When one of them adds a credential from a step, the
others need it in their own "Configure connection" list so they can attach it without reloading and
losing their place. When the list goes stale, a colleague either cannot find a credential that exists
or picks one that has gone.

## 2. What it does

1. An editor creates or edits a credential (including a keychain credential) from a step's "Configure connection" in the workflow editor.
2. Every editor open on that same workflow, including viewers' and the sender's own, gets the project's full, fresh credential list and replaces theirs.
3. Separately, any editor whose connection drops and comes back refetches the list, which is how it picks up changes made anywhere else.

**Straightforwardness: 3 of 5.** Easy to explain, but the update only travels in one narrow case, so most credential changes don't reach open editors until they reconnect or reload.

### Most surprising behaviours

- **(2)** Deleting or unsharing a credential elsewhere tells no open editor. The credential stays pickable and attached on screen, and the next save from that editor will likely fail with a "doesn't exist" error. (6.1)
- **(3)** Creating or sharing a credential on the credentials pages reaches no open editor at all; colleagues won't see it in "Configure connection" until their connection drops or they reload. (S03, 6.1)
- **(3)** Only editors on the same workflow are told. Someone editing a different workflow in the same project keeps a stale list. (6.2)
- **(3)** Every save writes the whole credential list to the server's logs. (6.2)
- **(4)** Editors looking at an older version, a release or a run never get the update, only on reconnect. (6.2)

## 3. Who can do what

Sending side: `project_users.ex:44` (`:create_project_credential`, checked at
`collaborate.ex:316-323`), `users.ex:40-44` (edit only by the credential's owner,
`collaborate.ex:156-162`), keychain creation per workflow-editor-inspectors section 3. Receiving
side checks no role: every joined channel on the topic is pushed the list (`workflow_channel.ex:950-954`).

| Action | Viewer | Editor | Admin | Owner | Superuser (no row) | Support (no row) |
|--------|--------|--------|-------|-------|--------------------|------------------|
| Trigger the broadcast by saving a new credential from a step | no | yes | yes | yes | no | yes, when support access is on |
| Trigger it by editing a credential from a step | owner of the credential only | same | same | same | no | same |
| Receive the updated list in an open editor | yes | yes | yes | yes | n/a | yes |

**Preconditions beyond role**
- The receiving tab must be on the latest view of the same workflow; pinned versions, releases and run views join a suffixed topic (`workflow_channel.ex:2152-2160`; `pinnedView.ts:60`).
- Credentials saved on credentials-index or project-settings-credentials do not broadcast at all (`helpers.ex:160-169`).

## 4. What it touches

**Reads**: `project_credentials`, `credentials`, `users`, `oauth_clients`, `keychain_credentials` (`projects.ex:1121-1125`; `credentials.ex:1912-1919`; `workflow_json.ex:12-51`)

**Writes**
- Hop 1, tab A: `credentials`, `project_credentials` or `keychain_credentials` via CredentialFormComponent; owned by shared-adaptor-credential-config
- Hop 3, tab B: none; the list is client state only

**Immediate side effects** (in the same request)
- Hop 1: `credential_saved` and `close_credential_modal` pushed to tab A's React (`collaborate.ex:417-420`)
- Hop 2: `Phoenix.PubSub.broadcast` of `%{event: "credentials_updated", payload: %{project_credentials, keychain_credentials}}` on `workflow:collaborate:<workflow_id>`, rebuilt from the database, not the saved row (`collaborate.ex:519-532`)
- Hop 3: each joined WorkflowChannel, including tab A's own, `push`es `credentials_updated` (`workflow_channel.ex:950-954`); the store validates, sorts by name and replaces both lists (`createCredentialStore.ts:200-243`, `:295-303`)

**Deferred side effects** (later, elsewhere)
- On every channel connect the store sends `request_credentials` and replaces the list from the reply (`StoreProvider.tsx:233-246`; `createCredentialStore.ts:306-308`, `:323-345`; `workflow_channel.ex:119-132`)

**External, non-transactional effects**
- none

**Depends on config**
- none

**Product limits**
- none

## 5. Scenarios

Verified against `default`. Tab A's save, attach and reopen is shared-adaptor-credential-config
S11 (and S14 for keychains); this flow owns what the other tab sees.

```gherkin
Feature: A credential created elsewhere appears in an open editor
  In order to use a credential a colleague just added
  As a member with a workflow open in the editor
  I want my credential list to update without reloading

  @S01 @pending
  Scenario Outline: A credential saved in one editor appears in a colleague's open editor
    # Value: colleagues can attach a credential the moment it exists, without reloading and losing their place.
    Given "amara@example.org" and I both have workflow "Intake" open in the editor
    And "amara@example.org" has "Configure connection" open for step "Fetch"
    When I <action> from "Configure connection" on step "Load"
    Then "amara@example.org" eventually sees <name> in her credential list under <group>
    # collaborate.ex:393-430, :519-532; workflow_channel.ex:950-954; createCredentialStore.ts:200-243, :295-303
    # collaborate_test.exs:267-446 (broadcast sent); workflow_channel_test.exs:4561-4677 (broadcast forwarded); no client test of the handler
    Examples:
      | action                                          | name           | group                   |
      | save a new DHIS2 credential "DHIS2 test"        | "DHIS2 test"   | the matching credentials |
      | save a new keychain credential "Per country"    | "Per country"  | "Keychain Credentials"  |
      | rename my credential "DHIS2 prod" to "DHIS2 live" | "DHIS2 live" | the matching credentials |

  @S02 @pending
  Scenario: A viewer's open editor receives the list too
    # Value: a read-only colleague reviewing the workflow sees the credential a step now uses by its name, not as unknown.
    Given "amara@example.org" is a viewer with "Intake" open
    When I save a new DHIS2 credential "DHIS2 test" from step "Fetch" and it is attached
    Then "amara@example.org" eventually sees "Fetch" show "DHIS2 test"
    # workflow_channel.ex:950-954 (no role check); createCredentialStore.ts:155-176 (lookup by id); no test

  @S03 @pending
  Scenario: An editor that reconnects picks up credentials added on the credentials page
    # Value: a stale credential list is corrected when the connection comes back, without a page reload.
    Given I have "Intake" open in the editor
    And in another tab I create project credential "Salesforce prod" on the credentials page
    Then my editor's credential list does not yet include "Salesforce prod"
    When my editor's connection drops and reconnects
    Then my credential list includes "Salesforce prod"
    # helpers.ex:160-169 (no broadcast); StoreProvider.tsx:233-246; createCredentialStore.ts:306-308, :323-345; workflow_channel.ex:119-132
    # no test of the reconnect refetch
```

## 6. Unclear value

### 6.1 Possible bugs

| What | Where | What a user sees | Disposition |
|------|-------|------------------|-------------|
| Creating or sharing a credential on credentials-index or project-settings-credentials broadcasts nothing, so open editors do not offer it. The lead's scope names these as entries; the code only reaches editors through S03's reconnect | `helpers.ex:160-169`; `credential_form_component.ex:1269-1276`; only publisher `collaborate.ex:527-531` | a credential just created in another tab is missing from "Configure connection" until reload or reconnect | fix |
| Removing a credential elsewhere (scheduled deletion, keychain delete, unsharing) broadcasts nothing; deletion nulls `jobs.project_credential_id` in the database but the open Y.Doc keeps the old id, so the next save from that editor likely fails the foreign key. Read from code, not run | `credentials.ex:1036-1052`, `:2018-2030`; `job.ex:122-126`; `scoping.ex:116-117` | the removed credential is still pickable and attached; saving likely shows "credential doesn't exist or isn't available in this project" | fix |

### 6.2 Quirks and implementation details

| What | Where | Disposition |
|------|-------|-------------|
| Only this workflow's topic is told; editors on other workflows of the same project stay stale (already a `decide` row in shared-adaptor-credential-config 6.2, carried here as the flow's owner) | `collaborate.ex:527-531` | decide |
| `broadcast`, not `broadcast_from`: tab A's own channel receives the list, and JobForm also calls `request_credentials` after save, so tab A loads the list twice | `collaborate.ex:527`; `JobForm.tsx:155-160`; `FullScreenIDE.tsx:706` | preserve |
| Pinned version, release and run views join a suffixed topic and never receive the broadcast; they refetch only on reconnect | `workflow_channel.ex:2152-2160`; `pinnedView.ts:60` | preserve |
| The payload is the whole project list, not a delta, rebuilt from the database after the save | `collaborate.ex:519-525`; `workflow_json.ex:12-51` | preserve |
| A malformed broadcast payload replaces the list with an error state rather than keeping the last good list | `createCredentialStore.ts:228-242` | decide |
| The full credential payload is written to the info log on every save | `collaborate.ex:413-415` | decide |

### 6.3 Unreachable or dead code

| What | Where | Why unreachable |
|------|-------|-----------------|
| `channel.on("credentials_list")` handler | `createCredentialStore.ts:290-293`, `:302` | no server code pushes `credentials_list`; the only pushes are `credentials_updated` and the `request_credentials` reply |

### 6.4 Performance and operational limits

| What | Where | User-visible? | Disposition |
|------|-------|---------------|-------------|
| Every connect, including each reconnect, issues a full `request_credentials` query of project and keychain credentials | `StoreProvider.tsx:233-246`; `workflow_channel.ex:119-132` | no | preserve |

### 6.5 Things seen but not understood

- Whether unsharing a credential from a project on credentials-index also nulls jobs that use it, as scheduled deletion does, was not followed (`credentials.ex:263-294`). (decide)
- How the step's credential badge and "Configure connection" render a selected credential that a broadcast has just removed from the list was not traced past the lookup (`createCredentialStore.ts:155-176`; `ConfigureAdaptorModal.tsx:261-264`). (preserve)

## 7. Not migrating

| Item | Reason | Decided by | Date |
|------|--------|------------|------|

## 8. Open questions

- Should credentials created, shared or removed on credentials-index and project-settings-credentials reach open editors (6.1)? If yes, the publisher should move into the Credentials context rather than the editor LiveView.
- Should the broadcast go to every workflow in the project, not just the one the credential was saved from (6.2)?
- Should an open editor be told when a credential it has attached is removed, before it tries to save?

## Proposed flows

none. Removal elsewhere would extend this flow if 6.1 is fixed, rather than become a new one.

## Proposed shared

none. References shared-editor-session and shared-adaptor-credential-config.

## Summary

- Scenarios: 3 (S01 to S03, S01 an outline of three), all `@pending`.
- Section 6: 6.1 has 2, 6.2 has 6, 6.3 has 1, 6.4 has 1, 6.5 has 2.
- Flows: none proposed; references flow-oauth-credential-authorize and flow-credential-scheduled-deletion.
- Shared: inherits shared-editor-session and shared-adaptor-credential-config; none proposed.
- Unsure: the lead's scope says credentials-index and project-settings-credentials changes reach open editors, but no code path broadcasts from them (6.1); the FK failure on save after removal and the reconnect refetch (S03) are read from code with no test.
