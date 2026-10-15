---
id: flow-history-export
type: flow
title: Export work order history
status: not-started
owner:

trigger:
  entry: history-work-orders
  exit: project-settings-history-exports
  surfaces:
    - history-work-orders
    - oban:ExportWorker
    - email:history-export-complete
    - project-settings-history-exports
    - controller:project-file-download
  reachable_when:
    - the export button renders only for viewers who can run workflows and when at least one work order matches (index.html.heex:664-674)
    - the history exports panel renders for every member who passes the project scope gate (settings.html.heex:1055-1100)
    - the download route re-checks project access itself (project_file_controller.ex:19-26)

inherits: []                              # the entry and exit views inherit shared-project-scope; the worker and controller do not mount it and re-ask :access_project themselves (exports.ex:21-24, mail_recipients.ex:28-32)

url_params:
  - name: id
    set_by: project-settings-history-exports "Download" link (settings.html.heex:1075), email:history-export-complete (user_notifier.ex:324)
    effect: the project file to download (project_file_controller.ex:17)

config_variants:
  default: {}                             # STORAGE_BACKEND=local; read under this variant
  storage-gcs: { STORAGE_BACKEND: gcs }   # download is a redirect to a signed bucket URL (bootstrap.ex:900-917, gcs.ex:60-74)

inventory:
  routes:
    - get /project_files/:id/download  ProjectFileController :download (router.ex:227, pipe_through [:browser, :require_authenticated_user], router.ex:190)
  events:
    - RunLive.Index#show-export-modal     # owned by history-work-orders; handoff only
    - RunLive.Index#close-export-modal
    - RunLive.Index#confirm-export
  js_hooks: []
  policies:
    - Lightning.Policies.Exports.authorize(:download)
    - Lightning.Policies.ProjectUsers.permitted?(:access_project)
    - Lightning.Projects.MailRecipients.may_receive?/2
  workers:
    - Lightning.WorkOrders.ExportWorker
  api_endpoints: []
  emails:
    - email:history-export-complete      # UserNotifier.notify_history_export_completion/3, user_notifier.ex:314-329
  config:
    - STORAGE_BACKEND
    - STORAGE_PATH
    - GCS_BUCKET
    - Oban queue history_exports (bootstrap.ex:340)
  not_reachable_here:
    - FallbackController clauses other than {:error, :forbidden} (fallback_controller.ex:10-76)
    - ProjectFileDefinition.delete/1 (reached only by retention and project deletion, see section 4)

related:
  - lib/lightning_web/live/run_live/index.ex
  - lib/lightning_web/live/run_live/index.html.heex
  - lib/lightning_web/live/run_live/export_confirmation_modal.ex
  - lib/lightning/invocation.ex
  - lib/lightning/workorders/export_audit.ex
  - lib/lightning/workorders/export_worker.ex
  - lib/lightning/workorders/search_params.ex
  - lib/lightning/dataclip_scrubber.ex
  - lib/lightning/accounts/user_notifier.ex
  - lib/lightning/projects/mail_recipients.ex
  - lib/lightning/projects/file.ex
  - lib/lightning/projects.ex
  - lib/lightning/storage.ex
  - lib/lightning/storage/local.ex
  - lib/lightning/storage/gcs.ex
  - lib/lightning/storage/project_file_definition.ex
  - lib/lightning/policies/exports.ex
  - lib/lightning/policies/project_users.ex
  - lib/lightning/projects/scope.ex
  - lib/lightning_web/controllers/project_file_controller.ex
  - lib/lightning_web/controllers/fallback_controller.ex
  - lib/lightning_web/live/project_live/settings.ex
  - lib/lightning_web/live/project_live/settings.html.heex
  - lib/lightning_web/live/components/data_tables.ex
  - test/lightning/export_worker_test.exs
  - test/lightning/invocation_test.exs
  - test/lightning_web/controllers/project_file_controller_test.exs
  - test/lightning_web/controllers/project_mfa_enforcement_test.exs
  - test/lightning_web/live/run_live/index_test.exs
