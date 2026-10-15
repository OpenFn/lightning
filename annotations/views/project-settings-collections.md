---
id: project-settings-collections
type: view
title: Project settings › Collections
status: not-started
owner:

trigger:
  old_route: /projects/:project_id/settings#collections
  new_route: /projects/:project_id/settings/collections
  old_route_disposition: redirect
  reachable_when:
    - the project scope gate admits the viewer (shared-project-scope; settings.ex:51)
    - the client-side tab hash is "collections" (settings.html.heex:39-42, :367; TabbedContainer, see shared-project-settings-tab-chrome)
    - create, edit and delete controls are enabled only when the viewer passes `:manage_collection` on the project at mount (settings.ex:180-186; collections_component.ex:282-287, :360, :371, :386)

inherits:
  - shared-authenticated-session
  - shared-project-scope                  # on_mount :project_scope (settings.ex:51); login, MFA gate, membership remount (S08 refreshes can_create_collection)
  - shared-usage-limits-banner            # on_mount :check_limits (settings.ex:52)
  - shared-project-header
  - shared-project-settings-tab-chrome    # tab navigation (S01 to S04), role notice (S06 row "editor | Collections"), sandbox editable banner (S08 row "Collections", collections_component.ex:290-294)
  - shared-dataclip-body-viewer
  - shared-flash-messages   # added by lead (final pass)

url_params:
  - name: "#collections (URL fragment)"
    set_by: >-
      the tab strip; every redirect this component issues (return_to, settings.html.heex:375;
      collections_component.ex:170, :176, :205, :210, :226, :249, :267)
    effect: opens this tab client-side; the server never sees it (shared-project-settings-tab-chrome)

config_variants:
  default: { Lightning.Extensions.collection_hook: Lightning.Extensions.CollectionHook }   # every hook returns :ok (extensions/collection_hook.ex:7-17; config/config.exs:46); read under this one
  collection-limited: { Lightning.Extensions.collection_hook: <adapter whose handle_create returns {:error, :exceeds_limit, %Message{text: _}}> }   # hosted plans; project_live_test.exs:7258-7303 stubs MockCollectionHook
  sandbox: { project.parent_id: <parent project id> }   # data state; only the shared banner differs (shared-project-settings-tab-chrome S08)

inventory:
  routes:
    - live /projects/:project_id/settings  ProjectLive.Settings :index   # catalogued by project-settings-setup
  events:
    - ProjectLive.CollectionsComponent#sort                 # collections_component.ex:55-74
    - ProjectLive.CollectionsComponent#toggle_action        # new :76-87, edit :89-107, delete :109-119
    - ProjectLive.CollectionsComponent#preview_collection   # :121-151
    - ProjectLive.CollectionsComponent#reset_action         # :153-155
    - ProjectLive.CollectionsComponent#delete_collection    # :157-179
    - ProjectLive.CollectionsComponent#validate             # :181-189
    - ProjectLive.CollectionsComponent#save                 # :191-235
  js_hooks:
    - ModalHook (assets/js/hooks/index.ts:522-530; modal.ex:37)   # shared by every LightningWeb.Components.Modal
    - CollectionPreviewViewer React island (viewers.ex:216-221; assets/js/react/components/CollectionPreviewViewer.tsx)
    - CodeViewer copy button (assets/js/react/components/CodeViewer.tsx:11-34)
  policies:
    - Lightning.Policies.Collections (:manage_collection on %Project{} collections.ex:73-75 and on %Collection{} :77-79; :access_collection :53-55)
    - Lightning.Policies.ProjectUsers (:access_project, via Collections :access_collection; project_users.ex:136)
    - Lightning.Projects.Scope.role_in?/3 (scope.ex:138-147)
  workers: []
  api_endpoints:
    - GET /download/collections/:project_id/:name  CollectionsController.download   # linked from each row (collections_component.ex:344-352); scenario owned by proposed flow-download-collection
  emails: []
  config:
    - :lightning, Lightning.Extensions, :collection_hook (config/config.exs:46), via Lightning.Services.CollectionHook (services/collection_hook.ex:10-29)
  not_reachable_here:
    - Collections.get_collection/1 cross-project lookup and its :conflict result (collections.ex:66-72); used only by the API (collections_controller.ex:131-141)
    - Collections item writes (put, put_all, delete, delete_all) and Policies.Collections :put_collection_item, :delete_collection_item, :delete_all_collection_items (collections.ex:208-345; policies/collections.ex:60-71); API only
    - Collection `delete` virtual field (collection.ex:22); not read by this view
    - Collection.validate/1 public entry (collection.ex:38-47); used by the provisioner (provisioner.ex:736), not this view

