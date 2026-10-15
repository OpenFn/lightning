---
id: flow-download-collection
type: flow
title: Download a collection
status: not-started
owner:

trigger:
  entry: project-settings-collections
  exit: project-settings-collections    # the page stays put; the response is a file attachment, so the browser saves it without navigating away
  surfaces:
    - project-settings-collections
    - controller:collections-download
    - project-settings-collections
  reachable_when:
    - the "Download" link renders on every collection row for every viewer of the tab, with no permission check (collections_component.ex:344-352); the controller re-checks access itself

inherits: []                            # the controller does not mount shared-project-scope or shared-authenticated-session (both are LiveView on_mount gates); it sits behind the plain :require_authenticated_user plug (router.ex:189-190) and re-implements the project gate with different outcomes (see section 3 and 6.2). The entry view inherits both.

url_params:
  - name: project_id
    set_by: project-settings-collections "Download" link (collections_component.ex:346-348)
    effect: the project whose collection is looked up; cast to a UUID first, 400 if malformed (collections_controller.ex:111, :143-148)
  - name: name
    set_by: project-settings-collections "Download" link (collections_component.ex:347)
    effect: the collection name, looked up only inside that project (collections_controller.ex:112; collections.ex:82-87); also the downloaded file name (collections_controller.ex:125)

config_variants:
  default: {}                           # read under this variant
  require-email-verification: { check_flag?(:require_email_verification): true }   # locked-out accounts are redirected before the controller runs (user_auth.ex:305-306)

inventory:
  routes:
    - get /download/collections/:project_id/:name  CollectionsController :download (router.ex:197-199, pipe_through [:browser, :require_authenticated_user], router.ex:189-190)
  events: []
  js_hooks: []
  policies:
    - Lightning.Policies.Collections.authorize(:access_collection) (policies/collections.ex:53-55), deferring to Lightning.Policies.ProjectUsers.permitted?(:access_project)
  workers: []
  api_endpoints: []
  emails: []
  config:
    - :lightning, LightningWeb.CollectionsController, :max_database_limit (config/config.exs:229-231)
  not_reachable_here:
    - CollectionsController.stream_all_in_chunks/3 first clause (limit <= max_database_limit) (collections_controller.ex:187-192); download always passes max_database_limit + 1 (:117), so only the unfold clause runs
    - Collections.get_all/3 key_pattern and timestamp filters (collections.ex:192-199); download passes nil and no timestamps
    - Collections.get_collection/1 cross-project lookup and FallbackController :conflict (collections.ex:66-72; fallback_controller.ex:31-39); download always scopes by project id
    - The rest of CollectionsController (put, put_all, get, delete, delete_all, stream) belongs to the Collections API capability

related:
  - lib/lightning_web/controllers/collections_controller.ex
  - lib/lightning_web/controllers/fallback_controller.ex
  - lib/lightning_web/controllers/user_auth.ex
  - lib/lightning_web/views/error_view.ex
  - lib/lightning_web/live/project_live/collections_component.ex
  - lib/lightning/collections.ex
  - lib/lightning/collections/item.ex
  - lib/lightning/collections/collection.ex
  - lib/lightning/policies/collections.ex
  - lib/lightning/policies/project_users.ex
  - lib/lightning/projects/scope.ex
  - test/lightning_web/collections_controller_test.exs
  - test/lightning_web/controllers/project_mfa_enforcement_test.exs
  - test/lightning_web/confirmation_lockout_recovery_test.exs
flows: []
---

## 1. Purpose

Any member of a project can take a full copy of a collection, the key-value data its jobs share
between runs, as a JSON file. They use it to inspect what jobs have stored, analyse it elsewhere or
keep a backup before clearing it out. If the download truncated the data, or handed it to someone
outside the project, the copy would either be wrong or a leak of health data.

## 2. What it does

