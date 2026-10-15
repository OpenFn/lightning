---
id: project-settings-history-exports
type: view
title: Project settings › History exports
status: not-started
owner:

trigger:
  old_route: /projects/:project_id/settings#history-exports
  new_route: /projects/:project_id/settings/history-exports
  old_route_disposition: redirect
  reachable_when:
    - the project scope gate admits the viewer (shared-project-scope; settings.ex:51)
    - the client-side tab hash is "history-exports" (settings.html.heex:63-66, :1055; TabbedContainer, see shared-project-settings-tab-chrome)
    - no permission flag gates the panel or its controls; the section header passes `can_perform_action={true}` (settings.html.heex:1056-1061)

inherits:
  - shared-authenticated-session
  - shared-project-scope                  # on_mount :project_scope (settings.ex:51); login, MFA gate, membership remount
  - shared-usage-limits-banner            # on_mount :check_limits (settings.ex:52)
  - shared-project-header
  - shared-project-settings-tab-chrome    # tab navigation (S01-S05), no role notice (section 3 row "Notice on History exports"), sandbox Local banner (S08 row "History Exports"), no banner outside a sandbox (S10)
  - shared-local-datetime
  - shared-flash-messages   # added by lead (final pass)

url_params:
  - name: "#history-exports (URL fragment)"
    set_by: the tab strip only (settings.html.heex:63); no email, flash or other page links to this fragment (the completion email links to the download route instead, user_notifier.ex:324)
    effect: opens this tab client-side; the server never sees it (settings.ex:233)

config_variants:
  default: {}                             # STORAGE_BACKEND=local; read under this one
  storage-gcs: { STORAGE_BACKEND: gcs }   # only changes what the download controller returns; owned by flow-history-export
  sandbox: { project.parent_id: <parent project id> }   # data state, named so the inherited sandbox banner row applies

inventory:
  routes:
    - live /projects/:project_id/settings  ProjectLive.Settings :index   # catalogued by project-settings-setup
    - get /project_files/:id/download  ProjectFileController :download   # linked from here (settings.html.heex:1075); owned by flow-history-export (router.ex:227)
  events: []                              # the panel has no phx-click or handle_event of its own
  js_hooks:
    - LocalTimeConverter                  # Common.datetime in the date column (data_tables.ex:310; common.ex:422-470; assets/js/hooks/index.ts)
    - Copy                                # click-to-copy timestamp inside Common.datetime (common.ex:463-468)
  policies:
    - Lightning.Policies.Exports.authorize(:download)   # enforced by the controller, not the panel (project_file_controller.ex:19-26, exports.ex:21-24); owned by flow-history-export
  workers: []                             # ExportWorker writes the rows this panel lists; owned by flow-history-export
  api_endpoints: []
  emails: []                              # email:history-export-complete is owned by flow-history-export
  config: []
  not_reachable_here:
    - section_header permissions message "history exports." (settings.html.heex:1059-1060); `can_perform_action={true}` means it never renders (see 6.3)

related:
  - project-settings-setup                # owns the host route and mount (settings.ex:100-225)
  - history-work-orders                   # where exports are started
flows:
  - flow-history-export                   # this view is its exit; download handoff only here
---

## 1. Purpose

Project members come here to find the work order history exports that anyone on the project has
requested, see whether each one is ready, and download the finished archive. It is the one place in
the app that lists a project's exports; without it, a member who lost the completion email, or who
did not request the export, would have no way to retrieve the file.

## 2. What it does

- Any member sees every export requested on this project, with when, by whom, filename and status
- Any member downloads a completed export
- Unfinished and failed exports cannot be downloaded
- Members see a clear empty state when the project has no exports
- Only this project's exports are listed, including in a sandbox

**Straightforwardness: 4 of 5.** A read-only list with a download link; the surprises are about how stale or misleading a row can look, not about what the page does.

### Most surprising behaviours

- **(3)** The list never updates on its own. An export that has finished keeps showing "In progress" with a disabled button until you reload the page. (6.1)
- **(3)** A failed export says "Export is not yet ready for download" and shows its filename as "Pending", which suggests it will be ready later when it never will. There's no way to retry or remove it from here. (6.1, 8)
- **(4)** Exports don't stay forever: they drop off this list when the project's data retention cleanup removes them. (4)

## 3. Who can do what

Sources: no policy is consulted when rendering the panel (`settings.html.heex:1055-1100`); the list is
loaded for every viewer at mount (`settings.ex:115`, `:208`). Download is checked by the controller
via `Exports.authorize(:download)`, which is `:access_project` (`exports.ex:21-24`,
`project_users.ex:134`, `:136`); the full download matrix is in flow-history-export section 3.

