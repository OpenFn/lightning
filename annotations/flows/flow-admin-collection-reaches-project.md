---
id: flow-admin-collection-reaches-project
type: flow
title: A collection created or renamed by a superuser reaches the project
owner:

trigger:
  entry: admin-collections
  exit: project-settings-collections
  surfaces:
    - admin-collections
    - capability:collections-api
    - project-settings-collections
  reachable_when:
    - the actor is a superuser on /settings/collections (admin-collections
      section 3; collection_live/index.ex:4)
    - for the exit, the observer is a member of the owning project (or a support
      user with access on) and opens its settings on the "Collections" tab
      (project-settings-collections section 3)
    - for the API hop, the caller is a run of a workflow in some project, or a
      personal access token holder, addressing the collection by name
      (router.ex:207-216; api_auth.ex:15-33)

inherits:
  - shared-admin-space # entry gate and settings layout; this flow does not repeat them
  - shared-project-scope # exit gate (login, MFA, non-member Not Found, membership remount)
  - shared-flash-messages # success and "Collection not found" toasts at both ends

url_params:
  - name: project_id (query, API hop)
    set_by: the job or API caller, optionally
    effect:
      scopes name lookup to one project (collections_controller.ex:99-110;
      collections.ex:111-133); one that isn't a UUID names no collection, so the
      lookup is 404 (naming_test.exs:225)

config_variants:
  default: {
      Lightning.Extensions.collection_hook: Lightning.Extensions.CollectionHook,
    } # every hook returns :ok; read under this one
  collection-limited: {
      Lightning.Extensions.collection_hook: <adapter that refuses or meters>,
    } # plan limits; affects create and delete only (collections.ex:181-186, :259-266), never rename

inventory:
  routes:
    - live /settings/collections  CollectionLive.Index :index # entry, owned by admin-collections (router.ex:333)
    - '/collections/:name and /collections/:name/:key  CollectionsController
      (stream, get, put, put_all, delete, delete_all)' # API hop (router.ex:206-216); owned by capability:collections-api
    - live /projects/:project_id/settings  ProjectLive.Settings :index # exit, owned by project-settings-collections
  events:
    - CollectionLive.CollectionCreationModal#save # create, rename (collection_creation_modal.ex:56-102); owned by admin-collections
    - CollectionLive.Index#delete_collection # delete (index.ex:48-64); owned by admin-collections
    - ProjectLive.CollectionsComponent#toggle_action # stale-tab lookup in S06 (collections_component.ex:89-119, :246-260); owned by project-settings-collections
  js_hooks: []
  policies:
    - Lightning.Policies.Collections authorize/3 on a %Scope{} for a person or
      the service account (policies/collections.ex:48-65), at the API hop; a run
      is never asked it, and resolve_collection/3 finds it only its own
      project's collections (collections_controller.ex:112-114;
      collections.ex:135-140)
  workers: []
  api_endpoints:
    - capability:collections-api
  emails: []
  config:
    - :lightning, Lightning.Extensions, :collection_hook
      (services/collection_hook.ex:10-17)
  not_reachable_here:
    - CollectionsController.download (collections_controller.ex:110-129); owned
      by flow-download-collection
    - Collections item writes beyond what S01 to S04 call (put_all, delete,
      delete_all); owned by capability:collections-api

related:
  - flow-download-collection # starts on the exit view once the collection is there
  - capability:collection-api-name-resolution # deferred
  - flow-sandbox-merge # a collection created in a sandbox reaches the parent only by name, empty (sandboxes.ex:289, :309-312, :344)
  - flow-export-project-yaml
  - flow-github-sync-actions
flows: []
---

## 1. Purpose

When a superuser fixes a project's collections from the admin page (adds one its
jobs need, renames it, puts it in the right project, or clears it out), the
project's members and its running jobs are the ones who live with the result. If
the change didn't reach them, a job would keep failing on a collection that
"exists", or keep reading data that now belongs to another project.

## 2. What it does

1. A superuser creates, renames or deletes a collection on the admin collections
   page, without needing to be on the project. A collection stays in the project
   it was created in.
2. The collection's records stay with it: a rename keeps them, and a delete
   removes them.
3. Members see the change on the project's collections tab the next time it
   loads; a member acting from a tab that was already open is told the
   collection is "not found".
4. The project's jobs see the change on their next call:
   - A new or renamed collection is found by its new name
   - The old name, or a deleted collection, gives 404 `not_found`
   - Only jobs in the collection's own project can use it; jobs in another
     project get 404 `not_found`

**Straightforwardness: 3 of 5.** The direct effects are what you'd expect, but a
rename or delete can break a project's jobs without warning.

### Most surprising behaviours

- **(3)** Renaming or deleting gives no warning that jobs using the collection
  will break, so the first sign is failed runs in a project the superuser may
  never look at. (6.1)

## 3. Who can do what

