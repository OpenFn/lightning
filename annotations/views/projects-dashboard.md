---
id: projects-dashboard
type: view
title: Projects
status: not-started
owner:

trigger:
  old_route: /projects
  new_route: /projects
  old_route_disposition: unchanged
  reachable_when:
    - the user has a valid, active session (see shared-authenticated-session)
    - the deployment's `Lightning.Extensions.Routing` config still maps `/projects` to `DashboardLive.Index` (config/config.exs:50-53, router.ex:340-356)

inherits:
  - shared-authenticated-session    # login redirect, lockout, sidebar toggle, book-a-demo banner in the :banner slot (index.ex:22-27, init_assigns.ex:46-54)
  - shared-local-datetime           # "Last Updated" column (components.ex:136-139)
  - shared-project-header           # global project picker (Ctrl/Cmd+P, "View all projects"), account menu and role-dependent menu only; see not_reachable_here and 6.5
  - shared-flash-messages   # added by lead (final pass)

url_params: []                      # sort state lives in component assigns, not the URL (user_projects_section.ex:20, :24-37)

config_variants:
  default: {}                                                                  # read under this one unless a scenario is tagged
  support-user: { current_user.support_user: true }                            # projects.ex:103-133
  book-demo-banner: { lightning.book_demo_banner.enabled: true }               # init_assigns.ex:46-54; behaviour owned by shared-authenticated-session S08
  require-email-verification: { lightning.require_email_verification: true }   # header banner, layout_components.ex:259-276; accounts_confirmation_live_test.exs:30-38
  project-hook: { Lightning.Extensions.project_hook: <adapter with its own handle_create_project> }   # projects.ex:564, services/project_hook.ex:14-16
  routes-override: { Lightning.Extensions.Routing.routes: <list without this module at /projects> }   # config/config.exs:50-53

inventory:
  routes:
    - live /projects  DashboardLive.Index :index          # config-injected, live_session :services (config/config.exs:50-53, router.ex:340-356)
    - get /  Plugs.Redirect to: /projects                 # router.ex:329
  events:
    - DashboardLive.UserProjectsSection#sort
    - DashboardLive.ProjectCreationModal#validate
    - DashboardLive.ProjectCreationModal#save
    - DashboardLive.ProjectCreationModal#close_modal
  js_hooks:
    - TypewriterHook (welcome banner, components.ex:11; assets/js/hooks/index.ts:872-946)
    - JS.navigate on row click (components.ex:114)
    - inline onclick="event.stopPropagation()" on the collaborators and History links (components.ex:129, :148)
    - show_modal("create-project-modal") on both create buttons (user_projects_section.ex:69, :75)
    - LocalTimeConverter (via shared-local-datetime)
    - ReactComponent Picker (global picker, via shared-project-header)
  policies: []                      # no policy module is consulted by this view
  workers: []
  api_endpoints: []
  emails: []                        # the modal passes schedule_email? false (project_creation_modal.ex:55)
  config:
    - :lightning, Lightning.Extensions.Routing (routes, session_opts)
    - :lightning, Lightning.Extensions, :project_hook
  not_reachable_here:
    - shared-project-scope: `:project_scope` takes the no-project fallthrough (hooks.ex:134-136); its nil-user clause (hooks.ex:64-72) is pre-empted by InitAssigns (init_assigns.ex:22-24)
    - shared-usage-limits-banner: `:check_limits` is a no-op without a project (hooks.ex:241-249), so the `:banner` slot only ever carries the book-a-demo banner
    - shared-project-header: breadcrumb project picker and project menu items (layout_components.ex:220-226, :342); this page renders the `:title` branch (index.ex:28-32, layout_components.ex:283-296) and `Menu.profile_items` (menu.ex:91-110)
    - `:assign_projects` result (hooks.ex:194-202), see 6.3

