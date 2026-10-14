---
id: flow-export-project-yaml
type: flow
title: Export a project as YAML
status: not-started
owner:

trigger:
  entry: project-settings-setup
  exit: project-settings-setup          # only on the failure path; the success path ends in a file download in the new tab
  surfaces:
    - project-settings-setup
    - controller:downloads-project-yaml
    - project-settings-setup
  reachable_when:
    - the "Export project" link renders for every viewer of the setup tab (settings.html.heex:252-266); the controller re-checks access itself

inherits: []                            # the controller does not mount shared-project-scope; it re-implements the gate with different outcomes (see section 3 and 6.2). The entry and exit views inherit it.

url_params:
  - name: id
    set_by: project-settings-setup "Export project" link (settings.html.heex:260)
    effect: the project to export (downloads_controller.ex:10-12)

config_variants:
  default: {}                           # read under this variant
  require-email-verification: { check_flag?(:require_email_verification): true }   # locked-out accounts are redirected before the controller runs (user_auth.ex:305-306)

inventory:
  routes:
    - get /download/yaml  DownloadsController :download_project_yaml (router.ex:195, pipe_through [:browser, :require_authenticated_user], router.ex:189)
  events: []
  js_hooks: []
  policies:
    - Lightning.Policies.ProjectUsers.permitted?(:access_project)
  workers: []
  api_endpoints: []
  emails: []
  config: []
  not_reachable_here:
    - Projects.export_project/4 :v1 format and snapshot_ids (projects.ex:1617-1629); this route always passes nil, :v2
    - FallbackController clauses other than {:error, :not_found} and {:error, :unauthorized}

related:
  - lib/lightning_web/controllers/downloads_controller.ex
  - lib/lightning_web/controllers/fallback_controller.ex
  - lib/lightning_web/controllers/user_auth.ex
  - lib/lightning_web/views/error_view.ex
  - lib/lightning_web/live/project_live/settings.html.heex
  - lib/lightning/projects.ex
  - lib/lightning/projects/scope.ex
  - lib/lightning/policies/project_users.ex
  - lib/lightning/workflows/yaml_format/v2.ex
  - lib/lightning/export_utils/duplicate_key_error.ex
  - test/lightning_web/controllers/download_controller_test.exs
  - test/lightning_web/controllers/project_mfa_enforcement_test.exs
  - test/lightning_web/confirmation_lockout_recovery_test.exs
  - test/lightning_web/live/project_live_test.exs
flows: []
---

## 1. Purpose

Any member of a project can take a copy of it as code: workflows, steps, triggers, edges, and the
names of its credentials, collections and channels, in the CLI's v2 project format. They use it to
keep a version, edit locally, or move a project elsewhere. If the export silently dropped a workflow,
or handed the definition to someone outside the project, the copy would either be wrong or a leak.

## 2. What it does

"Export project" on the setup tab opens a new tab that downloads `project-<id>.yaml`, or, when two
names would collide in the file, lands that tab back on project settings with the reason.

## 3. Who can do what

Source: `downloads_controller.ex:13-19` asks `ProjectUsers` for `:access_project`;
`project_users.ex:134` (MFA unsatisfied denies), `:136` and `:193-194` (standing is a role row or
support access); `scope.ex:149-152` (scheduled deletion denies).

| Action | Viewer | Editor | Admin | Owner | Superuser (no row) | Support (no row) |
|--------|--------|--------|-------|-------|--------------------|------------------|
| See the "Export project" link | yes | yes | yes | yes | no (cannot reach the page) | yes, when support access is on |
| Download the YAML | yes | yes | yes | yes | no, 401 | yes, when support access is on |

**Preconditions beyond role**
- Signed in, with no pending TOTP step and not locked out pending email confirmation (`user_auth.ex:288-311`).
- If the project requires MFA, the member must be enrolled, or the download is refused with 401 (`project_users.ex:134`; `project_mfa_enforcement_test.exs:162-167`).
- The project must exist (404 otherwise, `downloads_controller.ex:11-12`, `fallback_controller.ex:10-15`) and must not be scheduled for deletion (401, `scope.ex:149-152`).

## 4. What it touches

**Hop 1, project-settings-setup**
- Reads: none beyond the page's own assigns; the link is a plain `<a target="_blank">` (`settings.html.heex:258-264`)
- Writes: none