| Action | Viewer | Editor | Admin | Owner | Superuser (no row) | Support (no row, access on) |
|--------|--------|--------|-------|-------|--------------------|-----------------------------|
| See the panel and every export row | yes | yes | yes | yes | no (cannot reach the page) | yes |
| See an enabled "Download" link on a completed row | yes | yes | yes | yes | n/a | yes |
| Download succeeds (controller) | yes | yes | yes | yes | no, 403 | yes |
| Start an export | not here (history-work-orders) | | | | | |
| Delete an export | nobody; no control exists | | | | | |

**Preconditions beyond role**
- A member who hasn't met the project's MFA requirement never reaches the page (shared-project-scope); the controller also returns 403 for them (flow-history-export S08).
- The project must not be scheduled for deletion for the download to succeed (flow-history-export S08).
- "Download" is a live link only when the row's status is `completed` (`settings.html.heex:1071-1080`).

## 4. What it touches

**Reads**: `project_files` for this project, newest `inserted_at` first, with `created_by` preloaded from `users` (`settings.ex:115`, `projects.ex:2133-2142`)

**Writes**: none

**Immediate side effects**
- none; the "Download" link is a plain `href` to `/project_files/<id>/download` opened in a new tab (`settings.html.heex:1073-1080`)

**Deferred side effects**
- none from this view. Rows appear, change status and disappear through ExportWorker and the data retention job (flow-history-export section 4)

**External, non-transactional effects**
- none from this view; the storage read or signed-URL redirect happens in the controller (flow-history-export hop 5)

**Depends on config**
- none for the panel itself; `STORAGE_BACKEND` changes only the controller response (`storage-gcs` variant, owned by the flow)

**Product limits**
- none; the list is unpaginated (see 6.4)

## 5. Scenarios

```gherkin
Feature: Project history exports panel
  In order to retrieve a history export I or a teammate requested
  As a member of a project
  I want to see the project's exports, their status, and download the ones that are ready

  @S01 @pending
  Scenario: Members see every export requested on the project
    # Value: the team can find an export someone else asked for, and see who asked, without chasing them.
    Given I am a viewer on project "Malawi HIV"
    And "Amara Banda" requested a history export that has completed
    And "Tomas Silva" requested a history export that is in progress
    When I open the project's settings on the "History Exports" tab
    Then I see a row requested by "Amara Banda" with status "Completed" and the zip's filename
    And I see a row requested by "Tomas Silva" with status "In progress" and the filename "Pending"
    And each row shows when the export was requested
    # settings.ex:115, :208; projects.ex:2133-2142; settings.html.heex:1067-1070
    # data_tables.ex:291-332 (columns, Path.basename(file.path), "Pending", first and last name), :334-339 (status label)

  @S02 @pending
  Scenario Outline: Any member can start the download of a completed export
    # Value: whoever needs the record can take it, not only the person who requested it.
    Given I am a <role> on project "Malawi HIV"
    And a history export on the project has completed
    When I open the project's settings on the "History Exports" tab
    Then that row's "Download" link points to "/project_files/<project_file_id>/download" and opens in a new tab
    When I click "Download"
    Then the flow "flow-history-export" continues at controller:project-file-download for that file
    # settings.html.heex:1071-1080 (no role check on the link); router.ex:227
    # end-to-end delivery and access checks: flow-history-export S01, S07, S08
    Examples:
      | role   |
      | viewer |
      | editor |
      | admin  |
      | owner  |

  @S03 @pending
  Scenario: A project with no exports says so
    # Value: a member looking for an export knows there isn't one, rather than suspecting the page failed to load.
    Given I am an editor on project "Malawi HIV"
    And nobody has requested a history export on the project
    When I open the project's settings on the "History Exports" tab
    Then I see "No history exports found for this project."
    And I see no exports table
    # data_tables.ex:294-295; settings.html.heex:1092-1098

  @S04 @pending
  Scenario: Only this project's exports are listed
    # Value: export archives of one project's health data are never offered to members of another project.
    Given I am an owner of projects "Malawi HIV" and "Kenya TB"
    And a history export on "Kenya TB" has completed
    When I open the settings of "Malawi HIV" on the "History Exports" tab
    Then I see "No history exports found for this project."
    # projects.ex:2136-2137 (where project_id), settings.ex:115

  @S05 @pending @variant:sandbox
  Scenario: A sandbox lists its own exports, not its parent's
    # Value: someone in a sandbox does not mistake the live project's exports for the sandbox's, or the reverse.
    Given I am an owner of sandbox "dev" of project "Malawi HIV"
    And a history export on "Malawi HIV" has completed
    When I open the settings of sandbox "dev" on the "History Exports" tab
    Then I see "No history exports found for this project."
    And I see the sandbox banner (shared-project-settings-tab-chrome S08, row "History Exports")
    # projects.ex:2136-2137, settings.ex:109, :115, settings.html.heex:1062-1066
    # sandbox_settings_test.exs:116-126 asserts the banner id only
```