1. Any member of the project, viewers included, clicks "Download" on a collection on the project's collections tab.
2. The browser saves a file named after the collection, holding every record in it (key, value, created and updated), however many there are; an empty collection gives an empty list.
3. The tab stays where it was.
4. Anyone else is refused: people not on the project and members who haven't set up two-factor on a project that requires it see "Authorization Error", and signed-out visitors are sent to log in.

**Straightforwardness: 4 of 5.** It does what it says; the surprises are about what's in the file and what happens when the download goes wrong.

### Most surprising behaviours

- **(3)** If something fails part way through, the browser still saves the file as if it worked, but it's cut off and won't open as valid data. Someone taking a backup before clearing a collection may not notice. (6.1)
- **(3)** Each record's value comes out as text wrapped in quotes rather than as data, so the file can't be read or re-imported without unpicking it twice. (6.2)
- **(3)** Someone outside the project can guess collection names: a name that exists gives "Authorization Error", one that doesn't gives "Not Found". (6.2)
- **(4)** A member who hasn't set up two-factor gets "Authorization Error" rather than being sent to set it up, unlike the rest of the project. (6.2)

## 3. Who can do what

Source: `collections_controller.ex:113`, `:150-159` asks `Policies.Collections` for
`:access_collection`, which defers to `ProjectUsers` `:access_project`
(`policies/collections.ex:53-55`); `project_users.ex:134` (MFA unsatisfied denies), `:136` and
`:193-194` (standing is a role row or support access); `scope.ex:149-152` (scheduled deletion denies).

| Action | Viewer | Editor | Admin | Owner | Superuser (no row) | Support (no row) |
|--------|--------|--------|-------|-------|--------------------|------------------|
| See the "Download" link | yes | yes | yes | yes | no (cannot reach the page) | yes, when support access is on |
| Download the collection | yes | yes | yes | yes | no, 401 | yes, when support access is on |

**Preconditions beyond role**
- Signed in, with no pending TOTP step and not locked out pending email confirmation (`user_auth.ex:288-311`).
- If the project requires MFA, the member must be enrolled, or the download is refused with 401 (`project_users.ex:134`; `project_mfa_enforcement_test.exs:216-254`).
- The collection must exist in the named project (404 otherwise, `collections.ex:82-87`, `fallback_controller.ex:10-15`), and the project must not be scheduled for deletion (401, `scope.ex:149-152`).

## 4. What it touches

**Hop 1, project-settings-collections**
- Reads: none beyond the tab's own collection list; the link is a plain `<a href>` with no `target` (`collections_component.ex:344-352`)
- Writes: none

**Hop 2, controller:collections-download**
- Reads: `collections` (by project id and name, `collections.ex:82-87`); `projects` and `project_users` for the access check (`scope.ex:171-199`); `collections_items`, ordered by id, 501 rows per query with `id > cursor` until a query returns none (`collections_controller.ex:114-119`, `:194-210`; `collections.ex:187-204`, `:430-441`)
- Writes: none
- Response: `200 application/json`, chunked, `content-disposition: attachment; filename="<name>.json"`, body `[` then one chunk per item then `]` (`collections_controller.ex:121-127`, `:167-183`). Each item is `{key, value, created, updated}` (`item.ex:54-65`). Errors render the HTML error pages: 400, 401 "Authorization Error", 404 (`fallback_controller.ex:10-29`; `error_view.ex`)

**Hop 3, project-settings-collections**
- Reads: none; the browser saves the attachment and the tab is not reloaded
- Writes: none

**Immediate side effects**
- none (no audit event, no broadcast, no usage tracking)

**Deferred side effects**
- none

**External, non-transactional effects**
- none

**Depends on config**
- `require_email_verification` flag (see `config_variants`)
- `max_database_limit` sets the page size of each database read, not the size of the file (`config/config.exs:229-231`)

**Product limits**
- none; every record is streamed, with no cap on count or size (`collections_controller.ex:194-210`)

## 5. Scenarios

