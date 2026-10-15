---
id: flow-admin-collection-reaches-project
type: flow
title: A collection created or moved by a superuser reaches the project
status: not-started
owner:

trigger:
  entry: admin-collections
  exit: project-settings-collections
  surfaces:
    - admin-collections
    - capability:collections-api
    - project-settings-collections
  reachable_when:
    - the actor is a superuser on /settings/collections (admin-collections section 3; collection_live/index.ex:4)
    - for the exit, the observer is a member of the owning project (or a support user with access on) and opens its settings on the "Collections" tab (project-settings-collections section 3)
    - for the API hop, the caller is a run of a workflow in some project, or a personal access token holder, addressing the collection by name (router.ex:162-172; api_auth.ex:12-38)

inherits:
  - shared-admin-space              # entry gate and settings layout; this flow does not repeat them
  - shared-project-scope            # exit gate (login, MFA, non-member Not Found, membership remount)
  - shared-flash-messages           # success and "Collection not found" toasts at both ends

url_params:
  - name: project_id (query, API hop)
    set_by: the job or API caller, optionally
    effect: scopes name lookup to one project; without it the name is looked up across every project (collections_controller.ex:131-141; collections.ex:66-72)

config_variants:
  default: { Lightning.Extensions.collection_hook: Lightning.Extensions.CollectionHook }   # every hook returns :ok; read under this one
  collection-limited: { Lightning.Extensions.collection_hook: <adapter that refuses or meters> }   # hosted plans; affects create and delete only (collections.ex:115-120, :169-176), never rename or move (6.1)

inventory:
  routes:
    - live /settings/collections  CollectionLive.Index :index                      # entry, owned by admin-collections (router.ex:285)
    - "/collections/:name and /collections/:name/:key  CollectionsController (stream, get, put, put_all, delete, delete_all)"   # API hop (router.ex:162-172); owned by capability:collections-api
    - live /projects/:project_id/settings  ProjectLive.Settings :index              # exit, owned by project-settings-collections
  events:
    - CollectionLive.CollectionCreationModal#save            # create, rename, move (collection_creation_modal.ex:56-93); owned by admin-collections
    - CollectionLive.Index#delete_collection                 # delete (index.ex:48-64); owned by admin-collections
    - ProjectLive.CollectionsComponent#toggle_action         # stale-tab lookup in S06 (collections_component.ex:89-119, :237-251); owned by project-settings-collections
  js_hooks: []
  policies:
    - Lightning.Policies.Collections authorize/3 for %Run{} (policies/collections.ex:81-84) and %User{} (:53-79), at the API hop
  workers: []
  api_endpoints:
    - capability:collections-api
  emails: []
  config:
    - :lightning, Lightning.Extensions, :collection_hook (services/collection_hook.ex:10-17)
  not_reachable_here:
    - CollectionsController.download (collections_controller.ex:110-129); owned by flow-download-collection
    - Collections item writes beyond what S01 to S04 call (put_all, delete, delete_all); owned by capability:collections-api

related:
  - flow-download-collection                   # starts on the exit view once the collection is there
  - capability:collection-api-name-resolution  # deferred; a same-name create or rename here triggers its 409 (6.2)
  - flow-sandbox-merge                         # a collection created or moved into a sandbox reaches the parent only by name, empty (sandboxes.ex:289, :309-312, :344)
  - flow-export-project-yaml
  - flow-github-sync-actions
flows: []
---

## 1. Purpose

When a superuser fixes a project's collections from the admin page (adds one its jobs need,
renames it, puts it in the right project, or clears it out), the project's members and its running
jobs are the ones who live with the result. If the change didn't reach them, a job would keep
failing on a collection that "exists", or keep reading data that now belongs to another project.

## 2. What it does

1. A superuser creates, renames, moves to another project, or deletes a collection on the admin collections page, without needing to be on the project.
2. The collection's records go wherever it goes: a rename or move keeps them, and a delete removes them.
3. Members see the change on the project's collections tab the next time it loads; a member acting from a tab that was already open is told the collection is "not found".
4. The project's jobs see the change on their next call:
   - A new or renamed collection is found by its new name
   - The old name, or a deleted collection, gives "Not Found"
   - After a move, only jobs in the new project can use it; the old project's jobs are refused

**Straightforwardness: 3 of 5.** The direct effects are what you'd expect, but collection names are shared across the whole instance and moving is looser than it looks, so one change can break or expose another project.

### Most surprising behaviours

