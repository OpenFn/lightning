---
id: admin-collections
type: view
title: Admin settings › Collections
owner:

trigger:
  old_route: /settings/collections
  new_route:
  old_route_disposition: unchanged
  reachable_when:
    - the session is admitted by shared-authenticated-session; the route sits in the `:settings` live_session, which mounts `InitAssigns` (`lib/lightning_web/router.ex:316`, `:333`)
    - the viewer is a superuser (`collection_live/index.ex:4`; gate owned by shared-admin-space S02, S03)
    - entered from the "Collections" item in the admin side menu (shared-admin-space S01; `settings.html.heex:70-71`, `index.ex:19`)

inherits:
  - shared-admin-space                # gate (S02 row /settings/collections, S03), settings layout and side menu with "Collections" current (S01; index.ex:19, :23), demotion handoff (S06)
  - shared-authenticated-session      # login redirect, revoked sessions, TOTP and lockout gates, sidebar (S01 to S07, S11); S08 to S10 not on the settings layout
  - shared-flash-messages             # bottom toasts on the settings layout that stay until clicked (S07); flash carried across push_navigate (S05)
  - shared-project-header             # no-project parts only: LayoutComponents.header at index.ex:74-76 (confirmation banner S13, S14), global picker (S04, S06, S08, S10 to S12), account menu (S18)

url_params: []                        # sort state is held in assigns only (index.ex:21-22, :41-45)

config_variants:
  default: { Lightning.Extensions.collection_hook: Lightning.Extensions.CollectionHook }   # every hook returns :ok (extensions/collection_hook.ex:8-17); read under this one
  collection-limited: { Lightning.Extensions.collection_hook: <adapter whose handle_create returns {:error, :exceeds_limit, %Message{text: _}}> }   # a plan with collection limits; same variant as project-settings-collections; not exercised by this view's tests
  require-email-verification: { lightning.require_email_verification: true }   # inherited only; shared-project-header S13, S14

inventory:
  routes:
    - live /settings/collections  CollectionLive.Index :index   # router.ex:333
  events:
    - CollectionLive.Index#sort                         # index.ex:27-46
    - CollectionLive.Index#delete_collection            # index.ex:48-64
    - CollectionLive.CollectionCreationModal#close_modal  # collection_creation_modal.ex:39-41
    - CollectionLive.CollectionCreationModal#validate   # collection_creation_modal.ex:43-54
    - CollectionLive.CollectionCreationModal#save       # collection_creation_modal.ex:56-102
  js_hooks:
    - ModalHook (assets/js/hooks/index.ts:522; live/components/modal.ex:37)   # every create, edit and delete modal; proposed shared-modal
  policies:
    - Lightning.Policies.Users :access_admin_space via LightningWeb.Hooks :ensure_admin (index.ex:4; hooks.ex:40-53; policies/users.ex:30-32); owned by shared-admin-space
  workers: []
  api_endpoints: []
  emails: []
  config:
    - :lightning, Lightning.Extensions, :collection_hook via Lightning.Services.CollectionHook (services/collection_hook.ex:10-17); handle_create on create, handle_delete on delete
  not_reachable_here:
    - Collections.get_collection/2, get_collection_by_id/1, get_collection_for_project/2, resolve_collection/3, list_project_collections/2 (collections.ex:51-153); project tab and API only
    - Collections item reads and writes (get, get_all, stream_all, put, put_all, delete, delete_all) (collections.ex:273 onwards); API and project-tab preview only
    - Lightning.Policies.Collections (every rule)
    - Table.empty_state non-interactive branch (table.ex:325-331); this view passes no `interactive` attr (index.ex:87-94), so the default `true` applies (table.ex:301)
    - Collection `delete` virtual field (collection.ex:22); provisioner only (provisioner.ex:826-833)
    - Hooks :ensure_admin nil-user clause (hooks.ex:31-38); owned by shared-admin-space 6.3

related:
  - project-settings-collections            # the same collections from inside one project; scenarios referenced below, differences in 6.2
  - flow-download-collection                # a collection created here is downloadable only from the project tab; this page has no download link, so it is not a surface of that flow
  - flow-sandbox-merge                      # a collection created here in a sandbox is created empty in the parent on merge (sandboxes.ex:1463-1475)
  - flow-export-project-yaml                # exported YAML lists collection names, so a create, rename or delete here changes the next export (v2.ex:652-656)
  - flow-github-sync-actions                # the provisioner writes a project's collections by id (provisioner.ex:647, :826-833); a rename here changes what the next sync sees
  - admin-audit                             # lists audit events; create and rename write one (S14)