related:
  - lib/lightning_web/live/dashboard_live/index.ex
  - lib/lightning_web/live/dashboard_live/components.ex
  - lib/lightning_web/live/dashboard_live/project_creation_modal.ex
  - lib/lightning_web/live/dashboard_live/user_projects_section.ex
  - lib/lightning_web/live/helpers/table_helpers.ex
  - lib/lightning_web/hooks.ex
  - lib/lightning/projects.ex
  - lib/lightning/projects/project.ex
  - lib/lightning/extensions/project_hook.ex
  - test/lightning_web/live/dashboard_live_test.exs
  - assets/test/e2e/pages/projects.page.ts
flows:
  - flow-schedule-project-deletion    # exit: the owner lands here
  - flow-invite-new-collaborator      # passes through: the invitee's signed-in landing, then the row into workflows-index
  - flow-collaborator-added-email     # referenced: creating a project here does NOT start it (project_creation_modal.ex:55)
  - flow-login-return-to
  - flow-account-revocation-teardown
  - flow-change-email-confirm
  - flow-forgot-password
  - flow-sso-login
  - flow-first-superuser-sign-in
  - flow-admin-created-account-confirm
  - flow-resend-account-confirmation   # added by lead (link lint)
---

## 1. Purpose

This is where every signed-in user lands: the list of projects they work in, and the place to start
a new one. People who work across several projects use it to find the right one, see their role and
how active it is, and jump to its workflows, history or collaborators. Without it, a new user has no
way to create their first project, and nobody has a single place to see everything they can reach.

## 2. What it does

- Anyone signed in sees the top-level projects they are a member of, and no others
- Anyone sees, per project, their role, the number of workflows and collaborators, and when a workflow last changed
- Support users also see projects that allow support access
- Anyone with no projects is offered to create one
- Anyone sorts the list by name or by last updated
- Anyone opens a project's workflows, collaborators or history from its row
- Anyone creates a project, becoming its owner, and sees the name it will be stored under first
- Anyone can back out of creating a project without creating one
- Anyone is pointed to documentation and community help
- Visiting the instance root takes anyone to this page
- Owners land here after scheduling a project for deletion

## 3. Who can do what

No policy module is called by this view. Membership filtering happens in the overview query
(`projects.ex:158-175`, `:103-133`).

| Action | Signed-in user | Project member (any role) | Support user | Superuser |
|--------|----------------|---------------------------|--------------|-----------|
| See the page | yes | yes | yes | yes |
| See a project's row | no | yes | if member, or the project allows support access | if member |
| Sort the list | yes | yes | yes | yes |
| Create a project | yes | yes | yes | yes |
| Open a project from its row | no | yes (gate is shared-project-scope) | yes | if member |

**Preconditions beyond role**
- A valid, active session is required (shared-authenticated-session S01 to S05).
- Only top-level projects are listed; sandboxes never are (`projects.ex:108`, `:165`).
- Projects scheduled for deletion are not filtered out (see 6.1).
- The creator is always made the owner; no other user can be added from this form (`project_creation_modal.ex:48-54`).
- Create is not gated by role, plan or policy in the default adapter (`extensions/project_hook.ex:14-18`); a `project-hook` adapter may refuse it.

## 4. What it touches

**Reads**: `projects`, `project_users`, `workflows` (overview, `projects.ex:101-187`); `users` (session, via shared-authenticated-session); the picker tree via shared-project-header; `projects` again for the unused `:assign_projects` assign (`hooks.ex:197`)

**Writes**: `projects` (insert), `project_users` (insert, the creator as owner) (`projects.ex:562-575`, `extensions/project_hook.ex:14-18`)

**Immediate side effects** (in the same request)
- PubSub `ProjectCreated` on `projects_events:all` after commit (`projects.ex:571-574`, `projects/events.ex:81-86`, `:163`)
- No email: `schedule_email?` is false (`project_creation_modal.ex:55`, `projects.ex:565-567`)
- No audit event (`projects.ex:562-575`)