**Hop 2, controller:downloads-project-yaml**
- Reads: `projects` (three loads: `projects.ex:283`, `scope.ex:175`, `projects.ex:1619`), `project_users`, `users`, `workflows` (not soft-deleted, `project.ex:50`), `jobs`, `triggers`, `workflow_edges`, `project_credentials`, `credentials`, credential owners' `users`, `collections`, `channels`, channel auth methods (`v2.ex:744-755`)
- Writes: none
- Response: `200 text/yaml`, `content-disposition: attachment; filename="project-<id>.yaml"` (`downloads_controller.ex:21-29`), or `302` to `/projects/<id>/settings` with an error flash (`downloads_controller.ex:35-38`)

**Hop 3, project-settings-setup (failure path only)**
- Reads: as the view's own mount; shows the error flash
- Writes: none

**Immediate side effects**
- none (no audit event, no broadcast)

**Deferred side effects**
- none

**External, non-transactional effects**
- none

**Depends on config**
- `require_email_verification` flag (see `config_variants`)

**Product limits**
- Two workflows, or two steps in one workflow, whose names hyphenate to the same key block the whole export (`v2.ex:207`, `:642`, `:649`, `:690-704`)

## 5. Scenarios

```gherkin
Feature: Export a project as YAML
  In order to keep or move a copy of a project as code
  As any member of the project
  I want to download the project definition as a YAML file

  @S01 @pending
  Scenario: Member downloads the project YAML in a new tab
    # Value: anyone on the project can take a copy of it as code, even without edit rights.
    Given I am a viewer on project "project-1"
    And I am on the setup tab of project settings
    When I click "Export project"
    Then a new tab opens "/download/yaml?id=<project_id>"
    And that tab receives "project-<project_id>.yaml" as a "text/yaml" attachment
    And the file contains the name "project-1"
    And the original tab still shows project settings
    # settings.html.heex:258-264, downloads_controller.ex:20-29
    # project_live_test.exs:197-211, confirmation_lockout_recovery_test.exs:148-150

  @S02 @pending
  Scenario: Colliding names stop the export and say which ones
    # Value: a project never exports with one workflow silently overwriting another in the file.
    Given I am an editor on project "project-1"
    And project "project-1" has workflows "My Flow" and "My-Flow"
    When I click "Export project"
    Then the new tab lands on "/projects/<project_id>/settings"
    And I see an error naming "My Flow" and "My-Flow" and asking me to rename one and export again
    And no file is downloaded
    # downloads_controller.ex:31-38, v2.ex:165-170, :690-704, duplicate_key_error.ex:22-26
    # download_controller_test.exs:18-34

  @S03 @pending
  Scenario: Non-member cannot download a project's YAML by its id
    # Value: a project's definition is never handed to someone outside it.
    Given I am a registered user not on project "project-1"
    When I visit "/download/yaml?id=<project_id>"
    Then I see "Authorization Error"
    And no file is downloaded
    # downloads_controller.ex:13-19, fallback_controller.ex:24-29, error_view.ex:27-48
    # download_controller_test.exs:36-44 (asserts 401)

  @S04 @pending
  Scenario: Unenrolled member of an MFA-required project cannot download
    # Value: a sensitive project's full definition only leaves through MFA-protected accounts.
    Given project "project-1" requires MFA
    And I am an editor who has not enrolled in MFA
    When I visit "/download/yaml?id=<project_id>"
    Then I see "Authorization Error"
    # project_users.ex:134, project_mfa_enforcement_test.exs:162-167, :184-193

  @S05 @pending
  Scenario: Signed-out visitor logs in and gets the download
    # Value: a link to an export works after login, and never serves the file anonymously.
    Given I am not logged in
    When I visit "/download/yaml?id=<project_id>"
    Then I am on "/users/log_in"
    # user_auth.ex:290-299, :490-492; download_controller_test.exs:47-57
    # The return-to after login is stored (user_auth.ex:491) but no test reads it; assert only the redirect.

  @S06 @pending
  Scenario: The export carries credential names and owners, never secrets
    # Value: a member can share the YAML file without handing over the systems it connects to.
    Given project "project-1" has a credential "DHIS2 prod" owned by "owner@example.org"
    When I download the project YAML
    Then the file lists credential "DHIS2 prod" with owner "owner@example.org"
    And the file contains none of that credential's body
    # v2.ex:657-663, :766-777

  @S07 @pending @variant:require-email-verification
  Scenario: A locked-out account is sent to confirm its email instead of downloading
    # Value: an unconfirmed account past its grace period cannot pull project data.
    Given my account is locked out pending email confirmation
    And I am an editor on project "project-1"
    When I visit "/download/yaml?id=<project_id>"
    Then I am on "/users/confirm-required"
    # user_auth.ex:305-306, :332-341; confirmation_lockout_recovery_test.exs:82-103
```