related:
  - project-settings-setup                  # owns the host route and mount
  - lib/lightning_web/live/collection_live/index.ex   # superuser-wide collections page at /settings/collections (router.ex:285); separate view
  - lib/lightning_web/controllers/collections_controller.ex   # the Collections API and the download endpoint
  - lib/lightning/projects/sandboxes.ex     # sandbox creation clones collection names empty (:1409-1414); merge creates missing names, never deletes (:1448-1470)
flows:
  - flow-download-collection
  - flow-admin-collection-reaches-project   # added by lead (link lint)
---

## 1. Purpose

Project members use this tab to see which collections (key-value stores that a project's jobs
read and write between runs) exist in the project and how much storage each uses, to look at a
sample record, and to download the contents. Project owners and admins also create, rename and
delete collections here. Without it, a job that needs a collection would fail until someone with
API or superuser access created it, nobody on the project could check what data jobs have stored,
and an admin couldn't clear out a collection that is using up the project's storage.

## 2. What it does

- **Browse collections** (every member)
  - See the project's collections with their used storage, sorted by name or used storage
  - A project with no collections shows an empty state that admins can create from
  - Download a collection's contents
- **Preview a collection** (every member)
  - See its first record, or a note that it's empty
  - Long records stay readable on screen, and copying takes the full record
- **Create collections** (admins and owners)
  - Create one, seeing its URL-safe name before saving; a name that isn't URL safe can't be saved
  - Names are unique within a project but can be reused in other projects
  - On a plan that limits collections, creating one past the limit is refused with the plan's message
- **Rename and delete collections** (admins and owners)
  - Rename a collection
  - Delete a collection and all its records, after confirming
  - Close any form or confirmation without changing anything
- **Keep changes in bounds**
  - Viewers, editors and support users see create, edit and delete disabled, and their requests are refused
  - Collections from other projects can't be previewed, edited or deleted from this tab
  - A collection removed since the page loaded is reported as not found

**Straightforwardness: 3 of 5.** The tab itself is a plain list with a form, but collection names are what jobs and the API use to find data, so naming choices here have effects well beyond the page.

### Most surprising behaviours

- **(2)** Giving a collection the same name as one in another project is allowed, but it then breaks API requests by that name in both projects until callers add the project id. Nothing on the page warns about this. (S06, 4)
- **(2)** In a sandbox, the banner says changes sync to the parent on merge, but renaming a collection there ends up adding a second, empty collection to the parent instead of renaming it. (8)
- **(2)** An admin who tampers with the rename request can move a collection, with all its records, into another project, even one they aren't on. (6.1)
- **(3)** Renaming or deleting a collection gives no warning that jobs using it by name will stop finding it, and delete wipes every record with a simple confirm and no undo. (8, 6.2)
- **(3)** Pressing Escape on the create, edit or delete dialog may leave its button seeming dead until another dialog is opened or the page is reloaded. (6.1)

## 3. Who can do what

Sources: `lib/lightning/policies/collections.ex:53-55` (`:access_collection` defers to
`:access_project`), `:73-79` (`:manage_collection` needs an owner or admin row);
`lib/lightning/policies/project_users.ex:136` (`:access_project` is any standing, including
support); `lib/lightning/projects/scope.ex:138-147` (`role_in?` reads only the membership row and
requires MFA to be satisfied). Flag computed once at mount (`settings.ex:180-186`) and used to
disable controls (`collections_component.ex:282-287`, `:360`, `:371`, `:386`). Every write
handler re-checks the policy at the time of the event (`collections_component.ex:77`, `:96`,
`:116`, `:164`, `:192`, `:253-269`).