**Deferred side effects** (later, elsewhere)
- none

**External, non-transactional effects**
- none in the default adapter; a `project-hook` adapter runs inside the same transaction (`projects.ex:563-564`)

**Depends on config**
- `Lightning.Extensions.Routing` injects the route and its live_session options (`config/config.exs:50-53`, `router.ex:340-356`)
- `Lightning.Extensions.project_hook` (`config/config.exs:47`, `services/project_hook.ex:14-16`)

**Product limits**
- Project description at most 240 characters (`project.ex:107`, helper text `project_creation_modal.ex:121-123`)

## 5. Scenarios

```gherkin
Feature: Projects
  In order to find my work and start new work
  As anyone signed in to Lightning
  I want to see the projects I belong to and create new ones

  @S01 @pending
  Scenario: I see the projects I belong to and no others
    # Value: a project's existence and name are never disclosed to people who are not on it.
    Given I am an owner of "project-1" and an admin of "project-2"
    And "project-3" exists with only other members
    When I open "/projects"
    Then I see rows for "project-1" and "project-2"
    And I do not see "project-3"
    # projects.ex:135-142, :158-175; user_projects_section.ex:39-49
    # dashboard_live_test.exs:62-102 (refute row for project_3; assert_project_listed for the others)

  @S02 @pending
  Scenario: Each row shows my role, counts and last change
    # Value: people can tell at a glance what they can do in each project and which ones are active.
    Given I am an admin of "project-2", which has an owner and me as collaborators
    And "project-2" has two workflows last updated "2023-10-05 12:00" and "2023-10-03 12:00" and one deleted workflow
    When I open "/projects"
    Then the "project-2" row shows role "Admin"
    And workflows "2"
    And collaborators "2", linking to "/projects/<project-2 id>/settings#collaboration"
    And last updated at "2023-10-05 12:00:00 UTC", shown per shared-local-datetime
    # components.ex:116-143; projects.ex:166-174
    # dashboard_live_test.exs:476-538 (role, workflow count, collaborator link and count, data-iso-timestamp); :215-241 (deleted workflow not counted)

  @S03 @pending @variant:support-user
  Scenario: Support users also see projects that asked for support
    # Value: support staff can find a project that opted into support without being added as a member.
    Given I am a support user and an owner of "project-1"
    And "project-4" allows support access and I am not a member
    And "project-3" does not allow support access and I am not a member
    When I open "/projects"
    Then I see "project-1" with role "Owner"
    And I see "project-4" with role "Support"
    And I do not see "project-3"
    # projects.ex:103-133; dashboard_live_test.exs:104-163, helper :491-498 ("Support" for a support row)

  @S04 @pending
  Scenario: Someone with no projects is offered to create one
    # Value: a new user is never stuck on an empty page with no next step.
    Given I am not a member of any project
    When I open "/projects"
    Then I see "No projects found." and "Create a new one."
    When I click "Create a new one."
    Then the "Create a new project" modal opens
    # user_projects_section.ex:62-71; components.ex:72-73; table.ex:304-324
    # dashboard_live_test.exs:15-25 (text only; the click is read from code)

  @S05 @pending
  Scenario: Sorting by name
    # Value: people with many projects can find one by name.
    Given I am a member of three projects
    When I open "/projects"
    Then the projects are listed by name, A to Z
    When I click the "Name" column header
    Then they are listed Z to A
    When I click it again
    Then they are listed A to Z
    # user_projects_section.ex:20, :24-49; table_helpers.ex:110-118; projects.ex:177-181
    # dashboard_live_test.exs:323-353; :380-435 (support user)

  @S06 @pending
  Scenario: Sorting by last updated
    # Value: people can bring the projects that changed most recently, or least recently, to the top.
    Given I am a member of three projects with workflows changed at different times
    When I click the "Last Updated" column header
    Then the projects are listed oldest change first
    When I click it again
    Then they are listed newest change first
    # user_projects_section.ex:24-37; projects.ex:183-187
    # dashboard_live_test.exs:437-473 (asserts the ascending click only after the default name sort)

  @S07 @pending
  Scenario: A crafted sort request is ignored
    # Value: a malformed or hostile request can neither crash the page nor grow server memory by creating atoms.
    Given I am on "/projects" with three projects
    When a "sort" event arrives with a column that does not exist
    Then the list stays sorted by name, A to Z
    And the page keeps working
    # user_projects_section.ex:13, :39-44; table_helpers.ex:84-86, :93-94
    # dashboard_live_test.exs:355-378

  @S08 @pending
  Scenario: A row leads into the project
    # Value: one click takes people from the list to the part of the project they came for.
    Given I am a member of "project-1"
    When I click anywhere on the "project-1" row
    Then I am on "/projects/<project-1 id>/w"
    When I go back and click the collaborators count on that row
    Then I am on "/projects/<project-1 id>/settings#collaboration"
    When I go back and click "History" on that row
    Then I am on "/projects/<project-1 id>/history"
    # components.ex:111-115, :126-132, :145-151
    # assets/test/e2e/pages/projects.page.ts:22-29 (row click); dashboard_live_test.exs:527 (collaborators href only)

  @S09 @pending
  Scenario: Creating a project makes me its owner
    # Value: anyone can start a project the same day without waiting on an administrator, and it is never left without an owner.
    Given I am on "/projects"
    When I open "Create project", enter name "My Awesome Project" and description "This is a really awesome project"
    And I click "Create project"
    Then I am on "/projects" and see "Project created successfully"
    And "my-awesome-project" is listed with role "Owner"
    # project_creation_modal.ex:39-62; projects.ex:562-575; project.ex:282-302, :304-323
    # dashboard_live_test.exs:243-269 (project created and listed; role read from code)

  @S10 @pending
  Scenario: I see the stored name before creating
    # Value: people know the exact name their project will be stored and referred to by before they commit to it.
    Given the "Create a new project" modal is open
    When I type "My Awesome Project" in "Name"
    Then I see "Your project will be named my-awesome-project."
    # project_creation_modal.ex:26-37, :106-111; helpers.ex:221-238; pills.ex:98-105
    # dashboard_live_test.exs:248-258 (hidden name field value)

  @S11 @pending
  Scenario: A name with no usable characters is refused
    # Value: no project is created with an empty name that nobody could find or refer to.
    Given the "Create a new project" modal is open
    When I enter name "!!!" and submit
    Then I see "can't be blank" under "Name"
    And no project is created
    # project_creation_modal.ex:46-48, :64-72; helpers.ex:221-238; project.ex:155-157
    # dashboard_live_test.exs:289-302

  @S12 @pending
  Scenario: A description over 240 characters is refused
    # Value: people learn the limit while typing instead of losing what they wrote on submit.
    Given the "Create a new project" modal is open
    When I enter a name and a 241-character description
    Then I see an error under "Description"
    And the "Create project" button is disabled
    # project.ex:107; project_creation_modal.ex:26-37, :121-123, :127-131

  @S13 @pending
  Scenario: Cancelling creates nothing
    # Value: backing out of the form never leaves a stray project behind.
    Given I have filled in the "Create a new project" modal
    When I click "Cancel"
    Then I am on "/projects"
    And no project has been created
    # project_creation_modal.ex:21-24, :135-143; dashboard_live_test.exs:304-321

  @S14 @pending
  Scenario: The form cannot be used to attach a project under someone else's
    # Value: nobody can bypass sandbox provisioning rules or add other people to a project by crafting the create request.
    Given "other-project" exists and I have no role on it
    When I submit the create form with an extra "parent_id" of "other-project"
    Then a top-level project is created with me as its only member
    # project_creation_modal.ex:41-54; dashboard_live_test.exs:271-287 (parent_id is nil; the project_users override is read from code)

  @S15 @pending
  Scenario: Creating a project does not email me that I was added to it
    # Value: the creator is not sent an access notice for something they just did themselves.
    When I create project "my-awesome-project"
    Then the flow "flow-collaborator-added-email" has not started for me
    # project_creation_modal.ex:55; projects.ex:562-568, :836-847

  @S16 @pending
  Scenario: The welcome text points to help
    # Value: people who don't know where to start can find documentation and the community from the first page they see.
    When I open "/projects"
    Then I eventually see a greeting with my first name
    And a link to "docs.openfn.org" and a link to "community.openfn.org", each opening in a new tab
    # components.ex:7-51; assets/js/hooks/index.ts:872-946

  @S17 @pending
  Scenario: The instance root opens the projects list
    # Value: the bare instance address takes signed-in people straight to their work.
    Given I am logged in
    When I visit "/"
    Then I am on "/projects"
    # router.ex:329; plugs/redirect.ex (call/2). Signed out, "/projects" then follows shared-authenticated-session S01.

  @S18 @pending
  Scenario: The owner lands here after scheduling deletion
    # Value: the owner gets confirmation and is returned to a page that still exists.
    Given the flow "flow-schedule-project-deletion" has been completed by me for "project-1"
    Then I am on "/projects"
    And I see "Project scheduled for deletion"
    # project_deletion_modal.ex:49-53; flow-schedule-project-deletion S01. The listing that follows is 6.1.

  @S19 @pending
  Scenario: A newly invited collaborator finds their project here
    # Value: someone who has just joined lands on the project they were invited to without needing its URL.
    Given the flow "flow-invite-new-collaborator" has added me as an editor of "Malawi HIV"
    And I have signed in
    Then I am on "/projects" and see "Malawi HIV" with role "Editor"
    # user_auth.ex:514; flow-invite-new-collaborator S01; the row click is S08
```