flows:
  - flow-admin-collection-reaches-project
---

## 1. Purpose

Superusers use this page to see every collection on the instance, which project
owns it and how much storage it uses, and to create, rename and delete
collections in any project without being a member of it. Without it, an instance
admin chasing storage use would have to open each project in turn, and a project
whose admins can't or won't fix a collection (wrong name, data that must be
removed) would have nobody able to do it outside the API.

## 2. What it does

- **See every collection**
  - Superusers see every collection on the instance with its project and used
    storage, and sort by name or storage
  - An instance with no collections shows an empty state that opens the create
    form
- **Create a collection**
  - Superusers create a collection in any project, with its URL-safe name shown
    before saving; a name that isn't URL safe can't be saved
  - Names are unique within a project, but the same name can be used in
    different projects
  - On a plan that limits collections, creating one past the limit is refused
    with the plan's message
- **Rename a collection**
  - Superusers rename a collection, keeping its records
  - A collection's project is fixed once it is created: the project field is
    shown but disabled when editing
  - A rename to a name the project already uses is refused
- **Delete a collection**
  - Superusers delete a collection and all its records, after confirming
  - Superusers close a form or confirmation without changing anything
- **Effect on projects**
  - A change made here is what the owning project's members see on their
    collections tab

**Straightforwardness: 3 of 5.** The page itself is a simple list with forms;
the surprises come from what a rename does to the jobs using the collection.

### Most surprising behaviours

- **(2)** Renaming or deleting a collection gives no warning that jobs referring
  to it by name will stop finding it. (8, 4)
- **(3)** The form says names must be unique across the whole instance, but they
  only need to be unique within a project. The project picker also starts on the
  first project alphabetically, so it's easy to create a collection in the wrong
  place. (6.1, 6.2)
- **(4)** Project members with the collections tab already open keep seeing the
  old list until they reload. (4)

## 3. Who can do what

Sources: `collection_live/index.ex:4` (`:ensure_admin`); `hooks.ex:40-53`;
`policies/users.ex:30-32` (`:access_admin_space` is role `:superuser` only). A
role change disconnects the socket (shared-admin-space S06).

| Action                             | Signed out | Regular user | Support user | Superuser                     |
| ---------------------------------- | ---------- | ------------ | ------------ | ----------------------------- |
| See the page and every collection  | no         | no           | no           | yes                           |
| Sort the list                      | no         | no           | no           | yes                           |
| Create a collection in any project | no         | no           | no           | yes                           |
| Rename a collection                | no         | no           | no           | yes                           |
| Change a collection's project      | no         | no           | no           | no (field disabled)           |
| Delete a collection                | no         | no           | no           | yes                           |
| Preview or download a collection   | n/a        | n/a          | n/a          | n/a (no control on this page) |

**Preconditions beyond role**

- No project membership is needed: the picker lists every project
  (`collection_creation_modal.ex:26`, `:30-32`; `projects.ex:256-258`) and
  delete takes any collection id (`index.ex:48-49`; `collections.ex:255-258`).
- Signed-out, revoked, TOTP-pending and locked-out sessions are refused first by
  shared-authenticated-session.

## 4. What it touches

**Reads**: `collections` with `project` preloaded, all rows, ordered by the
chosen column (`index.ex:20`, `:36-39`; `collections.ex:43-49`); `projects` for
the picker, once per modal (`collection_creation_modal.ex:26`, `:30-32`); the
session user's role for the gate (shared-admin-space)

**Writes**:

- `collections` insert with `project_id` and `name`
  (`collection_creation_modal.ex:60`, `:66-67`; `collections.ex:173-205`;
  `collection.ex:34-40`), with an audit event "created" in the same transaction
  (`collections.ex:188-190`; `collections/audit.ex:1-9`)
- `collections` update of `name` only, with an audit event "updated" in the same
  transaction unless the name is unchanged
  (`collection_creation_modal.ex:67-72`; `collections.ex:222-249`;
  `collection.ex:45-50`); a rename of a collection deleted since the page loaded
  flashes the "changed or deleted" message (`collections.ex:240-241`;
  `collection_creation_modal.ex:88-92`)