```gherkin
Feature: Download a collection
  In order to inspect, analyse or back up the data my project's jobs share between runs
  As any member of the project
  I want to download a collection's contents as a JSON file

  @S01 @pending
  Scenario: Member downloads a collection from the collections tab
    # Value: anyone on the project can take a full copy of a collection, even without edit rights.
    Given I am a viewer on project "Malawi HIV"
    And the project has a collection "patients" with records "key-1" and "key-2"
    And I am on the "Collections" tab of project settings
    When I click "Download" on "patients"
    Then the browser receives "patients.json" as an "application/json" attachment
    And the file is a JSON array holding records "key-1" and "key-2", each with key, value, created and updated
    And the collections tab is still showing
    # collections_component.ex:344-352; collections_controller.ex:110-129, :167-183; item.ex:54-65
    # collections_controller_test.exs:1248-1286

  @S02 @pending
  Scenario: The download holds every record, not one page
    # Value: a backup taken before clearing a collection is complete, however large it is.
    Given the project has a collection "patients" with 1200 records
    When I download "patients"
    Then the file holds 1200 records in the order they were first stored
    # collections_controller.ex:117, :194-210 (pages of max_database_limit + 1 = 501 by id until empty); collections.ex:430-441
    # Read from code; no test downloads more than two records.

  @S03 @pending
  Scenario: An empty collection downloads as an empty array
    # Value: a member can tell a collection is empty rather than seeing an error.
    Given the project has a collection "patients" with no records
    When I download "patients"
    Then the file contains "[]"
    # collections_controller.ex:167-183; collections_controller_test.exs:1288-1299

  @S04 @pending
  Scenario: Non-member cannot download another project's collection
    # Value: a project's stored data is never handed to someone outside it, even with a guessed URL.
    Given I am a registered user not on project "Malawi HIV"
    And project "Malawi HIV" has a collection "patients"
    When I visit "/download/collections/<project_id>/patients"
    Then I see "Authorization Error"
    And no file is downloaded
    # collections_controller.ex:113, :150-159; policies/collections.ex:53-55; fallback_controller.ex:24-29
    # collections_controller_test.exs:1301-1313 (asserts 401)

  @S05 @pending
  Scenario: Unenrolled member of an MFA-required project cannot download
    # Value: a sensitive project's stored data only leaves through MFA-protected accounts.
    Given project "Malawi HIV" requires MFA
    And I am an editor on it who has not enrolled in MFA
    When I visit "/download/collections/<project_id>/patients"
    Then I see "Authorization Error"
    And an enrolled member of an MFA-required project still receives the file
    # project_users.ex:134; project_mfa_enforcement_test.exs:216-254

  @S06 @pending
  Scenario: Signed-out visitor is sent to log in
    # Value: a shared download link never serves collection data anonymously.
    Given I am not logged in
    When I visit "/download/collections/<project_id>/patients"
    Then I am on "/users/log_in"
    # user_auth.ex:290-299, :490-492
    # Read from code; no download test covers the signed-out case.

  @S07 @pending @variant:require-email-verification
  Scenario: A locked-out account is sent to confirm its email instead of downloading
    # Value: an unconfirmed account past its grace period cannot pull project data.
    Given my account is locked out pending email confirmation
    And I am an editor on project "Malawi HIV" with a collection "patients"
    When I visit "/download/collections/<project_id>/patients"
    Then I am on "/users/confirm-required"
    And no record from "patients" is served
    # user_auth.ex:305-306; collections_controller_test.exs:1328-1358; confirmation_lockout_recovery_test.exs:219-227
```

## 6. Unclear value

### 6.1 Possible bugs

| What | Where | What a user sees | Disposition |
|------|-------|------------------|-------------|
| The closing `]` is sent with `{:ok, conn} =`; if the client disconnects mid-download the per-item loop halts on `{:error, :closed}` and the final chunk then raises a `MatchError` | `collections_controller.ex:175-181` | nothing (they already cancelled); an error in the server logs and Sentry for every cancelled download | fix |
| The 200 status and opening `[` are sent before any item is read, so a database error mid-stream cannot become an error page | `collections_controller.ex:168-169`, `:201-209` | a truncated, invalid `.json` file saved as if it succeeded | decide |