| Action | Viewer | Editor | Admin | Owner | Superuser (no row) | Support (no row, access on) |
|--------|--------|--------|-------|-------|--------------------|-----------------------------|
| See the tab and the collection list | yes | yes | yes | yes | no (cannot open the project) | yes |
| Sort the list | yes | yes | yes | yes | no | yes |
| Preview a collection | yes | yes | yes | yes | no | yes |
| Download a collection (link) | yes | yes | yes | yes | no | yes |
| Create a collection | no | no | yes | yes | no | no |
| Rename a collection | no | no | yes | yes | no | no |
| Delete a collection | no | no | yes | yes | no | no |

**Preconditions beyond role**
- A member who hasn't met the project's MFA requirement never reaches this page (shared-project-scope S05), and `role_in?` returns false for them (`scope.ex:141-142`).
- A project scheduled for deletion fails every check (`scope.ex:149-152`); the page itself is closed by shared-project-scope S04 and S10.
- A support user with no membership row can preview and download but never manage (`policies/collections.ex:57-59`, `scope.ex:135-136`).
- Preview, edit and delete only find a collection by name inside the current project (`collections_component.ex:237-251`, `collections.ex:82-87`).
- A role change on an open page remounts it (shared-project-scope S08); between the change and the remount, write handlers still re-check (`collections_component.ex:253-269`).

## 4. What it touches

**Reads**: `collections` (list for the project, ordered by the chosen column, `collections.ex:47-56`; lookup by project and name, `:82-87`); `collections_items` (first item by id for the preview, `collections.ex:187-204`, `:430-441`); `projects` and `project_users` for every permission check (`scope.ex:112-117`, `:184-200`)

**Writes**:
- `collections` insert with `project_id` and `name` (`collections_component.ex:197-200`; `collections.ex:113-128`; `collection.ex:31-36`)
- `collections` update of `name` (and of any cast field sent, see 6.1) (`collections_component.ex:221-222`; `collections.ex:153-157`)
- `collections` delete, cascading to `collections_items` (`collections.ex:163-179`; `priv/repo/migrations/20241022021209_create_collections.exs:19-21`)

**Immediate side effects** (in the same request)
- Flash "Collection created", "Collection updated" or "Collection deleted", then a navigation back to `settings#collections` that remounts the page (`collections_component.ex:168-170`, `:203-205`, `:224-226`)
- `CollectionHook.handle_create(attrs)` before the insert, inside the transaction (`collections.ex:115-120`); `CollectionHook.handle_delete(project_id, byte_size_sum)` before the delete, inside the transaction (`collections.ex:169-176`). Both no-ops under `default`.
- No audit event for create, rename or delete (`collections.ex:113-179`; see 6.2)

**Deferred side effects** (later, elsewhere)
- Jobs and Collections API callers that address the collection by name see the new, renamed or deleted collection on their next request (`collections_controller.ex:131-141`). Not followed further; see section 8.
- Creating a name that already exists in another project makes un-scoped API lookups of that name return 409 for both projects (`collections.ex:66-72`; `fallback_controller.ex:31-39`). Proposed flow `flow-collection-api-name-resolution`.

**External, non-transactional effects**
- Under `collection-limited`, the hook adapter may record usage outside the database; a create that then fails validation rolls back the insert but not anything the adapter did (`collections.ex:113-127`). Nothing external under `default`.

**Depends on config**
- `Lightning.Extensions.collection_hook`: may refuse creation with a message (`collections.ex:116-118`, `:125`; variant `collection-limited`) and is told the freed size on delete (`collections.ex:170-174`)

**Product limits**
- Collection names use only lowercase letters, digits and single `-`, `_` or `.` separators (`collection.ex:40-42`)
- On hosted plans, the number or size of collections may be capped by the plan (variant `collection-limited`, S07)
- The preview shows one record, with strings cut at 140 characters (`collections_component.ex:129`; `CollectionPreviewViewer.tsx:3`)

## 5. Scenarios