Sources: entry gate `collection_live/index.ex:4` (`:ensure_admin`, superuser
only; no handler re-checks, admin-collections section 3); API hop
`collections_controller.ex:99-119` and `policies/collections.ex:48-65`; exit
`policies/collections.ex:58` and `scope.ex:267-276`.

| Action                                            | Superuser (no row)           | Project member | Support (access on) | Run in owning project | Run in another project |
| ------------------------------------------------- | ---------------------------- | -------------- | ------------------- | --------------------- | ---------------------- |
| Create, rename or delete on /settings/collections | yes                          | no             | no                  | n/a                   | n/a                    |
| See the result on the project's collections tab   | no (cannot open the project) | yes            | yes                 | n/a                   | n/a                    |
| Read the collection by name through the API       | only as a member             | yes, any role  | yes                 | yes                   | no                     |
| Write items by name through the API               | only as a member             | editor and up  | no                  | yes                   | no                     |

**Preconditions beyond role**

- The superuser needs no membership in the project they change (`index.ex:4`, no
  `:project_scope`; admin-collections 6.2). The project's members do need MFA to
  see the result (shared-project-scope S05).
- A run is allowed only when its workflow's project is the collection's current
  project, read on every call (`collections.ex:135-140`;
  `collections_controller.ex:112-118`). Because a collection never changes
  project, the set of runs allowed on it never changes either.

## 4. What it touches

**Hop 1, admin-collections**

- Reads: `collections` with projects, `projects` for the picker
  (admin-collections section 4)
- Writes: `collections` insert with an audit event "created"
  (`collections.ex:173-205`); update of `name` only, with an audit event
  "updated" (`collection_creation_modal.ex:60`, `:67-72`;
  `collections.ex:222-249`; `collection.ex:45-50`); delete cascading to
  `collections_items` (`collections.ex:251-269`;
  `20241022021209_create_collections.exs:20`)
- Items keep their `collection_id`, so a rename carries every record with it
  (`20241022021209_create_collections.exs:20`; no item write in
  `collections.ex:222-249`)
- Flash then `push_navigate` to `/settings/collections`
  (`collection_creation_modal.ex:76-80`; `index.ex:50-54`)

**Hop 2, capability:collections-api**

- Reads: `collections` by name among those the caller can see, optionally
  narrowed to one project (`collections_controller.ex:99-110`;
  `collections.ex:111-153`); the run's project via
  `work_order -> workflow -> project` (`runs.ex:563-567`); `collections_items`