flows: []
---

## 1. Purpose

Editors take the full record behind a set of work orders (runs, steps, logs and I/O data) out of
Lightning as a zip, to hand to an auditor, a partner or an incident review. The file is built in the
background and the requester is told by email when it is ready. If this went wrong, the export would
either be incomplete when someone relies on it as the record, or would put health data and
credentials in the hands of someone no longer allowed to see them.

## 2. What it does

1. An editor filters the history page and confirms "Export history"; the page says the export has started and an email will follow.
2. The export is built in the background as a zip.
   - It covers every work order matching the filters, not just the page shown or the first 50.
   - It holds each work order's runs, steps, logs and input and output data, with credential and webhook secrets blanked out.
   - Exports run one at a time, and one that fails is marked "Failed" and is not tried again.
3. The requester gets an email with a download link once it's done, as long as they can still see the project.
4. Any member of the project sees every export in project settings under History exports, and can download any completed one.
   - Unfinished exports show as "Pending" with the download button disabled.
   - The download is refused to anyone without project access: non-members, members who haven't set up two-factor sign-in when the project requires it, and everyone once the project is scheduled for deletion.
5. Exports are deleted automatically once they are older than the project's history retention period.

**Straightforwardness: 3 of 5.** The export-then-email shape is familiar, but what counts as "complete", who gets told, and who can download are all a bit different from what you'd assume.

### Most surprising behaviours

- **(2)** If some log or data files fail to write, they are skipped and the export is still marked "Completed". Someone can hand over a zip as the full record when parts of it are missing. (6.1)
- **(3)** A failed export sends no email, even though the start message promised one. The requester waits and has to find "Failed" in settings themselves. (6.1)
- **(3)** Any member, including a viewer, can download any export, and the export is still built for someone who lost access while it ran; only their email is held back. (S07, 6.5)
- **(3)** Exported steps don't say which version of the workflow ran them, so they can't be tied back to the code that produced them. (6.1)
- **(4)** The History exports list doesn't update while you watch: an export stays "Pending" until you reload. (6.2)

## 3. Who can do what

Sources: `index.ex:651-684`, `:694-708` (`can_run_workflow`); `exports.ex:21-24` delegates download to
`:access_project`; `project_users.ex:134`, `:136`, `:193-194`; `scope.ex:149-152`, `:197`;
`mail_recipients.ex:28-32`.

| Action | Viewer | Editor | Admin | Owner | Superuser (no row) | Support (no row) |
|--------|--------|--------|-------|-------|--------------------|------------------|
| Start an export on history | no | yes | yes | yes | no | yes, when support access is on |
| See the history exports panel | yes | yes | yes | yes | no (cannot reach the page) | yes, when support access is on |
| Download any member's export | yes | yes | yes | yes | no, 403 | yes, when support access is on |
| Receive the completion email | requester only | requester only | requester only | requester only | n/a | requester only |

**Preconditions beyond role**
- Signed in (`router.ex:190`).
- If the project requires MFA, the member must be enrolled; otherwise download is 403 and the email is withheld (`project_users.ex:134`; `project_mfa_enforcement_test.exs:169-182`; `export_worker_test.exs:458-471`).
- The project must not be scheduled for deletion; otherwise download is 403 (`scope.ex:149-152`; `project_file_controller_test.exs:32-62`).
- The email goes only to the requester, and only if their account is not disabled or locked out and they still have project access when the job finishes (`export_worker.ex:77-81`, `user_notifier.ex:69-85`, `mail_recipients.ex:28-32`).
- Download needs the export to be `completed`; the panel disables the button otherwise (`settings.html.heex:1070-1090`).

## 4. What it touches