```gherkin
Feature: Project collections
  In order to keep and inspect the data my project's jobs share between runs
  As a member of a project
  I want to see, preview and download its collections, and, as an admin, create, rename and delete them

  @S01 @pending
  Scenario: Every member sees the project's collections and their storage
    # Value: anyone on the project can tell which collections exist and which ones are using up storage.
    Given I am a viewer on project "Malawi HIV"
    And the project has collections "alpha" using 5000000000 bytes, "bravo" using 2500000 bytes and "charlie" using 100 bytes
    When I open the project's settings on the "Collections" tab
    Then I see the rows "alpha" with "5 GB", "bravo" with "2.5 MB" and "charlie" with "100 B", in that order
    # collections_component.ex:40-51, :324-331; data_tables.ex:353-399; helpers.ex:76-95
    # project_live_test.exs:7726-7751 asserts the sizes and the default order (as owner)

  @S02 @pending
  Scenario: A project with no collections offers to create one
    # Value: an admin setting up a new project sees straight away where to create the collection its jobs need.
    Given I am an admin on project "Malawi HIV"
    And the project has no collections
    When I open the project's settings on the "Collections" tab
    Then I see "No collections found."
    And I see an enabled "Create a new collection" button
    When I click "Create a new collection"
    Then I see the "Create Collection" form
    # data_tables.ex:356-357; collections_component.ex:377-388, :76-87; table.ex:304-324

  @S03 @pending
  Scenario: Admin creates a collection
    # Value: a project can get the collection its jobs write to without a superuser or an API call.
    Given I am an admin on project "Malawi HIV"
    When I click "Create collection"
    And I enter "Test collection 0" as the name
    Then I see "Your collection will be named test-collection-0."
    When I click "Save"
    Then I see "Collection created"
    And I am on the "Collections" tab of the project's settings
    And "test-collection-0" is in the list
    # collections_component.ex:76-87, :181-189, :191-205, :429-435; collection.ex:60-75; helpers.ex:223-228
    # project_live_test.exs:7164-7220 (owner and admin; lowercase input "test collection 0")

  @S04 @pending
  Scenario: A name that isn't URL safe can't be saved
    # Value: every collection name works unchanged in job code and API URLs.
    Given I am an admin on project "Malawi HIV"
    When I click "Create collection"
    And I enter "Café data" as the name
    Then I see "Collection name must be URL safe" under the name
    And the "Save" button is disabled
    # collection.ex:49-53, :60-75; helpers.ex:223-228 (keeps "é"); collections_component.ex:181-189 (error copied to raw_name, :185), :444

  @S05 @pending
  Scenario: Two collections in a project can't share a name
    # Value: a job addressing a collection by name always gets the one it means.
    Given I am an owner on project "Malawi HIV"
    And the project has a collection "patients"
    When I create a collection named "patients"
    Then I see "A collection with this name already exists"
    And the project still has one collection named "patients"
    # collection.ex:54-57; collections_component.ex:212-217; migration 20260410000000_scope_collection_name_uniqueness_to_project.exs:6
    # project_live_test.exs:7222-7256

  @S06 @pending
  Scenario: The same name can be used in another project
    # Value: teams in different projects don't have to coordinate collection names.
    Given I am an admin on project "Malawi HIV"
    And project "Kenya TB" has a collection "patients"
    When I create a collection named "patients"
    Then I see "Collection created"
    And "patients" is in the list
    And the flow "flow-collection-api-name-resolution" has started for "patients"
    # migration 20260410000000_scope_collection_name_uniqueness_to_project.exs:4-8; collection.ex:54-57

  @S07 @pending @variant:collection-limited
  Scenario: Creating a collection past the plan's limit is refused
    # Value: a project on a limited plan learns why it can't add a collection instead of getting a silent failure.
    Given project "Malawi HIV" is at its plan's collection limit, with the message "Some error message"
    And I am an owner on the project
    When I create a collection named "some-name"
    Then I see "Some error message"
    And no collection "some-name" exists
    # collections.ex:115-120, :125; collections_component.ex:207-210; project_live_test.exs:7258-7303

  @S08 @pending
  Scenario Outline: Members who can't manage collections see the controls disabled
    # Value: read-only members can't start a change they aren't allowed to make.
    Given I am a <role> on project "Malawi HIV"
    And the project has a collection "patients"
    When I open the project's settings on the "Collections" tab
    Then the "Create collection" button is disabled
    And the "Edit" and "Delete" buttons on "patients" are disabled
    And the "Preview collection" button and the "Download" link on "patients" are enabled
    # settings.ex:180-186; collections_component.ex:282-288, :334-374; role notice is shared-project-settings-tab-chrome S06
    # project_live_test.exs:7097-7134 (create), :7305-7346 (edit), :7409-7450 (delete) assert disabled for viewer and editor

    Examples:
      | role    |
      | viewer  |
      | editor  |

  @S09 @pending
  Scenario Outline: A non-admin's create, edit or delete request is refused
    # Value: a crafted or stale request can't change a project's collections behind the policy's back.
    Given I am an editor on project "Malawi HIV"
    And the project has a collection "patients"
    When the page receives "toggle_action" with action "<action>" for "patients"
    Then I see "You are not authorized to perform this action"
    And I am on the "Collections" tab of the project's settings
    And collection "patients" is unchanged
    # collections_component.ex:76-119, :253-269; project_live_test.exs:7116-7132, :7330-7345, :7434-7449 (viewer and editor)

    Examples:
      | action |
      | new    |
      | edit   |
      | delete |

  @S10 @pending
  Scenario: Admin renames a collection
    # Value: an admin can fix a badly named collection without recreating it and losing its records.
    Given I am an admin on project "Malawi HIV"
    And the project has a collection "patients" with 3 records
    When I click "Edit" on "patients"
    And I change the name to "patients-2024"
    Then I see "Your collection will be named patients-2024."
    When I click "Save"
    Then I see "Collection updated"
    And "patients-2024" is in the list with its 3 records
    And "patients" is not in the list
    # collections_component.ex:89-107, :221-235; collections.ex:153-157; project_live_test.exs:7348-7407 (name change only)

  @S11 @pending
  Scenario: Admin deletes a collection after confirming
    # Value: an admin can clear out data the project no longer needs, and can't do it with a single misclick.
    Given I am an owner on project "Malawi HIV"
    And the project has a collection "patients" with 3 records
    When I click "Delete" on "patients"
    Then I see "Are you sure you want to delete the collection patients"
    When I click "Delete" in the confirmation
    Then I see "Collection deleted"
    And "patients" is not in the list
    And none of its records remain
    # collections_component.ex:109-119, :157-170, :527-578; collections.ex:163-179; create_collections migration :19-21 (cascade)
    # project_live_test.exs:7452-7494 (asserts the collection row is gone; item cascade read from the migration)

  @S12 @pending
  Scenario Outline: Cancelling a form or confirmation changes nothing
    # Value: an admin who opened the wrong dialog can back out safely.
    Given I am an admin on project "Malawi HIV"
    And the project has a collection "patients"
    When I click "<open>"
    And I click "Cancel"
    Then the dialog is closed
    And collection "patients" is unchanged
    # collections_component.ex:153-155, :448-456, :568-575; project_live_test.exs:7148-7160 (create, Cancel)

    Examples:
      | open                    |
      | Create collection       |
      | Edit on "patients"      |
      | Delete on "patients"    |

  @S13 @pending
  Scenario Outline: Any member previews the first record of a collection
    # Value: anyone on the project can check what a job has stored without writing code or using the CLI.
    Given I am a <role> on project "Malawi HIV"
    And collection "patients" holds a record with key "my-key" and value "my-value"
    When I click "Preview collection" on "patients"
    Then I see "Collection Preview: patients"
    And I see "Showing first record"
    And I see "my-key" and "my-value"
    # collections_component.ex:121-151, :468-521; policies/collections.ex:53-55
    # project_live_test.exs:7513-7541, :7543-7571, :7622-7638 (viewer, editor, admin, owner)

    Examples:
      | role   |
      | viewer |
      | editor |
      | admin  |
      | owner  |

  @S14 @pending
  Scenario: Previewing an empty collection says it is empty
    # Value: a member can tell an empty collection from a broken preview.
    Given I am an owner on project "Malawi HIV"
    And collection "patients" has no records
    When I click "Preview collection" on "patients"
    Then I see "This collection is empty."
    # collections_component.ex:129-131, :508-517; project_live_test.exs:7573-7594

  @S15 @pending
  Scenario: The preview stays readable and copies the full record
    # Value: a large record can be scanned on screen, and what is copied is the real data, not the shortened view.
    Given I am an owner on project "Malawi HIV"
    And collection "patients" holds a record whose value is a JSON object with a 300-character string field
    When I click "Preview collection" on "patients"
    Then the value is shown as an expanded JSON object, with "key" first
    And the long string is cut to 140 characters followed by "…"
    When I click the copy button
    Then the clipboard holds the full record, including all 300 characters
    # CollectionPreviewViewer.tsx:3-21, :23-47, :49-61; CodeViewer.tsx:11-34; collections_component.ex:134-141

  @S16 @pending
  Scenario Outline: A collection in another project can't be reached from this tab
    # Value: knowing another project's collection name doesn't let a member read, rename or delete it.
    Given I am an owner on project "Malawi HIV"
    And project "Kenya TB", which I am not on, has a collection "secret"
    When the page receives "<event>" for "secret"
    Then I see "Collection not found"
    And collection "secret" is unchanged
    # collections_component.ex:237-251; collections.ex:82-87
    # project_live_test.exs:7640-7666 (preview), :7668-7695 (edit), :7697-7724 (delete)

    Examples:
      | event                       |
      | preview_collection          |
      | toggle_action with "edit"   |
      | toggle_action with "delete" |

  @S17 @pending
  Scenario: A collection removed since the page loaded is reported as not found
    # Value: an admin acting on a stale list gets a clear answer instead of an error page.
    Given I am an admin on project "Malawi HIV" with the "Collections" tab open
    And collection "patients" has since been deleted
    When I click "Edit" on "patients"
    Then I see "Collection not found"
    And "patients" is no longer in the list
    # collections_component.ex:94-95, :237-251 (push_navigate remounts and re-lists)

  @S18 @pending
  Scenario: Members sort the list by name or used storage
    # Value: an admin chasing a storage limit can put the biggest collections at the top.
    Given I am an owner on project "Malawi HIV"
    And the project has collections "alpha" (5 GB), "bravo" (2.5 MB) and "charlie" (100 B)
    When I click the "Name" header
    Then the rows read "charlie", "bravo", "alpha"
    When I click the "Used storage" header
    Then the rows read "charlie", "bravo", "alpha"
    When I click the "Used storage" header again
    Then the rows read "alpha", "bravo", "charlie"
    # collections_component.ex:55-74, :271-272; data_tables.ex:362-379; table.ex:234-243
    # project_live_test.exs:7726-7764

  @S19 @pending
  Scenario: Every member can start a download of a collection
    # Value: anyone on the project can take a full copy of a collection for analysis or backup.
    Given I am a viewer on project "Malawi HIV"
    And the project has a collection "patients"
    When I open the project's settings on the "Collections" tab
    Then the "Download" link on "patients" points to "/download/collections/<project_id>/patients"
    And following it starts the flow "flow-download-collection"
    # collections_component.ex:344-352; router.ex:197-199
```