## 6. Unclear value

### 6.1 Possible bugs

| What | Where | What a user sees | Disposition |
|------|-------|------------------|-------------|
| Projects scheduled for deletion are still listed: neither overview query checks `scheduled_deletion`, unlike `projects_for_user_query` (same row in flow-schedule-project-deletion 6.1) | `projects.ex:103-115`, `:158-175`; contrast `:1138-1146` | after "Project scheduled for deletion" the project is still in the list; clicking it shows "Not Found" (shared-project-scope S04) | fix |
| A project whose workflows are all deleted disappears from the list: `is_nil(w.deleted_at)` sits in the WHERE of a left join, so every joined row is filtered out | `projects.ex:107-108`, `:164-165` | a project with only deleted workflows is missing, or "No projects found." if it was the only one; a project with no workflows at all is still shown | fix |
| Any parent re-render resets the list's sort and the create form, because both components reset state in `update/2`; collapsing the sidebar reassigns `current_user` and triggers it (read from code, not run) | `user_projects_section.ex:15-22`; `project_creation_modal.ex:8-19`; `init_assigns.ex:84-95`; `index.ex:43-54` | after collapsing the sidebar, a "Last Updated" sort snaps back to name A to Z, and a half-filled create form is cleared | fix |
| A failed save rebuilds the error changeset from `form_changeset` with the raw params, discarding the errors the insert actually returned | `project_creation_modal.ex:64-72` | under the `project-hook` variant, or any insert error `form_changeset` doesn't check (e.g. owner validation), the modal stays open with no error and nothing created | fix |