## 6. Unclear value

### 6.1 Possible bugs

| What | Where | What a user sees | Disposition |
|------|-------|------------------|-------------|
| Success sets flash "Project yaml exported successfully" on a 200 response; Phoenix only persists flash on 3xx, so it is discarded and never shown | `downloads_controller.ex:28` | nothing; the message is dead | fix |
| Any serializer failure other than a name collision returns `{:error, {:serialize_failed, err}}`, a tuple no `FallbackController` clause matches | `v2.ex:170`, `downloads_controller.ex:40-41`, `fallback_controller.ex:65-76` | a 500 error page in the new tab instead of a reason | fix |
| A malformed `id` reaches `Repo.get` uncast in `get_project/1` before the policy's cast-first load runs | `projects.ex:282-287`, `scope.ex:171-175` | a Bad Request (Ecto cast error) page rather than Not Found | fix |
| Collision flash copy starts lowercase ("two workflows in this project...") and quotes keys with Elixir `inspect` | `duplicate_key_error.ex:22-26` | an error that reads like a log line | decide |

### 6.2 Quirks and implementation details

| What | Where | Disposition |
|------|-------|-------------|
| The controller re-implements the project gate with different outcomes from `shared-project-scope`: non-member, MFA-unenrolled and scheduled-for-deletion all get a 401 "Authorization Error" page, not "Not Found" or `/mfa_required` | `downloads_controller.ex:13-19`, `fallback_controller.ex:24-29` | decide |
| A non-member is told the project exists (401) while an unknown id gets 404; the LiveView gate deliberately hides existence | `downloads_controller.ex:11-19` vs `shared-project-scope` S03 | decide |
| On collision the new tab lands on project settings, so the user ends with two settings tabs open | `downloads_controller.ex:31-38` comment | preserve |
| `put_root_layout(false)` has no effect on a `send_resp` | `downloads_controller.ex:27` | decide |
| Credentials whose owner has no email are dropped from the file without notice | `v2.ex:658-663`, `:772-773` | decide |
| Collections export as names only, sorted; no collection data | `v2.ex:652-656` | preserve |
| Filename uses the project UUID, not its name | `downloads_controller.ex:25` | decide |
| Route sits under `/download/yaml?id=` with the project id in the query string, outside `/projects/:project_id` | `router.ex:195` | decide |

### 6.3 Unreachable or dead code

| What | Where | Why unreachable |
|------|-------|-----------------|
| Success flash | `downloads_controller.ex:28` | discarded on non-redirect responses (see 6.1) |
| `export_project/4` v1 and `snapshot_ids` branches | `projects.ex:1621-1628` | this route always passes `nil, :v2` (`downloads_controller.ex:20`) |
| `serialize_project(_, _)` `{:error, :not_a_project}` | `v2.ex:173` | `export_project` always passes a `%Project{}` (`projects.ex:1619`) |

### 6.4 Performance and operational limits

| What | Where | User-visible? | Disposition |
|------|-------|---------------|-------------|
| Project row loaded three times per request | `projects.ex:283`, `scope.ex:175`, `projects.ex:1619` | no | preserve |
| Whole project, every workflow with jobs, triggers and edges, built in memory in one request; no size cap or streaming | `v2.ex:744-755`, `downloads_controller.ex:29` | only on very large projects | preserve |

### 6.5 Things seen but not understood

- The test describing the non-member case is titled "renders a 404?" but asserts 401 (`download_controller_test.exs:36-44`); unclear whether 404 was the intent.

## 7. Not migrating

| Item | Reason | Decided by | Date |
|------|--------|------------|------|

## 8. Open questions

- Should the export gate match `shared-project-scope` (Not Found for non-members, `/mfa_required` for unenrolled members), or keep its 401 (6.2)?
- Should a collision be reported in the original tab rather than by redirecting the new one?
- Should support users without a row keep export access, given it includes credential owners' emails?