### 6.2 Quirks and implementation details

| What | Where | Disposition |
|------|-------|-------------|
| The controller re-implements the project gate with different outcomes from `shared-project-scope`: non-member, MFA-unenrolled and scheduled-for-deletion all get a 401 "Authorization Error" page, not "Not Found" or `/mfa_required` | `collections_controller.ex:113`; `fallback_controller.ex:24-29` | decide |
| The collection is looked up before access is checked, so a non-member gets 404 for a name the project doesn't have and 401 for one it does, revealing which collection names exist | `collections_controller.ex:111-113` | decide |
| `value` is written as the stored JSON string, not parsed, so the file is an array of objects whose `value` is an escaped string | `item.ex:30`, `:54-65` | decide |
| Timestamps are named `created` and `updated` in the file, matching the API and preview, not `inserted_at` | `item.ex:58-61` | preserve |
| Each page is a separate query with no transaction, so writes during a long download can appear or be missed; ordering by id means records updated mid-download keep their position | `collections_controller.ex:185-210`; `collections.ex:430-441` | preserve |
| A final empty query runs after the last page to detect the end | `collections_controller.ex:204-206` | preserve |
| One HTTP chunk per item, unlike the API stream which batches 100 | `collections_controller.ex:172-179` vs `:12`, `:223` | preserve |
| Filename is the collection name, which the name format already keeps URL- and filename-safe | `collections_controller.ex:125`; `collection.ex:40-41` | preserve |
| Route sits under `/download/collections/:project_id/:name`, outside `/projects/:project_id`, beside `/download/yaml` | `router.ex:195-199` | decide |
| The tests send `accept: text/html,*/*`; the `:browser` pipeline only accepts html, so a request without it negotiates differently | `router.ex:22`; `collections_controller_test.exs:1244-1246`; `confirmation_lockout_recovery_test.exs:223-225` | preserve |

### 6.3 Unreachable or dead code

| What | Where | Why unreachable |
|------|-------|-----------------|
| `stream_all_in_chunks/3` first clause | `collections_controller.ex:187-192` | download passes `max_database_limit + 1` (`:117`), which fails the `limit <= max_database_limit` guard |
| `key_pattern` and timestamp filters in `get_all/3` | `collections.ex:192-199` | download passes `nil` and no timestamp params (`collections_controller.ex:115-119`) |

### 6.4 Performance and operational limits

| What | Where | User-visible? | Disposition |
|------|-------|---------------|-------------|
| Records are read 501 per query (`max_database_limit` 500 + 1) and streamed, so memory stays flat for large collections | `config/config.exs:229-231`; `collections_controller.ex:117`, `:199` | no | preserve |
| No cap on records or bytes; a multi-gigabyte collection streams for as long as it takes | `collections_controller.ex:194-210` | only on very large collections | decide |

### 6.5 Things seen but not understood

- The lead's brief cites the route at `router.ex:222-224`; in the tree read it is at `router.ex:197-199` (`:222-224` is `retry_run`). The view annotation's S19 already cites `:197-199`.
- `refute_serves` in the lockout test accepts any refusal shape, so S07's `/users/confirm-required` redirect is pinned only by `collections_controller_test.exs:1356`, not by the shared lockout test.

## 7. Not migrating

| Item | Reason | Decided by | Date |
|------|--------|------------|------|

## 8. Open questions

- Should the download gate match `shared-project-scope` (Not Found for non-members, `/mfa_required` for unenrolled members), or keep its 401 (6.2)? `flow-export-project-yaml` raises the same question; answer both together.
- Should access be checked before the collection lookup, so a non-member cannot probe collection names (6.2)?
- Should `value` be parsed into JSON in the file, so the download can be re-imported or read without double decoding (6.2)?
- Should a failure mid-stream be detectable by the user, given the file is saved with a 200 (6.1)?