**Hop 1, history-work-orders (confirm)**
- Reads: the page's current `filters`, frozen into `SearchParams` (`index.ex:663-666`)
- Writes, in one transaction (`invocation.ex:1311-1340`):
  - `audit_events` insert, item `history_export`, event `requested`, metadata `search_params` (`invocation.ex:1313-1322`, `export_audit.ex:5-8`)
  - `project_files` insert, `type: :export`, `status: :enqueued`, `created_by` the requester (`invocation.ex:1323-1331`, `file.ex:38-45`)
  - `oban_jobs` insert, `ExportWorker` with `project_id`, `project_file`, `search_params` (`invocation.ex:1332-1338`, `export_worker.ex:95-116`)
- Flash: "History export started successfully. You will be notified by email after completion." or "Failed to start export. Please try again." (`index.ex:670-681`)

**Hop 2, oban:ExportWorker** (queue `history_exports`, `max_attempts: 1`, `export_worker.ex:29`)
- Writes `project_files.status` to `in_progress` (`export_worker.ex:65-66`)
- Reads every matching work order id, uncapped, then pages of 50: `work_orders`, `workflows`, `runs`, `run_steps`, `steps`, `log_lines`, `dataclips` with bodies, plus credentials and webhook auth methods for scrubbing (`export_worker.ex:173-217`, `:524-535`, `invocation.ex:628-632`, `dataclip_scrubber.ex:63-69`)
- Writes temp files: `export.json` (work orders, runs, steps, run steps), `logs/<run_id>.txt`, `dataclips/<dataclip_id>.json`, zipped to `<project_file_id>.zip` (`export_worker.ex:300-405`, `:427-443`)
- Stores the zip at `exports/<project_id>/<project_file_id>.zip` (`export_worker.ex:118-129`, `project_file_definition.ex:66-68`)
- Writes `project_files.status` to `completed` and `path` (`export_worker.ex:72-76`), or `failed` on any error (`export_worker.ex:85-92`, `:618-639`)

**Hop 3, email:history-export-complete**
- Subject "Your OpenFn History Export Is Complete", body links to `/project_files/<id>/download` (`user_notifier.ex:314-329`)
- Sent only on success; withheld (logged at info) when `MailRecipients.may_receive?` is false (`user_notifier.ex:69-85`)

**Hop 4, project-settings-history-exports**
- Reads `project_files` for the project, newest first, with `created_by` (`settings.ex:115`, `:208`, `projects.ex:2133-2142`)
- Writes: none

**Hop 5, controller:project-file-download**
- Reads `project_files`, `projects`, `project_users`, `users` (`project_file_controller.ex:17-25`, `scope.ex:175-199`)
- Writes: none
- Response: local backend sends the file (`project_file_controller.ex:27-29`); GCS backend redirects to a signed URL (`:31-32`, `gcs.ex:60-74`); denial renders 403 (`fallback_controller.ex:41-46`)

**Immediate side effects**
- Audit event `history_export.requested` (hop 1)

**Deferred side effects**
- `ExportWorker` runs later on its own queue (hop 2)
- The data retention job deletes export rows and stored zips older than the project's history retention period (`projects.ex:223-231`, `:1811-1826`, `:1828-1848`)
- Project deletion removes every stored export before the project row and stops if any cannot be removed (`extensions/project_hook.ex:48-75`, `projects.ex:1800-1809`); owned by the project deletion flows

**External, non-transactional effects**
- Zip upload to the storage backend; on GCS an HTTP upload (`gcs.ex:35-46`)
- Completion email via Swoosh (`user_notifier.ex:71`)

**Depends on config**
- `STORAGE_BACKEND`, `STORAGE_PATH`, `GCS_BUCKET` (`bootstrap.ex:900-927`); see `config_variants`

**Product limits**
- One export runs at a time per node; others wait in the queue (`bootstrap.ex:340`)
- A failed export is not retried (`export_worker.ex:29`)

## 5. Scenarios