## 6. Unclear value

### 6.1 Possible bugs

| What | Where | What a user sees | Disposition |
|------|-------|------------------|-------------|
| Rename passes the submitted form params straight to `Collection.changeset`, which casts `project_id`; an admin of this project who adds `collection[project_id]` to the save request moves the collection into any other project, including one they aren't on | `collections_component.ex:191-193`, `:221-222`; `collections.ex:153-157`; `collection.ex:31-33` | the collection vanishes from their project and appears in someone else's; not exercised by any test | fix |
| The saved name comes from the hidden `name` field rendered after the last `validate` round trip, not from `raw_name` on the server. Every other name form uses `Helpers.derive_name_param/1`, whose doc names this exact timing problem | `collections_component.ex:191-200`, `:221-222`, `:430`; `helpers.ex:230-240`; compare `collection_live/collection_creation_modal.ex:58` | typing and pressing Enter quickly can save the collection under the previous keystroke's name | fix |
| No length validation on `name`; the column is `varchar(255)` | `collection.ex:31-58`; `20241022021209_create_collections.exs:6` | a name over 255 characters raises a database error and the tab crashes and reconnects instead of showing a field error | fix |
| Create, edit and delete modals have no `on_close`, so Escape or a click outside hides them in the browser while the server keeps `action` set. Opening the same modal again assigns the same action and the hidden modal is not remounted | `collections_component.ex:296-315`; `modal.ex:34-36`, `:46-49`, `:62-70`; compare the preview modal's `on_close`, `collections_component.ex:474` | after pressing Escape on "Create collection", the button appears to do nothing until another dialog is opened or the page is reloaded (read from code, not run) | fix |
| A limiter message that uses `function` instead of `text` matches `%{text: error_msg}` with `nil` | `collections_component.ex:207-210`; `extensions/message.ex:5-12` | under `collection-limited`, an empty red flash with no explanation | fix |
| Events the UI never sends crash the component: `save` while no form is open (no `save_collection` clause for `nil`, `:delete`, `:preview`), `validate` with no collection assigned, and `sort` with any field other than `name` or `byte_size_sum` | `collections_component.ex:55-56`, `:181-184`, `:191-193`, `:197`, `:221` | a reconnect and reset of the settings page; only reachable with a crafted event | fix |