### 6.2 Quirks and implementation details

| What | Where | Disposition |
|------|-------|-------------|
| "Last Updated" is the latest `updated_at` of a non-deleted workflow, not of the project, its settings or its runs; a project with no workflows shows "N/A" | `projects.ex:172`, `:117`; `components.ex:135-142` | decide |
| The dashboard renders its own "N/A" for a missing date, where `Common.datetime` would show "--" (shared-local-datetime S07) | `components.ex:135-142` | decide |
| Clicking the timestamp copies it instead of opening the row (row in shared-local-datetime 6.2) | `components.ex:111-115`, `:136-139` | decide |
| Support users' lists are merged and sorted in Elixir: names compare bytewise (uppercase before lowercase) and projects with no workflows sort first ascending; everyone else is sorted by Postgres collation with nulls last both ways | `projects.ex:128-132`, `:150-156`, `:177-187` | decide |
| A support user who is also a member sees their member role, because member rows come first before `uniq_by` | `projects.ex:128-131` | preserve |
| Top-level project names need not be unique; the unique index only covers sandboxes | `priv/repo/migrations/20250824190735_add_sandbox_fields_to_projects.exs:14-17`; `project.ex:122` | decide |
| Sandboxes are never listed, so a user whose only membership is a sandbox sees "No projects found." while the global picker lists that sandbox | `projects.ex:108`, `:165`; shared-project-header S05 | decide |
| The collaborators count uses `href` (full page load) while "History" and the row use LiveView navigation | `components.ex:114`, `:126-132`, `:145-151` | decide |
| Cancel and the close button reload the page with `push_navigate` instead of hiding the modal | `project_creation_modal.ex:21-24` | decide |
| After a successful create the user stays on the list rather than being taken into the new project | `project_creation_modal.ex:57-62` | decide |
| The modal and its form are always in the page, hidden; both create buttons only reveal it client-side | `index.ex:49-54`; `user_projects_section.ex:69`, `:75` | decide |
| The modal's close button has id `close-credential-modal-type-picker`, copied from the credential modal | `project_creation_modal.ex:84` | fix |
| A crafted sort column is stored in `sort_key`, so no header shows as active and the next "Name" click sorts A to Z rather than toggling | `user_projects_section.ex:24-37`; `table_helpers.ex:110-118` | decide |
| The list never updates live: being added to or removed from a project elsewhere, or another user creating one, shows only after reload; `ProjectCreated` is broadcast but nothing in `lib/` subscribes | `user_projects_section.ex:15-22`; `projects.ex:571-574`; `projects/events.ex:81-86`, `:140-142` | decide |
| Creating a project writes no audit event | `projects.ex:562-575`; `extensions/project_hook.ex:14-18` | decide |
| The greeting depends on the browser's clock ("Good evening, Ama. You're up late!" from 10pm to 3am) | `assets/js/hooks/index.ts:879-904` | decide |
| Without JavaScript the heading and welcome text are empty; the text exists only in a data attribute | `components.ex:9-35`; `assets/js/hooks/index.ts:872-946` | decide |
| The empty state shows the button text "Create a new one." above the message "No projects found." | `table.ex:317-323`; `user_projects_section.ex:64-70` | decide |
| Column headers are title case ("Last Updated") | `components.ex:104` | decide |