- `collections` delete, cascading to `collections_items` (`index.ex:49`;
  `collections.ex:251-269`; `20241022021209_create_collections.exs:19-21`)

**Immediate side effects** (in the same request)

- Flash "Collection created successfully", "Collection updated successfully" or
  "Collection deleted", then `push_navigate` to `/settings/collections`, which
  remounts the page (`collection_creation_modal.ex:79-80`; `index.ex:53-54`)
- `CollectionHook.handle_create(attrs)` inside the create transaction
  (`collections.ex:181-186`);
  `CollectionHook.handle_delete(project_id, byte_size_sum)` inside the delete
  transaction (`collections.ex:259-266`). All no-ops under `default`.
- `Logger.error` on a failed delete (`index.ex:57`), which reaches Sentry
  (`.claude/rules/logging.md`)
- Audit events for create and rename, written by the same transaction as the
  write (`collections.ex:188-190`, `:230-233`)
- No PubSub broadcast, no email, no Oban job

**Deferred side effects** (later, elsewhere)

- The owning project's collections tab lists the new or renamed collection, and
  drops a deleted one, on its next load; there is no broadcast, so an open tab
  is stale until it remounts (project-settings-collections S01; proposed
  `flow-admin-collection-reaches-project`)
- Jobs and Collections API callers that address the collection by name see the
  change on their next request (`collections_controller.ex:99-110`)
- The next project YAML export and GitHub sync see the changed collection set
  (flow-export-project-yaml, flow-github-sync-actions)
- A collection created here in a sandbox is created empty in the parent on merge
  (flow-sandbox-merge)

**External, non-transactional effects**

- Under `collection-limited`, the hook adapter may record usage outside the
  database (`collections.ex:173-205`, `:259-266`). Nothing external under
  `default`.

**Depends on config**

- `Lightning.Extensions.collection_hook`: may refuse a create with a message
  (`collections.ex:181-186`, `:196-197`; `collection_creation_modal.ex:82-86`)
  and is told the freed size on delete (`collections.ex:259-263`)

**Product limits**

- Collection names use only lowercase letters, digits and single `-`, `_` or `.`
  separators (`collection.ex:54-56`)
- Names are unique within a project, not across the instance
  (`collection.ex:57-60`;
  `20260410000000_scope_collection_name_uniqueness_to_project.exs:4-8`)
- On a plan with collection limits, the number or size of collections may be
  capped (variant `collection-limited`, S07)

## 5. Scenarios