### 6.2 Quirks and implementation details

| What | Where | Disposition |
|------|-------|-------------|
| Every success, refusal and not-found ends in `push_navigate` back to `settings#collections`, remounting the whole settings page rather than patching the list | `collections_component.ex:170`, `:176`, `:205`, `:210`, `:226`, `:249`, `:267` | decide |
| Switching sort column always starts ascending; ties (equal storage) have no secondary order; sort state is not in the URL and survives parent re-renders only through `socket.assigns` | `collections_component.ex:40-41`, `:57-62`; `collections.ex:47-56` | decide |
| `url_safe_name` keeps non-ASCII letters, so the hint shows a name ("café-data") that the format check then rejects | `helpers.ex:223-228`; `collection.ex:40-42`; `collections_component.ex:431-435` | decide |
| Errors on `name` are copied onto the visible `raw_name` field | `collections_component.ex:185`, `:216`, `:232`; `helpers.ex:182-197` | preserve |
| Modal titles are title case ("Create Collection", "Edit Collection", "Collection Preview: x") while the header and buttons are sentence case | `collections_component.ex:301`, `:308`, `:479` | decide |
| Delete copy renders "the collection patients ?" with a space before the question mark, and tells the user to "click on the delete button" | `collections_component.ex:550-553` | decide |
| Edit and Delete are rendered disabled for non-admins rather than hidden; Preview and Download are always enabled | `collections_component.ex:334-374` | preserve |
| The section header wraps the "Create collection" button in `aria-hidden="true"`, hiding it from screen readers (shared `section_header`) | `layout_components.ex:595`; `collections_component.ex:278-289` | decide |
| The preview shows the record with the lowest item id (first inserted), not the most recently updated | `collections_component.ex:129`; `collections.ex:430-434` | preserve |
| The preview JSON uses `created` and `updated` for `inserted_at` and `updated_at` | `collections_component.ex:134-139` | preserve |
| Create, rename and delete write no audit event | `collections.ex:113-179` | decide |
| Delete removes every record in the collection with a plain confirm (no typed name), and cannot be undone | `collections_component.ex:527-578`; `20241022021209_create_collections.exs:19-21` | decide |
| `preview_json` is left set after the preview closes; harmless because the next preview overwrites it | `collections_component.ex:144-155` | preserve |
| A delete that races another delete (found by `get_collection`, gone by `delete_collection`) shows "Couldn't delete collection!" | `collections_component.ex:172-176`; `collections.ex:164-166` | preserve |