```gherkin
Feature: Export work order history
  In order to hand the full record of a set of work orders to someone outside Lightning
  As an editor on a project
  I want to export the matching history and download it when it is ready

  @S01 @pending
  Scenario: Editor exports history and downloads it from project settings
    # Value: the full record of an incident can leave Lightning without anyone querying the database.
    Given I am an editor on project "Malawi HIV"
    And 12 work orders match my filters on history
    When I confirm "Export history"
    Then I see "History export started successfully. You will be notified by email after completion."
    And eventually the export job finishes
    And I receive the email "Your OpenFn History Export Is Complete"
    When I open project settings › History exports
    Then I see a row requested by me with status "Completed" and a "Download" link
    When I click "Download"
    Then a new tab receives a zip containing "export.json", a "logs/<run_id>.txt" per run and a "dataclips/<dataclip_id>.json" per step input and output
    And "export.json" lists the 12 work orders with their runs, steps and run steps
    # index.ex:661-684, invocation.ex:1311-1340, export_worker.ex:56-93, :300-405, user_notifier.ex:314-329
    # settings.html.heex:1067-1080, project_file_controller.ex:16-34
    # export_worker_test.exs:81-189, invocation_test.exs:2701-2722, index_test.exs:1593-1608, project_file_controller_test.exs:81-99

  @S02 @pending
  Scenario: Requester downloads from the email link
    # Value: the requester gets the file without hunting for it in settings.
    Given my history export on project "Malawi HIV" has completed
    When I open the link in the "Your OpenFn History Export Is Complete" email
    Then I receive "<project_file_id>.zip"
    # user_notifier.ex:324, project_file_controller.ex:16-34, router.ex:227

  @S03 @pending
  Scenario: Export covers every match, not only the first page or the first 50
    # Value: the export is the whole record the filters describe, not the slice the page could show.
    Given I am an editor and 51 work orders match my search term
    And history shows "50+"
    When I confirm "Export history" and the export completes
    Then "export.json" lists 51 work orders
    # invocation.ex:628-632 (no limit, unlike :580-582), export_worker.ex:152-159, :173-186
    # export_worker_test.exs:191-259 (51 work orders across pages)

  @S04 @pending
  Scenario: Secrets are scrubbed from exported dataclips
    # Value: an export handed outside Lightning does not carry credential or webhook secrets.
    Given a step whose credential has password "super-secret-value" wrote it into its output
    And a webhook request carried basic auth "secretuser:secretpass"
    When the history export for those work orders completes
    Then neither secret appears in any file under "dataclips/"
    And the redacted values read "***"
    # export_worker.ex:524-535, dataclip_scrubber.ex:63-69
    # export_worker_test.exs:486-544, :545-600

  @S05 @pending
  Scenario: An unfinished export cannot be downloaded
    # Value: nobody takes away a partial file as the record.
    Given an export on project "Malawi HIV" is "Enqueued" or "In progress"
    When I open project settings › History exports
    Then its filename reads "Pending"
    And its "Download" button is disabled with the tooltip "Export is not yet ready for download"
    # settings.html.heex:1070-1090, data_tables.ex:312-318, :329-334

  @S06 @pending
  Scenario: A failed export is shown as failed and never offered
    # Value: a broken export is never mistaken for a complete record.
    Given the export job fails while writing the archive
    When I open project settings › History exports
    Then the row shows status "Failed"
    And its "Download" button is disabled
    And no completion email is sent
    # export_worker.ex:85-92, :149-168, :618-639, settings.html.heex:1081-1089
    # export_worker_test.exs:261-364

  @S07 @pending
  Scenario: Another member downloads an export they did not request
    # Value: the team can retrieve an export without waiting on the person who asked for it.
    Given an editor's export on project "Malawi HIV" has completed
    And I am a viewer on that project
    When I click "Download" on that row in project settings › History exports
    Then I receive the zip
    # exports.ex:21-24, project_users.ex:136, settings.html.heex:1071-1080
    # project_file_controller_test.exs:81-99 (member with default role)

  @S08 @pending
  Scenario Outline: The archive is refused to people without project access
    # Value: exported health data never leaves through a stale link once access is gone.
    Given a completed export on project "Malawi HIV"
    And <who>
    When I open its download link
    Then I get a 403
    And no archive is sent
    Examples:
      | who                                                                    |
      | I am signed in but not a member of the project                         |
      | I am an admin and the project is scheduled for deletion                |
      | the project requires MFA and I am a member who has not enrolled        |
    # project_file_controller.ex:19-26, exports.ex:21-24, scope.ex:149-152, project_users.ex:134, fallback_controller.ex:41-46
    # project_file_controller_test.exs:32-79, project_mfa_enforcement_test.exs:169-182

  @S09 @pending
  Scenario Outline: The completion email is withheld from a requester who may no longer see the project
    # Value: a download link to project data is not mailed to someone the project no longer admits.
    Given I requested a history export on project "Malawi HIV"
    And <change> while it ran
    When the export completes
    Then the export row is "Completed"
    And I receive no completion email
    Examples:
      | change                                                         |
      | my account was disabled                                        |
      | the project started requiring MFA and I have not enrolled      |
    # export_worker.ex:77-81, user_notifier.ex:69-85, mail_recipients.ex:28-32
    # export_worker_test.exs:444-471

  @S10 @pending
  Scenario: Exports expire with the project's history retention
    # Value: exported data does not outlive the retention policy the project chose.
    Given project "Malawi HIV" keeps history for 30 days
    And an export was requested 31 days ago
    When the data retention job runs
    Then the export row is gone from project settings › History exports
    And its stored zip is deleted
    # projects.ex:223-231, :1811-1826, :1828-1848, project_file_definition.ex:55-64
```