```gherkin
Feature: Admin collections
  In order to see and correct collections across the whole instance
  As a superuser
  I want to list, create, rename and delete any project's collections

  @S01
  Scenario: Superuser sees every collection on the instance with its project and storage
    # Value: an instance admin can see which collections exist in every project, and which use the most storage, without joining each project.
    Given I am a superuser who is not a member of "Malawi HIV" or "Kenya TB"
    And "Malawi HIV" has a collection "patients" using 2500000 bytes
    And "Kenya TB" has a collection "visits" using 100 bytes
    When I open "/settings/collections"
    Then I see "Collections (2)"
    And I see a row "patients" with project "Malawi HIV" and "2.5 MB"
    And I see a row "visits" with project "Kenya TB" and "100 B"
    # index.ex:20; collections.ex:43-49 (all rows, project preloaded); components.ex:52-61, :64-115; helpers.ex:76-95
    # collection_live_test.exs:30-48 asserts both rows exist (not the project names, sizes or count); storage format as project-settings-collections S01

  @S02
  Scenario: An instance with no collections offers to create one
    # Value: an admin on a fresh instance sees straight away where to create the first collection.
    Given I am a superuser
    And no collection exists on the instance
    When I open "/settings/collections"
    Then I see "No collection found."
    And I do not see the collections table
    When I click "Create a new one."
    Then I see the "Create Collection" form
    # index.ex:86-95, :108-113; components.ex:71-73; table.ex:304-324
    # collection_live_test.exs:22-28 (asserts the copy, not the click)

  @S03
  Scenario: Superuser creates a collection in a project they are not a member of
    # Value: a superuser can give a project the collection its jobs need without being added to the project.
    Given I am a superuser who is not a member of "Malawi HIV"
    When I click "Create collection"
    And I enter "New Collection" as the name
    Then I see "This collection will be named new-collection."
    When I choose "Malawi HIV" as the project
    And I click "Save"
    Then I see "Collection created successfully"
    And I see a row "new-collection" with project "Malawi HIV"
    And an audit event "created" is recorded for the collection, by me
    And the flow "flow-admin-collection-reaches-project" has started for "new-collection"
    # index.ex:96-106; collection_creation_modal.ex:43-54, :56-80, :139-162; helpers.ex:223-240; collections.ex:173-205
    # collection_live_test.exs:99-127 (the superuser is made a member at :103; the non-member case is read from code, 6.5)

  @S04
  Scenario: A name that isn't URL safe can't be saved
    # Value: every collection name works unchanged in job code and API URLs.
    Given I am a superuser
    When I click "Create collection"
    And I enter "Café data" as the name
    Then I see "Collection name must be URL safe" under the name
    And the "Save" button is disabled
    # same behaviour as project-settings-collections S04
    # collection.ex:54-56, :63-78; helpers.ex:223-228 (keeps "é"); collection_creation_modal.ex:47 (error copied to raw_name), :160

  @S05
  Scenario: Two collections in a project can't share a name
    # Value: a job addressing a collection by name always gets the one it means.
    Given I am a superuser
    And "Malawi HIV" has a collection "patients"
    When I create a collection named "patients" in "Malawi HIV"
    Then I see "A collection with this name already exists" under the name
    And "Malawi HIV" still has one collection named "patients"
    # same behaviour as project-settings-collections S05
    # collection.ex:57-60; collection_creation_modal.ex:94-100; migration 20260410000000_scope_collection_name_uniqueness_to_project.exs:6
    # collection_live_test.exs:179-200 renders the submit but never asserts (6.5)

  @S06
  Scenario: The same name can be used in another project
    # Value: teams in different projects don't have to coordinate collection names.
    Given I am a superuser
    And "Kenya TB" has a collection "patients"
    When I create a collection named "patients" in "Malawi HIV"
    Then I see "Collection created successfully"
    And I see two rows "patients", one for "Malawi HIV" and one for "Kenya TB"
    # same behaviour as project-settings-collections S06; migration 20260410000000_scope_collection_name_uniqueness_to_project.exs:4-8

  @S07 @variant:collection-limited
  Scenario: Creating a collection past the plan's limit is refused
    # Value: a superuser learns why a project can't take another collection instead of getting a silent failure.
    Given "Malawi HIV" is at its plan's collection limit, with the message "Some error message"
    And I am a superuser
    When I create a collection named "some-name" in "Malawi HIV"
    Then I see "Some error message"
    And no collection "some-name" exists
    # same behaviour as project-settings-collections S07, reached from here
    # collections.ex:181-186, :196-197; collection_creation_modal.ex:82-86; not tested on this page

  @S08
  Scenario: Superuser renames a collection and keeps its records
    # Value: an admin can fix a badly named collection without recreating it and losing its records.
    Given I am a superuser
    And "Malawi HIV" has a collection "old-collection" with 3 records
    When I click "Edit" on "old-collection"
    And I change the name to "Updated Collection"
    Then I see "This collection will be named updated-collection."
    When I click "Save"
    Then I see "Collection updated successfully"
    And I see a row "updated-collection" with project "Malawi HIV"
    And "updated-collection" still has its 3 records
    And an audit event "updated" is recorded for the collection, by me
    # components.ex:119-127, :138-144; collection_creation_modal.ex:14-19, :60, :67-72; collections.ex:222-249; collections/collection.ex:45-50
    # collection_live_test.exs:147-177 (asserts the flash, name and project name; records read from code)

  @S09
  Scenario: A collection stays in the project it was created in
    # Value: a collection's data and the jobs that name it can't be moved to another project by an edit, so a rename never changes whose data it is.
    Given I am a superuser
    And "Malawi HIV" has a collection "patients" with 3 records
    When I click "Edit" on "patients"
    Then the "Project" field shows "Malawi HIV" and is disabled
    When I change the name to "patients-2024" and click "Save"
    Then I see "Collection updated successfully"
    And I see a row "patients-2024" with project "Malawi HIV"
    And "patients-2024" still has its 3 records
    # collection_creation_modal.ex:155-162 (select disabled in edit mode, so no project is submitted); collection.ex:45-50 (rename_changeset casts only name)
    # not tested on this page (collection_live_test.exs:168-170 submits the same project)

  @S10
  Scenario: A rename to a name the project already uses is refused
    # Value: a rename can't leave a project with two collections a job can't tell apart.
    Given I am a superuser
    And "Malawi HIV" has collections "patients" and "patients-old"
    When I rename "patients-old" to "patients"
    Then I see "A collection with this name already exists" under the name
    And "Malawi HIV" still has both its collections, named as before
    # collection.ex:45-50, :57-60; collection_creation_modal.ex:94-100; migration 20260410000000_scope_collection_name_uniqueness_to_project.exs:6; read from code

  @S11
  Scenario: Superuser deletes a collection after confirming
    # Value: an admin can clear out data a project no longer needs, and can't do it with a single misclick.
    Given I am a superuser
    And "Malawi HIV" has a collection "patients" with 3 records
    When I click "Delete" on "patients"
    Then I see "Are you sure you want to delete the collection patients"
    When I click "Delete" in the confirmation
    Then I see "Collection deleted"
    And "patients" is not in the list
    And none of its records remain
    And the flow "flow-admin-collection-reaches-project" has started for "patients"
    # components.ex:4-50, :128-136, :145-148; index.ex:48-54; collections.ex:251-269; create_collections migration :19-21 (cascade)
    # collection_live_test.exs:80-97 (clicks the confirm button directly; asserts the flash and the row gone)

  @S12
  Scenario Outline: Cancelling a form or confirmation changes nothing
    # Value: an admin who opened the wrong dialog can back out safely.
    Given I am a superuser
    And "Malawi HIV" has a collection "patients"
    When I click "<open>"
    And I type "changed" into any name field shown
    And I click "Cancel"
    Then the dialog is closed
    And collection "patients" is unchanged
    And no collection "changed" exists
    # create and edit: collection_creation_modal.ex:39-41, :175-183 (push_navigate remounts); delete: components.ex:44 (client-side hide)
    # collection_live_test.exs:129-145 (create, Cancel)

    Examples:
      | open                 |
      | Create collection    |
      | Edit on "patients"   |
      | Delete on "patients" |

  @S13
  Scenario: Superuser sorts the list by name or used storage
    # Value: an admin chasing instance storage can put the biggest collections at the top.
    Given I am a superuser
    And collections "tiny" (100 B), "huge" (5 GB) and "medium" (2.5 MB) exist in any projects
    When I open "/settings/collections"
    Then the rows read "huge", "medium", "tiny"
    When I click the "Name" header
    Then the rows read "tiny", "medium", "huge"
    When I click the "Used storage" header
    Then the rows read "tiny", "medium", "huge"
    When I click the "Used storage" header again
    Then the rows read "huge", "medium", "tiny"
    # index.ex:21-22, :27-46; components.ex:85-100; table.ex:234-243; common.ex:649-668
    # collection_live_test.exs:50-63 (name), :65-78 (storage)

  @S14
  Scenario: Creating or renaming a collection is recorded in the audit trail
    # Value: an admin can later see who created or renamed a project's collection, and when.
    Given I am a superuser
    When I create a collection named "patients" in "Malawi HIV"
    And I rename it to "patients-2024"
    Then an audit event "created" and an audit event "updated" are recorded for the collection, each by me
    When I save the edit form again without changing the name
    Then no further audit event is recorded
    # collections.ex:173-205 (create and its audit in one transaction), :222-249 (the "updated" event is skipped when the name is unchanged); collections/audit.ex:1-9
    # not tested on this page; collections_test.exs covers the context

  @S15
  Scenario: Renaming a collection that was deleted meanwhile is refused with a reload message
    # Value: a superuser acting on a stale list learns the record changed, instead of seeing a crash or a silent no-op.
    Given I am a superuser with "/settings/collections" open, listing "patients"
    And another request deletes "patients"
    When I rename "patients" to "patients-2024" and click "Save"
    Then I see "Someone else changed or deleted this record while you were editing it. Reload and try again."
    And "patients-2024" does not exist
    # collections.ex:228, :240-241; collection_creation_modal.ex:88-92; live_helpers.ex:217-219
    # not tested; read from code
```