### 6.3 Unreachable or dead code

| What | Where | Why unreachable |
|------|-------|-----------------|
| `:project_scope` on_mount | `index.ex:8`; `hooks.ex:64-72`, `:134-136` | no `project_id` param, so it falls through; the nil-user clause is pre-empted by InitAssigns |
| `:check_limits` on_mount | `index.ex:10`; `hooks.ex:241-249` | no `project` assign, so it always continues unchanged; the usage limits banner cannot appear here |
| `:assign_projects` on_mount | `index.ex:9`; `hooks.ex:194-202` | assigns `@projects`, which neither this view nor the live layout reads |
| `require Logger` | `index.ex:6`; `user_projects_section.ex:8` | no Logger call in either module |
| `user` attr on `user_projects_table` | `user_projects_section.ex:57`; `components.ex:64-160` | never read by the component |
| `assign(project: project)` before navigating away | `project_creation_modal.ex:61` | the socket is replaced by `push_navigate` immediately |
| `ProjectCreated` broadcast | `projects/events.ex:81-86` | no subscriber in `lib/` (`projects_test.exs:5029` subscribes in tests only) |

### 6.4 Performance and operational limits

| What | Where | User-visible? | Disposition |
|------|-------|---------------|-------------|
| No pagination; every mount and every sort click re-runs the full overview query | `user_projects_section.ex:39-49`; `projects.ex:135-142` | no, until a user has many projects | decide |
| Support users run two queries and merge and sort in memory, including every support-access project on the instance | `projects.ex:103-133` | no | decide |
| An unused `get_projects_for_user` query on every mount | `hooks.ex:194-202` | no | decide |
| Global picker tree rebuilt on renders (row in shared-project-header 6.4) | `live.html.heex:110-112`; `layout_components.ex:464-475` | no | decide |
| The typewriter types at 50 ms per character with 200 ms and 1000 ms pauses, so the help links take several seconds to become clickable | `assets/js/hooks/index.ts:916-941` | yes | decide |
| Description capped at 240 characters | `project.ex:107` | yes, helper text and error | preserve |