## 6. Unclear value

### 6.1 Possible bugs

| What | Where | What a user sees | Disposition |
|------|-------|------------------|-------------|
| `format_steps` takes `:snapshot_it`, not `:snapshot_id`, so steps in `export.json` never carry their snapshot | `export_worker.ex:577-595` (line 587) | exported steps cannot be tied to the workflow version that ran them | fix |
| A log or dataclip file that fails to write is logged and skipped, and the export is still marked `completed` | `export_worker.ex:445-484`, `:486-522`, `:72-76` (see the TODO at `:457`) | a "Completed" zip silently missing some `logs/` or `dataclips/` files | fix |
| A failed export sends nothing, though the start flash promises an email | `index.ex:675`, `export_worker.ex:85-92` | the requester waits for an email that never comes and must find "Failed" in settings themselves | decide |
| Opening `/project_files/<id>/download` for an export with no `path` (enqueued, in progress, failed) passes `nil` to `Path.join` in the storage backend | `project_file_controller.ex:26`, `project_file_definition.ex:38-40`, `local.ex:55-56`, `gcs.ex:66`, `:109-110` | a 500 instead of "not ready"; reachable only from a hand-typed or old URL, since the panel disables the link | fix |
| Email body reads "You history export ... is completed" | `user_notifier.ex:322` | a typo in the notification | fix |

The export counts shown in the modal and button tooltip stop at 50 under a search term while the export covers every match; that row is owned by history-work-orders 6.1 and not repeated here.

### 6.2 Quirks and implementation details