## 6. Unclear value

### 6.1 Possible bugs

| What                                                                                                                                                     | Where                                                                                                                           | What a user sees                                                                                                                                                   | Disposition |
| -------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ----------- |
| The name sublabel says names "must be unique across all projects within this instance", but uniqueness has been per project since the 20260410 migration | `collection_creation_modal.ex:144`; `collection.ex:57-60`; `20260410000000_scope_collection_name_uniqueness_to_project.exs:4-8` | copy that contradicts S06: the same name saves fine in a second project                                                                                            | fix         |
| No length validation on `name`; the column is `varchar(255)`                                                                                             | `collection.ex:34-61`; `20241022021209_create_collections.exs:6`                                                                | a name over 255 characters raises a database error and the page crashes and reconnects instead of showing a field error (same as project-settings-collections 6.1) | fix         |
| A limiter message that sets `function` instead of `text` matches `%Message{text: error_msg}` with `nil`                                                  | `collection_creation_modal.ex:82-86`; `extensions/message.ex:5-12`                                                              | under `collection-limited`, an empty or missing error toast after the page reloads                                                                                 | fix         |

### 6.2 Quirks and implementation details

| What                                                                                                                                                                                                             | Where                                                                                                | Disposition |
| ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------- | ----------- |
| The project picker lists every project, including sandboxes and projects scheduled for deletion, by name only; projects with the same name can't be told apart                                                   | `collection_creation_modal.ex:30-32`, `:155-162`; `projects.ex:256-258`                              | decide      |
| The create form has no blank project option, so the first project alphabetically is preselected                                                                                                                  | `collection_creation_modal.ex:155-162`                                                               | decide      |
| The name field's value is bound to the derived name, so once it loses focus the typed text ("New Collection") is replaced by the slug ("new-collection"); the project tab keeps what was typed                   | `collection_creation_modal.ex:142`; `collection_live_test.exs:114`, `:164`                           | decide      |
| No preview and no download on this page; both exist on the project tab (project-settings-collections S13 to S15, S19)                                                                                            | `components.ex:104-148`                                                                              | decide      |
| Edit and Delete are shown to every viewer, since only superusers reach the page; the project tab disables them for non-admins                                                                                    | `components.ex:119-136`                                                                              | preserve    |
| Every save, limit refusal and form close (X or Cancel) ends in `push_navigate`, remounting the page and resetting sort; Escape or a click outside only hides the modal and keeps typed text for next time        | `index.ex:54`, `:62`; `collection_creation_modal.ex:39-41`, `:80`, `:85`; `modal.ex:45-49`, `:63-71` | decide      |
| Switching sort column always starts ascending; ties have no secondary order; sort state is not in the URL; the Project column is not sortable                                                                    | `index.ex:29-34`; `collections.ex:43-49`; `components.ex:93`                                         | decide      |
| Flash copy differs from the project tab: "Collection created successfully" and "Collection updated successfully" here, "Collection created" and "Collection updated" there                                       | `collection_creation_modal.ex:79`; `collections_component.ex:203-205`, `:228-230`                    | decide      |
| A delete of a collection already gone shows "Couldn't delete collection!" with no reason                                                                                                                         | `index.ex:56-62`; `collections.ex:255-258`                                                           | preserve    |
| That not-found race is logged with `Logger.error`, which reaches Sentry for an expected condition                                                                                                                | `index.ex:57`; `.claude/rules/logging.md`                                                            | fix         |
| Modal titles are title case ("Create Collection", "Edit Collection") while the page uses sentence case                                                                                                           | `collection_creation_modal.ex:112-114`                                                               | decide      |
| Delete copy renders "the collection patients ?" with a space before the question mark and tells the user to "click on the delete button" (same as the project tab)                                               | `components.ex:27-30`                                                                                | decide      |
| Empty-state copy "No collection found." and "Create a new one." differs from the project tab's "No collections found."                                                                                           | `index.ex:89-90`                                                                                     | decide      |
| Name hint reads "This collection will be named x."; the project tab reads "Your collection will be named x."                                                                                                     | `collection_creation_modal.ex:149-151`; `pills.ex:98-105`                                            | decide      |
| Delete is a plain confirm (no typed name) that removes every record and cannot be undone                                                                                                                         | `components.ex:4-50`; `20241022021209_create_collections.exs:19-21`                                  | decide      |
| The project cell is plain text, not a link to the project                                                                                                                                                        | `components.ex:111-113`                                                                              | decide      |
| Markup oddities: the empty-state button id is spelled "buttton"; the delete modal's close button carries a `variant` attribute that a raw `<button>` ignores; the create button sets `role="button"` on a button | `index.ex:91`, `:98`; `components.ex:13-22`                                                          | decide      |