- Writes: `collections_items` on put (outside this flow's scope beyond S01)
- Responses that change with hop 1: 404 problem document with code `not_found`
  for a name no project the caller can see holds
  (`api/fallback_controller.ex:35-41`; `api/problem.ex:96-110`); the same 404
  for a collection in another project; 409 `ambiguous_name` when two of the
  caller's projects hold the name and no `project_id` is sent
  (`api/fallback_controller.ex:56-67`)

**Hop 3, project-settings-collections**

- Reads: `collections` for the project, on every mount and component update
  (`collections_component.ex:29-51`; `collections.ex:51-61`)
- Writes: none in this flow

**Immediate side effects**

- `CollectionHook.handle_create` on create and `handle_delete` on delete, inside
  the transaction; nothing on rename (`collections.ex:181-186`, `:259-266`,
  `:222-249`). No-ops under `default`.
- No PubSub broadcast, no email, no Oban job at any hop

**Deferred side effects**

- An open project tab shows the old list until it remounts (6.2)
- The next YAML export, GitHub sync and sandbox merge see the changed set
  (related flows)

**External, non-transactional effects**

- Under `collection-limited`, whatever the hook adapter records on create and
  delete; nothing on rename

**Depends on config**

- `Lightning.Extensions.collection_hook` (see `config_variants`)

**Product limits**

- none beyond those owned by admin-collections (name format, per-project
  uniqueness)

## 5. Scenarios

```gherkin
Feature: A collection changed by a superuser reaches the project
  In order to fix a project's collections without joining the project
  As a superuser
  I want my change to be what the project's members see and what its jobs use

  @S01
  Scenario: A collection a superuser creates is usable by the project's jobs and visible to members
    # Value: a project gets the collection its jobs write to the moment a superuser creates it, with no further step.
    Given I am a superuser who is not a member of "Malawi HIV"
    And workflow "Daily sync" in "Malawi HIV" has a run "R1"
    When I create a collection named "patients" in "Malawi HIV" on "/settings/collections"
    Then a member of "Malawi HIV" opening the project's "Collections" tab sees "patients"
    And run "R1" can put key "k1" into "patients" by name and read it back
    # collection_creation_modal.ex:56-80; collections.ex:173-205; collections_controller.ex:22-36, :47-54, :99-110; collections_controller.ex:112-119
    # naming_test.exs:235-260 (a run token of the project reads and writes its collection); naming_test.exs:209-223 (scoped by ?project_id)
    # collections_component.ex:29-51

  @S02
  Scenario: After a rename, jobs find the collection only by its new name, with its records
    # Value: a rename keeps the project's data and makes it obvious, not silent, when a job still uses the old name.
    Given "Malawi HIV" has a collection "patients" with record "k1"
    And workflow "Daily sync" in "Malawi HIV" has a run "R1"
    When I rename "patients" to "patients-2024" on "/settings/collections"
    Then a member of "Malawi HIV" sees "patients-2024" and not "patients" on the "Collections" tab
    And run "R1" reading "patients-2024" by name gets record "k1"
    And run "R1" reading "patients" by name gets 404 with code "not_found"
    # collection_creation_modal.ex:60, :67-72; collections.ex:222-249; collections.ex:111-153 (no row: :not_found); api/fallback_controller.ex:35-41
    # naming_test.exs:16-22 (404 for a name the project hasn't got, on every route); rename path read from code

  @S03
  Scenario: A collection stays in its project, so only that project's jobs can use it
    # Value: a rename by a superuser never changes whose data a collection is, so another project's jobs can't read or overwrite it.
    Given "Malawi HIV" has a collection "patients" with record "k1"
    And run "R1" belongs to a workflow in "Malawi HIV" and run "R2" to a workflow in "Kenya TB"
    When I rename "patients" to "patients-2024" on "/settings/collections"
    Then the "Project" field on the edit form is disabled and still reads "Malawi HIV"
    And a member of "Malawi HIV" sees "patients-2024" on the "Collections" tab
    And run "R1" reading "patients-2024" by name gets record "k1"
    And run "R2" reading or writing "patients-2024" by name gets 404 with code "not_found"
    # admin-collections S09; collection.ex:45-50 (rename_changeset casts only name); collection_creation_modal.ex:155-162; collections.ex:135-140; collections_controller.ex:112-118
    # naming_test.exs:35-64 (a run token counts only its own project's collection)

  @S04
  Scenario: After a delete, the collection is gone for members and jobs
    # Value: data a superuser clears out is not still readable by a job or visible on the project.
    Given "Malawi HIV" has a collection "patients" with record "k1"
    And workflow "Daily sync" in "Malawi HIV" has a run "R1"
    When I delete "patients" on "/settings/collections" after confirming
    Then a member of "Malawi HIV" sees "No collections found." on the "Collections" tab
    And run "R1" reading "patients" by name gets 404 with code "not_found"
    # index.ex:48-54; collections.ex:251-269; 20241022021209_create_collections.exs:20 (items cascade); data_tables.ex:356-357

  @S05
  Scenario: A member acting on an open tab after a superuser deleted the collection is told it is not found
    # Value: a project admin working from a stale list can't act on a collection that a superuser has removed.
    Given I am an admin on "Malawi HIV" with the "Collections" tab open, listing "patients"
    And a superuser has since deleted "patients"
    When I click "Edit" on "patients"
    Then I see "Collection not found"
    And "patients" is no longer in the list
    # collections_component.ex:89-107, :246-260 (lookup scoped to the tab's project, then push_navigate re-lists); collections.ex:91-98
    # same mechanism as project-settings-collections S16 and S17, reached by a superuser delete; read from code
```

## 6. Unclear value

### 6.1 Possible bugs

| What                                                                             | Where                                  | What a user sees                                                                            | Disposition |
| -------------------------------------------------------------------------------- | -------------------------------------- | ------------------------------------------------------------------------------------------- | ----------- |
| Rename gives no warning that runs using the old name will start failing with 404 | `collection_creation_modal.ex:105-188` | jobs break silently from the superuser's side; the first sign is failed runs in the project | decide      |

### 6.2 Quirks and implementation details

| What                                                                                                                                                      | Where                                                                | Disposition |
| --------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------- | ----------- |
| No broadcast: a project tab already open keeps listing a created, renamed or deleted collection as it was until it remounts                               | `collections.ex:173-269`; `collections_component.ex:29-51`           | decide      |
| The project picker lists sandboxes, so a superuser can create a collection straight into a sandbox; it reaches the parent only by name and empty on merge | `collection_creation_modal.ex:30-32`; `sandboxes.ex:289`, `:309-312` | decide      |

### 6.3 Unreachable or dead code

| What | Where | Why unreachable |
| ---- | ----- | --------------- |
| none |       |                 |

### 6.4 Performance and operational limits

| What                                                                               | Where                    | User-visible? | Disposition |
| ---------------------------------------------------------------------------------- | ------------------------ | ------------- | ----------- |
| A run's project is looked up with a three-table join on every collections API call | `collections.ex:135-140` | no            | preserve    |

### 6.5 Things seen but not understood

- No test renames a collection and then calls the API, or checks the project tab
  after an admin-page change; S01 to S05 are composed from per-surface tests and
  code.

## 7. Not migrating

| Item | Reason | Decided by | Date |
| ---- | ------ | ---------- | ---- |

## 8. Open questions

- Should rename and delete warn which workflows use the collection (6.1)?

## Proposed flows

none

## Proposed shared

none