| What | Where | Disposition |
|------|-------|-------------|
| The email links straight to the download controller, not to the history exports panel, so the email path never passes the exit view | `user_notifier.ex:324` | decide |
| The history exports panel reads `project_files` only at mount and has no subscription; status changes appear only after a reload | `settings.ex:115`, `:208`, `:683-724` | decide |
| The download link opens in a new tab | `settings.html.heex:1076` | preserve |
| On GCS the download is a redirect to a signed URL valid for one hour; on local storage the app streams the file | `project_file_controller.ex:27-32`, `gcs.ex:60-74`, `local.ex:55-59` | preserve |
| The file row is loaded with `Repo.get!` before authorization, so a non-member gets 404 for an unknown id and 403 for a real one | `project_file_controller.ex:17-26` | decide |
| Filters are frozen when the export is confirmed but evaluated when the job runs; work orders deleted between listing and paging drop out | `index.ex:666`, `export_worker.ex:173-186`, `:228-235` | preserve |
| A step shared by two runs is exported once per run | `export_worker.ex:205-207`, `:254-269` | preserve |
| Log lines with tied timestamps are ordered by id | `export_worker.ex:271-279`; `export_worker_test.exs:366-420` | preserve |
| A user who has requested an export cannot be deleted while the row exists | `accounts.ex:117-121`, `:879-882` | decide |
| Panel lists newest first; status labels are the humanized enum ("In progress"); headers are title case ("Export Date", "Export Requested By") | `projects.ex:2136-2139`, `data_tables.ex:300-303`, `:329-334` | decide |
| The exports table reuses the id `project_users_table` | `settings.html.heex:1068` | decide |
| The panel's section header passes `can_perform_action={true}`, so its permissions message never shows | `settings.html.heex:1056-1061` | preserve |

### 6.3 Unreachable or dead code

| What | Where | Why unreachable |
|------|-------|-----------------|
| `enqueue_export/3` error branch marks the file failed | `export_worker.ex:107-115` | it runs inside the `Ecto.Multi` that then rolls back, so the `failed` update and the file row both vanish |
| `{:error, :project_file_not_found}` path in `perform/1` | `export_worker.ex:414-419`, `:618-621` | the job is only enqueued in the same transaction that inserts the row; reachable only if the row is deleted before the job runs |
| `Projects.File.size` | `file.ex:19`, `:41` | never written by the export path |
| Moduledoc refers to `enqueue_export/2` | `export_worker.ex:7`, `:15`, `:22` | the function is arity 3 |

### 6.4 Performance and operational limits

| What | Where | User-visible? | Disposition |
|------|-------|---------------|-------------|
| `history_exports` queue concurrency 1, `max_attempts: 1` | `bootstrap.ex:340`, `export_worker.ex:29` | yes, a second export waits; a failure is final | preserve |
| Pages of 50 work orders; log and dataclip writes in async batches of 50 | `export_worker.ex:50`, `:155`, `:448`, `:488` | no | preserve |
| Id listing runs with three times the default database timeout | `export_worker.ex:184` | no, unless it times out and the export fails | preserve |
| `Task.async_stream` default 5s timeout per batch; a timeout exits the walk and fails the export | `export_worker.ex:449`, `:489`, `:164-167` | yes, as "Failed" | preserve |
| `export.json` assembled with a 512 KB delayed write buffer | `export_worker.ex:319` | no | preserve |

### 6.5 Things seen but not understood

- Wiped dataclips come back with a `nil` body; `File.write(path, nil)` is then called (`export_worker.ex:508-521`, `:524-535`). Not verified whether this errors and is logged (missing file) or writes an empty file.
- Steps with no output dataclip put `nil` into the dataclip id list used in `where d.id in ^ids` (`export_worker.ex:603-610`, `:526`). Not verified that this is harmless.
- The export does not check, when the job runs, that the requester still has access; only the email is gated (`export_worker.ex:56-93`). The archive is still built and visible to members. Unclear whether that is intended.

## 7. Not migrating

| Item | Reason | Decided by | Date |
|------|--------|------------|------|

## 8. Open questions

- Should a failed export notify the requester (6.1)?
- Should the email land on the history exports panel rather than the raw download (6.2), so the flow always passes its exit view?
- Should the history exports panel update live as the job progresses (6.2)?
- Is building the archive for a requester who has since lost access intended (6.5)?

## Proposed flows

- none. Project deletion removing stored exports is referenced, not owned; it belongs to flow-schedule-project-deletion.

## Proposed shared

- **shared-project-mail-recipients**: the `MailRecipients.may_receive?/2` gate (`mail_recipients.ex:28-32`, `user_notifier.ex:69-85`) applied to project mail: history export completion, failure alerts, digests and retention notices. S09 here would then reference it.