### 6.3 Unreachable or dead code

| What                                       | Where              | Why unreachable                                                                                   |
| ------------------------------------------ | ------------------ | ------------------------------------------------------------------------------------------------- |
| `Table.empty_state` non-interactive branch | `table.ex:325-331` | this view never passes `interactive`, which defaults to `true` (`table.ex:301`; `index.ex:87-94`) |

### 6.4 Performance and operational limits

| What                                                                                                                                                                                               | Where                                                                | User-visible?                           | Disposition |
| -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------- | --------------------------------------- | ----------- |
| The list holds every collection on the instance, unpaginated                                                                                                                                       | `collections.ex:43-49`; `index.ex:20`                                | yes, on instances with many collections | decide      |
| Every row mounts its own edit modal component, and each one runs `Projects.list_projects()`, so the page runs one projects query per collection plus one for the create modal, again on every sort | `components.ex:138-144`; `collection_creation_modal.ex:26`, `:30-32` | yes, slow loads on large instances      | fix         |
| `list_collections` runs on both the dead render and the connected mount                                                                                                                            | `index.ex:14-24`                                                     | no                                      | preserve    |
| Used storage is `byte_size_sum` in decimal units (1 KB = 1000 B) rounded to one decimal                                                                                                            | `components.ex:115`; `helpers.ex:76-95`                              | yes                                     | preserve    |