### 6.5 Things seen but not understood

- Projects created here get `env` nil: `project_with_users_changeset` skips `set_default_env_for_root_projects`, which `changeset/2` and `form_changeset/2` apply ("main"). Whether anything reads `env` on a root project was not established (`project.ex:72-103`, `:138-160`, `:282-302`).
- `create_project/2` never calls `ProjectHook.handle_project_validation/1`, which `update_project/3` does; under a hosted `project-hook` adapter, creation may skip validation that edits get (`projects.ex:562-575`, `:589-593`).
- The route is config-injected; a deployment could map `/projects` to another module (`config/config.exs:50-53`, `router.ex:340-356`). Every signed-in redirect still targets `/projects` (`user_auth.ex:514`, `hooks.ex:51`, `:307`).
- Inheriting shared-project-header: that file's `reachable_when` assumes a project page, but its global picker, account menu and role-dependent menu scenarios (S04 to S12, S17, S18) also apply on this non-project page. Whether to inherit it or split the picker out was not decided here.
- The lead's inventory row says project creation queues flow-collaborator-added-email; this modal passes `schedule_email?` false (`project_creation_modal.ex:55`), as flow-collaborator-added-email section 8 also notes. S15 asserts it does not start.

## 7. Not migrating

| Item | Reason | Decided by | Date |
|------|--------|------------|------|

## 8. Open questions

- Should projects scheduled for deletion, and projects whose workflows are all deleted, be listed (see 6.1)?
- Should a user whose only membership is a sandbox see it here (see 6.2)?
- Should the list update live on membership changes, and should creation be audited (see 6.2)?
- Should creating a project take the user into it, and should "Last Updated" mean workflow edits, any project change or run activity (see 6.2)?
- Should this view inherit shared-project-header, or should the global picker and non-project side menu move to their own shared annotation (see 6.5 and Proposed shared)?

## Proposed flows

- `flow-login-return-to` (already proposed by the lead; referenced, not created here): signing in without a stored return path lands on `/projects`. Surfaces: auth-login (`user_auth.ex:61-70`), projects-dashboard (`user_auth.ex:514`).

## Proposed shared

- `shared-account-side-menu`: the side menu on non-project pages (`Menu.profile_items`: Projects, User Profile, Credentials, API Tokens, with the current one marked) plus the global picker when no project is in scope. Surfaces: projects-dashboard (`index.ex:14`, `layout_components.ex:207-231`, `menu.ex:91-110`; `dashboard_live_test.exs:27-60`), credentials-index (`credential_live/index.ex:14`), profile, profile-tokens.

## Lead resolution (batch 4)

- The lead's row was wrong: project creation does not queue the collaborator-added email (`schedule_email?` false). S15 stands as written.
- `shared-account-side-menu` declined: shared-project-header owns the side menu, account menu and picker.
- `flow-login-return-to` created.