### 6.3 Unreachable or dead code

| What | Where | Why unreachable |
|------|-------|-----------------|
| `mount/1` assigns `current_user: nil` and `collections: []` | `collections_component.ex:16-27` | `update/2` always overwrites both from the parent before render (`:29-51`) |
| `update/2` has a single clause requiring all five assigns | `collections_component.ex:30-38` | the only caller passes all five (`settings.html.heex:368-376`); any other caller would crash |
| `{:error, changeset}` branch of `delete_collection` | `collections_component.ex:172-176`; `collections.ex:176` | `Repo.delete` on a just-loaded row has no changeset errors here; only `:not_found` reaches it (6.2) |

### 6.4 Performance and operational limits

| What | Where | User-visible? | Disposition |
|------|-------|---------------|-------------|
| The collection list is unpaginated | `collections.ex:47-56` | yes, on projects with many collections | decide |
| The list is re-queried on every `update/2`, i.e. whenever the parent re-renders the component with changed assigns | `collections_component.ex:43-46` | no | preserve |
| Preview fetches one record; strings cut at 140 characters; `value` JSON parsed to depth 5 | `collections_component.ex:129`; `CollectionPreviewViewer.tsx:3-4`, `:23-24` | yes | preserve |
| Used storage is `byte_size_sum`, shown in decimal units (1 KB = 1000 B) rounded to one decimal | `data_tables.ex:388`; `helpers.ex:76-95` | yes | preserve |
| Download streams 500 records per database page (`max_database_limit`) | `config/config.exs:229-231`; `collections_controller.ex:117` | no | preserve |