Inherited, not restated: tab selection and deep link (shared-project-settings-tab-chrome S01 to S04),
all tabs visible to viewers (S05), no role notice on this tab (S07 and section 3 row "Notice on History
exports"), sandbox banner copy (S08), no banner outside a sandbox (S10). Disabled "Download" with tooltip
for unfinished exports and "Failed" rows: flow-history-export S05, S06.

## 6. Unclear value

### 6.1 Possible bugs

| What | Where | What a user sees | Disposition |
|------|-------|------------------|-------------|
| The list is loaded once at mount and nothing refreshes it; no `handle_info` touches `project_files` | `settings.ex:115`, `:208`, `:683-724` | an export stays "Enqueued" or "In progress" with a disabled button after it has finished, until the page is reloaded (also flow-history-export 6.2) | decide |
| A failed export shows the disabled button's tooltip "Export is not yet ready for download" | `settings.html.heex:1081-1089`; failed rows never get a `path`, `export_worker.ex:85-92` | copy implies the file will become ready when it never will | fix |
| A failed export's filename reads "Pending" | `data_tables.ex:312-316`; `export_worker.ex:85-92` | "Pending" next to status "Failed" | fix |
| The table reuses the DOM id `project_users_table` (table `project_users_table-table`) also used on the project form | `settings.html.heex:1068`; `form_component.html.heex:58` | nothing visible; collides with tests and scripts that target the collaborators table id | fix |

### 6.2 Quirks and implementation details

| What | Where | Disposition |
|------|-------|-------------|
| Rows are ordered newest `inserted_at` first, by default arg of `list_project_files` | `projects.ex:2134-2138` | decide |
| Column headers are title case ("Export Date", "Export Requested By") and the tab label is "History Exports", while the section heading is sentence case | `data_tables.ex:300-303`; `settings.html.heex:65`, `:1057` | decide |
| Status label is the enum humanized ("In progress", "Enqueued") | `data_tables.ex:334-339` | decide |
| Request time uses `Common.datetime` with the default `:relative` format, a hover tooltip with the UTC ISO time, and click-to-copy | `data_tables.ex:310`; `common.ex:402-407`, `:422-470` | preserve |
| The download control is a `<.link>` when completed and a disabled `<.button>` otherwise, both with the same id | `settings.html.heex:1073-1090` | preserve |
| Download opens in a new tab (`target="_blank"`) | `settings.html.heex:1076` | preserve |
| Requester name is built as `first_name <> " " <> last_name`; both are required by every user changeset seen | `data_tables.ex:319`; `user.ex:103-109` | preserve |
| The empty state is the non-interactive variant (no button) | `settings.html.heex:1093-1097`; `table.ex:306-330` | preserve |
| The panel has no LiveView test of its own; only the sandbox banner id is asserted | `sandbox_settings_test.exs:116-126` | preserve |

### 6.3 Unreachable or dead code

| What | Where | Why unreachable |
|------|-------|-----------------|
| Section header permissions message "history exports." | `settings.html.heex:1059-1060` | `can_perform_action={true}` is hard-coded, so the message never renders (also listed in shared-project-settings-tab-chrome 6.2) |

### 6.4 Performance and operational limits

| What | Where | User-visible? | Disposition |
|------|-------|---------------|-------------|
| Every export row the project has ever kept is loaded at mount, unpaginated, on every settings page load whichever tab is open | `settings.ex:115`; `projects.ex:2133-2142` | no, until a project has many exports; bounded in practice by the retention job (flow-history-export S10) | preserve |

### 6.5 Things seen but not understood

- The disabled "Download" button relies on `simple_button_with_tooltip` to show its tooltip (`new_inputs.ex:139-149`); not verified that the tooltip appears on hover over a `disabled` button in all browsers.

## 7. Not migrating

| Item | Reason | Decided by | Date |
|------|--------|------------|------|

## 8. Open questions

- Should the panel update live as an export moves from enqueued to completed (6.1)? Same question as flow-history-export section 8.
- Should failed exports have their own copy, or a way to retry or remove them, given no control on this panel deletes or retries an export?
- Should the completion email land on this tab rather than the raw download route, so the panel is the single exit (flow-history-export 6.2)?

## Proposed flows

none. The download handoff and everything upstream belong to flow-history-export (surfaces: history-work-orders, oban:ExportWorker, email:history-export-complete, project-settings-history-exports, controller:project-file-download).

## Proposed shared

- **shared-local-datetime**: the `Common.datetime` component (relative time, UTC ISO tooltip, click-to-copy via the LocalTimeConverter and Copy hooks; `common.ex:402-470`, `assets/js/hooks/index.ts`), rendered by 14 files under `lib/lightning_web`, including this panel's date column (`data_tables.ex:310`).

## Lead resolution (batch 3)

- `shared-local-datetime` created as proposed.