- **(2)** A project admin can also move a collection, with all its records, into any project, including one they aren't on. The data leaves their project and the other project's jobs can read it. Moving may not even be an intended feature. (6.1)
- **(2)** Collection names are looked up across the whole instance. Creating, renaming or moving a collection to a name another project already uses makes every job in both projects that uses that name start failing. (6.2)
- **(3)** Renaming, moving or deleting gives no warning that jobs using the collection will break, so the first sign is failed runs in a project the superuser may never look at. (6.1)
- **(3)** A move isn't checked against the new project's plan limits, and the old project keeps the usage. (6.1)
- **(3)** These changes to someone else's project skip that project's two-factor requirement and leave no audit record. (6.2)

## 3. Who can do what

Sources: entry gate `collection_live/index.ex:4` (`:ensure_admin`, superuser only; no handler
re-checks, admin-collections section 3); API hop `collections_controller.ex:131-159` and
`policies/collections.ex:53-84`; exit `policies/collections.ex:53-55` and `scope.ex:138-152`.

| Action | Superuser (no row) | Project member | Support (access on) | Run in owning project | Run in another project |
|--------|--------------------|----------------|---------------------|-----------------------|------------------------|
| Create, rename, move or delete on /settings/collections | yes | no | no | n/a | n/a |
| See the result on the project's collections tab | no (cannot open the project) | yes | yes | n/a | n/a |
| Read the collection by name through the API | only as a member | yes, any role | yes | yes | no, 401 |
| Write items by name through the API | only as a member | editor and up | no | yes | no, 401 |

**Preconditions beyond role**
- The superuser needs no membership in, or MFA for, the project they change (`index.ex:4`, no `:project_scope`; admin-collections 6.2). The project's members do need MFA to see the result (shared-project-scope S05).
- A run is allowed only when its workflow's project is the collection's current project, read on every call (`policies/collections.ex:82-84`; `runs.ex:563-567`). A move therefore changes which runs are allowed with no other step.
- A bare name is looked up across all projects; a name held by two projects returns 409 before authorization (`collections.ex:66-72`; `collections_controller_test.exs:1727-1752`).

## 4. What it touches

**Hop 1, admin-collections**
- Reads: `collections` with projects, `projects` for the picker (admin-collections section 4)
- Writes: `collections` insert (`collections.ex:113-128`); update of `name` and `project_id` (`collection_creation_modal.ex:58`, `:66-69`; `collections.ex:153-157`; `collection.ex:31-33`); delete cascading to `collections_items` (`collections.ex:163-179`; `20241022021209_create_collections.exs:20`)
- Items keep their `collection_id`, so a rename or move carries every record with it (`20241022021209_create_collections.exs:20`; no item write in `collections.ex:153-157`)
- Flash then `push_navigate` to `/settings/collections` (`collection_creation_modal.ex:73-77`; `index.ex:50-54`)