### 6.5 Things seen but not understood

- `CollectionHook.handle_delete/2` is matched with `:ok =` inside the transaction (`collections.ex:170-174`). The behaviour's spec says it returns `:ok` (`collection_hooking.ex:12-15`), so an adapter that returns anything else raises a `MatchError` and crashes the tab. Not reachable under `default`; unknown under hosted adapters.
- No test covers download from this tab, the sandbox variant beyond the banner (`sandbox_settings_test.exs:103-114`), or membership changes while the tab is open. S02, S04, S12 (edit and delete rows), S15, S17 and S19 are read from code.
- `project_live_test.exs:7726-7764` inserts names "Alpha", "Bravo", "Charlie" through the factory, bypassing the URL-safe format; S01 and S18 use lowercase names so they can be set up through the UI.

## 7. Not migrating

| Item | Reason | Decided by | Date |
|------|--------|------------|------|

## 8. Open questions

- Renaming or deleting a collection gives no warning that jobs referring to it by name will stop finding it. Should the rebuild show which workflows use a collection, or warn on rename and delete? (owner: product)
- Should create, rename and delete be audited (6.2)?
- In a sandbox, the banner says changes sync to the parent on merge, but merge only creates missing names and never renames or deletes (`sandboxes.ex:1448-1470`); a rename in a sandbox therefore adds a second, empty collection to the parent. This is the collections half of shared-project-settings-tab-chrome 6.1; (owner: product) to decide which side changes.
- Should the list paginate (6.4), and should sort state live in the URL once the tab has its own route?
- Is the 6.1 `project_id` cast on rename covered by any security review? It should be fixed before or during migration either way.

## Proposed flows

- `flow-download-collection`: a member follows the "Download" link on a collection row and the browser saves `<name>.json`, a JSON array of every record streamed from `CollectionsController.download`, with non-members getting 401, unknown names 404 and malformed project ids 400 (`collections_controller.ex:110-129`; `collections_controller_test.exs:1240-1360`). Surfaces: project-settings-collections, controller:collections-download (`GET /download/collections/:project_id/:name`).
- `flow-collection-api-name-resolution`: once two projects hold a collection with the same name, Collections API requests for that name without `?project_id=` return 409 "Multiple collections found with this name" for callers in both projects, until they add the project id (`collections.ex:66-72`; `collections_controller.ex:131-141`; `fallback_controller.ex:31-39`). Surfaces: project-settings-collections (S06), collection_live index (superuser create), api:collections (`/collections/:name...`).

## Proposed shared

none. `ModalHook` and `LightningWeb.Components.Modal` are used across the app; if the lead wants a `shared-modal` annotation, the 6.1 Escape row here is its first candidate scenario.

## Lead resolution (batch 3)

- `flow-download-collection` created as proposed.
- `flow-collection-api-name-resolution` deferred to the capabilities pass (collections API).