### 6.5 Things seen but not understood

- `collection_live_test.exs:197-199` ends with
  `render_submit() =~ "A collection with this name already exists"` with no
  `assert`, so the duplicate-name test passes whatever the page shows. S05 is
  read from code.
- No test renames a collection into another project's name or creates one as a
  non-member (`collection_live_test.exs:168-170` submits the same project;
  `:103` makes the superuser a member). S03's non-member case, S09, S10, S14 and
  S15 are read from code.
- `Collection` defines a public `validate/1` and an identical private
  `validate_changeset/1` (`collection.ex:42-61`); unclear whether they are meant
  to diverge.
- `components.ex:63` carries "TODO - replace with common table when moving to
  project scope!"; the project tab now has its own component, so it is not clear
  whether this page was meant to be retired in favour of it.
- `CollectionHook.handle_delete/2` is matched with `:ok =` inside the
  transaction (`collections.ex:259-263`); an adapter that returns anything else
  raises and crashes the page. Unknown under other adapters (same note as
  project-settings-collections 6.5).

## 7. Not migrating

| Item | Reason | Decided by | Date |
| ---- | ------ | ---------- | ---- |

## 8. Open questions

- Should this page offer preview and download like the project tab, or link to
  the project's tab instead (6.2)?
- Should the picker hide sandboxes and projects scheduled for deletion, or show
  enough to tell same-name projects apart (6.2)?
- Rename and delete give no warning that jobs referring to the collection by
  name will stop finding it; same question as project-settings-collections
  section 8.

## Proposed flows

- `flow-admin-collection-reaches-project`: a superuser creates, renames or
  deletes a collection on `/settings/collections`, and members of the owning
  project see the change on their collections tab the next time it loads; with
  no broadcast, a tab already open keeps the old list until it remounts
  (`collections.ex:173-269`, no PubSub; `collections_component.ex:43-46`).
  Surfaces: admin-collections, project-settings-collections. From there, the
  existing flow-download-collection starts on the project tab.

## Proposed shared

- `shared-modal`: `LightningWeb.Components.Modal` with `ModalHook`
  (`live/components/modal.ex:31-101`; `assets/js/hooks/index.ts:522`), used by
  this view's create, edit and delete dialogs and by the project tab and many
  others; owns Escape and click-away closing, which only hides the dialog
  client-side unless `on_close` is set. First candidates: the 6.2 row here on
  Escape keeping typed text, and project-settings-collections 6.1 row 4.
  Surfaces: admin-collections, project-settings-collections, and every other
  view rendering `.modal`.

## Lead resolution (batch 11)

- `flow-admin-collection-reaches-project` created. `shared-modal` declined: a UI
  primitive, kept in each view.