**Hop 2, capability:collections-api**
- Reads: `collections` by name, optionally by project (`collections_controller.ex:131-141`; `collections.ex:66-87`); the run's project via `work_order -> workflow -> project` (`runs.ex:563-567`); `collections_items`
- Writes: `collections_items` on put (outside this flow's scope beyond S01)
- Responses that change with hop 1: 404 `{"error": "Not Found"}` for a name no project holds (`fallback_controller.ex:10-15`; `error_view.ex:73-84`); 401 `{"error": "Unauthorized"}` for a collection now in another project (`fallback_controller.ex:24-29`); 409 when two projects hold the name (`fallback_controller.ex:31-39`)

**Hop 3, project-settings-collections**
- Reads: `collections` for the project, on every mount and component update (`collections_component.ex:29-51`; `collections.ex:45-56`)
- Writes: none in this flow

**Immediate side effects**
- `CollectionHook.handle_create` on create and `handle_delete` on delete, inside the transaction; nothing on rename or move (`collections.ex:115-120`, `:169-176`, `:153-157`). No-ops under `default`.
- No audit event, no PubSub broadcast, no email, no Oban job at any hop (`collections.ex:113-179`; grep of `lib/lightning/collections*` finds none)

**Deferred side effects**
- An open project tab shows the old list until it remounts (6.2)
- The next YAML export, GitHub sync and sandbox merge see the changed set (related flows)

**External, non-transactional effects**
- Under `collection-limited`, whatever the hook adapter records on create and delete; nothing on move (6.1)

**Depends on config**
- `Lightning.Extensions.collection_hook` (see `config_variants`)

**Product limits**
- none beyond those owned by admin-collections (name format, per-project uniqueness)

## 5. Scenarios

```gherkin
Feature: A collection changed by a superuser reaches the project
  In order to fix a project's collections without joining the project
  As a superuser
  I want my change to be what the project's members see and what its jobs use

  @S01 @pending
  Scenario: A collection a superuser creates is usable by the project's jobs and visible to members
    # Value: a project gets the collection its jobs write to the moment a superuser creates it, with no further step.
    Given I am a superuser who is not a member of "Malawi HIV"
    And workflow "Daily sync" in "Malawi HIV" has a run "R1"
    When I create a collection named "patients" in "Malawi HIV" on "/settings/collections"
    Then a member of "Malawi HIV" opening the project's "Collections" tab sees "patients"
    And run "R1" can put key "k1" into "patients" by name and read it back
    # collection_creation_modal.ex:56-77; collections.ex:113-128; collections_controller.ex:28-40, :62-70, :131-141; policies/collections.ex:81-84
    # collections_controller_test.exs:1610-1665 (run token reads and writes its own project's collection; scoped by ?project_id)
    # collections_component.ex:29-51

  @S02 @pending
  Scenario: After a rename, jobs find the collection only by its new name, with its records
    # Value: a rename keeps the project's data and makes it obvious, not silent, when a job still uses the old name.
    Given "Malawi HIV" has a collection "patients" with record "k1"
    And workflow "Daily sync" in "Malawi HIV" has a run "R1"
    When I rename "patients" to "patients-2024" on "/settings/collections"
    Then a member of "Malawi HIV" sees "patients-2024" and not "patients" on the "Collections" tab
    And run "R1" reading "patients-2024" by name gets record "k1"
    And run "R1" reading "patients" by name gets 404 "Not Found"
    # collection_creation_modal.ex:58, :66-69; collections.ex:153-157; collections.ex:66-72 (no row: :not_found); fallback_controller.ex:10-15
    # collections_controller_test.exs:1480-1491 (404 for unknown name, PAT); rename path read from code

  @S03 @pending
  Scenario: After a move, the data follows the collection and the old project's jobs lose access
    # Value: once a collection belongs to another project, the old project's jobs can no longer read or overwrite that project's data.
    Given "Malawi HIV" has a collection "patients" with record "k1"
    And "Kenya TB" has no collection "patients"
    And run "R1" belongs to a workflow in "Malawi HIV" and run "R2" to a workflow in "Kenya TB"
    When I move "patients" to "Kenya TB" on "/settings/collections"
    Then a member of "Malawi HIV" no longer sees "patients" on the "Collections" tab
    And a member of "Kenya TB" sees "patients" on the "Collections" tab, with its used storage unchanged
    And run "R2" reading "patients" by name gets record "k1"
    And run "R1" reading or writing "patients" by name gets 401 "Unauthorized"
    # admin-collections S09; collection.ex:31-33 (casts project_id); collections.ex:153-157; policies/collections.ex:82-84; runs.ex:563-567
    # collections_controller_test.exs:1667-1725 (run token refused on another project's collection); the move itself is untested (admin-collections 6.5)

  @S04 @pending
  Scenario: After a delete, the collection is gone for members and jobs
    # Value: data a superuser clears out is not still readable by a job or visible on the project.
    Given "Malawi HIV" has a collection "patients" with record "k1"
    And workflow "Daily sync" in "Malawi HIV" has a run "R1"
    When I delete "patients" on "/settings/collections" after confirming
    Then a member of "Malawi HIV" sees "No collections found." on the "Collections" tab
    And run "R1" reading "patients" by name gets 404 "Not Found"
    # index.ex:48-54; collections.ex:163-179; 20241022021209_create_collections.exs:20 (items cascade); data_tables.ex:356-357

  @S05 @pending
  Scenario: A member acting on an open tab after a superuser moved the collection away is told it is not found
    # Value: a project admin working from a stale list can't rename or delete a collection that now belongs to another project.
    Given I am an admin on "Malawi HIV" with the "Collections" tab open, listing "patients"
    And a superuser has since moved "patients" to "Kenya TB"
    When I click "Edit" on "patients"
    Then I see "Collection not found"
    And "patients" is no longer in the list
    And "patients" in "Kenya TB" is unchanged
    # collections_component.ex:89-107, :237-251 (lookup scoped to the tab's project, then push_navigate re-lists); collections.ex:82-87
    # same mechanism as project-settings-collections S16 and S17, reached by a superuser move; read from code
```

## 6. Unclear value

### 6.1 Possible bugs

| What | Where | What a user sees | Disposition |
|------|-------|------------------|-------------|
| Move is possible only because `Collection.changeset` casts `project_id` for updates as well as inserts; the admin edit form renders the project select in edit mode and sends it | `collection.ex:31-33`; `collection_creation_modal.ex:146-152`, `:66-69` | a superuser can move a collection, which may be an accident of the cast rather than a designed feature; S03 depends on it | decide |
| The same cast lets a project admin on the project tab move a collection into any project, including one they are not on, by adding `collection[project_id]` to the save | `collections_component.ex:191-193`, `:221-222`; `collections.ex:153-157`; `collection.ex:31-33` (project-settings-collections 6.1) | the collection and its records leave the project and appear in a project the admin has no rights in; S03 then gives that project's runs the data and cuts off the source's | fix |
| A move calls no `CollectionHook`: the target project is not checked against its plan and the source is not credited | `collections.ex:153-157` vs `:115-120`, `:169-176` | under `collection-limited`, a move can take the target project past its limit, and the source keeps the usage (admin-collections 6.1) | decide |
| Rename and move give no warning that runs using the old name or project will start failing with 404 or 401 | `collection_creation_modal.ex:96-178` | jobs break silently from the superuser's side; the first sign is failed runs in the project | decide |

### 6.2 Quirks and implementation details

| What | Where | Disposition |
|------|-------|-------------|
| Writes on the entry page skip the project's MFA requirement and leave no audit event, though they change projects the superuser is not a member of | `index.ex:4`; `collections.ex:113-179` (admin-collections 6.2) | decide |
| No broadcast: a project tab already open keeps listing a created, renamed, moved or deleted collection as it was until it remounts | `collections.ex:113-179`; `collections_component.ex:29-51` | decide |
| Creating, renaming or moving to a name another project already holds makes every bare-name API call for it, from runs in either project, return 409 until callers add `?project_id=` | `collections.ex:66-72`; `fallback_controller.ex:31-39`; `collections_controller_test.exs:1385-1427`, `:1727-1752` | decide |
| After a move, the old project's runs get 401 "Unauthorized" rather than 404, because the bare name still resolves to the moved collection before the project check | `collections_controller.ex:131-141`, `:150-159` | decide |
| The project picker lists sandboxes, so a superuser can create or move a collection straight into a sandbox; it reaches the parent only by name and empty on merge | `collection_creation_modal.ex:30-32`; `sandboxes.ex:289`, `:309-312` | decide |

### 6.3 Unreachable or dead code

| What | Where | Why unreachable |
|------|-------|-----------------|
| none | | |

### 6.4 Performance and operational limits

| What | Where | User-visible? | Disposition |
|------|-------|---------------|-------------|
| A run's project is looked up with a three-table join on every collections API call | `policies/collections.ex:82-84`; `runs.ex:563-567` | no | preserve |

### 6.5 Things seen but not understood

- No test moves a collection and then calls the API, or checks the project tab after an admin-page change; S01 to S05 are composed from per-surface tests and code.
- Whether jobs in practice send `?project_id=` depends on the adaptor running in the external worker, which this repository does not contain; the run channel holds the run's project id (`run_channel.ex:44-55`) but nothing here shows it reaching the collections calls. S01 to S04 hold either way unless a 409 applies (6.2).
- `collections_controller_test.exs:27-49` gets 401 for a run token on its own project's collection; the run's work order has no workflow in that project, which is the likely cause, but the test name says the token is invalid.

## 7. Not migrating

| Item | Reason | Decided by | Date |
|------|--------|------------|------|

## 8. Open questions

- Is moving a collection between projects an intended capability, or an accident of `Collection.changeset` casting `project_id` (6.1)? If intended, should it run the collection hook on both sides? (owner: product)
- Should a project admin be able to move a collection out of their project through the cast, given the target may be a project they are not on (6.1)? (owner: security)
- Should superuser create, rename, move and delete of a project's collections be audited, and require the superuser's MFA when the project requires it (6.2)? (owner: security)
- Should runs resolve a bare collection name within their own project instead of across the instance, so a create elsewhere can't break them with a 409 (6.2)? (owner: product)
- Should rename, move and delete warn which workflows use the collection (6.1)? (owner: product)

## Proposed flows

none

## Proposed shared

none
