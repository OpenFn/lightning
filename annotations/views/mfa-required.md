---
id: mfa-required
type: view
title: MFA required for project
status: not-started
owner:

trigger:
  old_route: /mfa_required
  new_route: /mfa_required
  old_route_disposition: unchanged
  reachable_when:
    - the visitor is signed in with a valid session (shared-authenticated-session; `router.ex:189-190`, `:288-289`)
    - the signed-in user has not enrolled in MFA (`users.mfa_enabled` not truthy); enrolled users are redirected to `/projects` (`mfa_required.ex:16-24`)
    - normally reached because `:project_scope` redirected an unenrolled member of an MFA-required project here (`hooks.ex:98-101`; shared-project-scope S05), but nothing requires that (see 6.1)

inherits:
  - shared-authenticated-session    # login redirect, lockout, sidebar toggle, GDPR banner; InitAssigns runs before this view's own on_mount (router.ex:288)
  - shared-project-header           # side menu (Menu.profile_items here), account menu, global project picker and confirmation banner in the live layout; per batch 4 lead resolution it owns these on non-project pages too
  - shared-flash-messages   # added by lead (final pass)

url_params: []                      # takes no params; nothing records which project sent the user here (hooks.ex:100-101)

config_variants:
  default: {}                                                                  # read under this one
  require-email-verification: { lightning.require_email_verification: true }  # header renders the unconfirmed-account banner (layout_components.ex:260-277); owned by shared-authenticated-session S06 / shared-project-header S13

inventory:
  routes:
    - live /mfa_required  ProjectLive.MFARequired :index      # router.ex:288-289, live_session :default
  events: []                                                  # the view defines no handle_event; toggle_sidebar comes from InitAssigns (shared-authenticated-session)
  js_hooks: []                                                # ToggleSidebarViaCtrlM, SidebarHoverDelay, ReactComponent Picker come from the live layout (shared)
  policies: []                                                # the view calls none; ProjectUsers.blocked_by_mfa?/1 is called by the sender (hooks.ex:98-101)
  workers: []
  api_endpoints: []
  emails: []
  config: []
  not_reachable_here:
    - shared-project-header S01-S03 (breadcrumbs and picker button); this page passes neither breadcrumbs nor a title (mfa_required.html.heex:3-4)
    - shared-project-header S15, S16 (project side menu items); no project is assigned, so Menu.profile_items renders (layout_components.ex:220-228)
    - shared-authenticated-session S08, S09 (book-a-demo banner); this page passes no `:banner` slot to page_content (mfa_required.html.heex:1-5; layout_components.ex:237)
    - shared-usage-limits-banner; no `:check_limits` on_mount and no `:banner` slot
    - "`:assign_projects` result (hooks.ex:194-202), see 6.3"

related:
  - lib/lightning_web/live/project_live/mfa_required.ex
  - lib/lightning_web/live/project_live/mfa_required.html.heex
  - test/lightning_web/live/mfa_required_live_test.exs
  - shared-project-scope            # S05 is the gate that sends members here; this page does not inherit the project scope
  - profile-mfa                     # where both links lead
flows:
  - flow-require-project-mfa        # this view is a surface; S01 there lands here, S03 there leaves via "Visit your account"
---

## 1. Purpose

A member of a project that requires multi-factor authentication, who has not enrolled, is sent
here when they try to open that project. The page tells them why they were stopped and sends them
to their account settings to enrol. Without it, the requirement would turn people away with a
generic "not found" and no route to fix their own access.

## 2. What it does

- Unenrolled users see why project access was refused and a link to enrol on their profile
- Enrolled users who land here are sent to the projects list
- Blocked users can still move to their other projects and account pages from the side menu

**Straightforwardness: 4 of 5.** A small explanation page; the surprises are about what it leaves out, not what it does.

### Most surprising behaviours

- **(3)** The page never says which project needs MFA, and the project picker still lists it, so picking it just brings the user back here. (6.2)
- **(3)** Any signed-in user without MFA who opens this address is told "This project requires all members to use multi-factor authentication", even if none of their projects does. (6.1)

## 3. Who can do what

Source: `mfa_required.ex:16-24` (the view's own gate), `init_assigns.ex:17-35` (session gate,
shared-authenticated-session). No policy module is consulted by this view; project role,
superuser and support status play no part once the user is here.

| Action | Signed out | Signed in, not enrolled (any role, support, superuser) | Signed in, enrolled |
|--------|------------|-------------------------------------------------------|---------------------|
| See the page | no (log in) | yes | no (redirect to `/projects`) |
| Follow "Visit your account" or "your account" | n/a | yes | n/a |
| Use the side menu, account menu and project picker | n/a | yes | n/a |

**Preconditions beyond role**
- The page does not check that the user belongs to, or was sent by, any project that requires MFA (6.1).
- Who is sent here is decided upstream: only a user with standing on the project (a role, or support access) who has not enrolled (`project_users.ex:186-194`; shared-project-scope S05). A stranger to an MFA-required project gets not-found instead (`project_live_test.exs:2188-2200`).

## 4. What it touches

**Reads**: `user_tokens`, `users` (session, via shared-authenticated-session); `projects`, `project_users` for the unused `@projects` assign (`mfa_required.ex:9`; `hooks.ex:194-202`; `projects.ex:1160-1176`); the project tree for the global picker (`layout_components.ex:461-470`; `projects.ex:1210-1220`, via shared-project-header)

**Writes**: none

**Immediate side effects** (in the same request)
- none

**Deferred side effects** (later, elsewhere)
- none

**External, non-transactional effects** (calls out that can't be rolled back if the request fails)
- none

**Depends on config**
- none of its own; `require_email_verification` affects the inherited header banner only

**Product limits** (limits a user would notice and that we intend to keep)
- none

## 5. Scenarios

```gherkin
Feature: MFA required for project
  In order to get back into a project that requires multi-factor authentication
  As a member who has not enrolled in MFA
  I want to be told why I was stopped and where to enrol

  @S01 @pending
  Scenario: An unenrolled member is told why and where to enrol
    # Value: a member stopped by the project's MFA requirement understands the reason instead of thinking the project is gone or broken.
    Given I am an editor on project "Malawi HIV", which requires MFA
    And I have not enrolled in MFA
    When I visit "/mfa_required"
    Then I see "MFA Required for Project"
    And I see "This project requires all members to use multi-factor authentication."
    And I see a "your account" link to "/profile"
    And I see a "Visit your account" link to "/profile"
    # mfa_required.ex:32; mfa_required.html.heex:28-46
    # mfa_required_live_test.exs:11-18 asserts the copy and that an href="/profile" element exists (its project does not require MFA; see 6.1)

  @S02 @pending
  Scenario: Visiting the account hands off to enrolment
    # Value: the member has a one-click route to fix their own access without asking an admin.
    Given I am an unenrolled member on "/mfa_required"
    When I click "Visit your account"
    Then I am on "/profile"
    And the flow "flow-require-project-mfa" continues at enrolment (its S03)
    # mfa_required.html.heex:44-46; /profile is ProfileLive.Edit in the :services session (config/config.exs:58-59)
    # untested: no test clicks the link

  @S03 @pending
  Scenario: An enrolled user is not kept on this page
    # Value: someone who has already enrolled, or follows an old bookmark, isn't shown a page saying they are blocked.
    Given I have enrolled in MFA
    When I visit "/mfa_required"
    Then I am on "/projects"
    # mfa_required.ex:16-24; mfa_required_live_test.exs:20-29 (asserts {:redirect, %{to: "/projects"}})
    # same behaviour as flow-require-project-mfa S05; see section 8

  @S04 @pending
  Scenario: A blocked member can still reach their other work
    # Value: being blocked on one MFA-required project doesn't strand the member; they can open their other projects and account pages.
    Given I am an unenrolled member on "/mfa_required"
    Then the side menu shows "Projects", "User Profile", "Credentials" and "API Tokens"
    When I click "Projects" in the side menu
    Then I am on "/projects"
    # live.html.heex:42-43; layout_components.ex:207-231 (no project assigned, so profile_items); menu.ex:91-110
    # mfa_required.ex:13 (no item marked active); untested on this page
```

Arriving here is not restated: the redirect from a project page is shared-project-scope S05, and the
end-to-end journey (requirement turned on, member stopped, enrols, gets back in) is
flow-require-project-mfa S01 and S03. Sign-in, lockout and sidebar behaviour are
shared-authenticated-session S01-S07; the account menu and picker are shared-project-header S04-S12
and S17-S18.

## 6. Unclear value

### 6.1 Possible bugs

| What | Where | What a user sees | Disposition |
|------|-------|------------------|-------------|
| The page says "This project requires all members to use multi-factor authentication" to any signed-in unenrolled user who visits it, whether or not any of their projects requires MFA. The view's own test does exactly this: its project uses the factory default `requires_mfa: false`. Same item as flow-require-project-mfa 6.1 row 2 | `mfa_required.ex:16-24`; `mfa_required.html.heex:33-38`; `mfa_required_live_test.exs:7-18`; `conn_case.ex:178-187`; `project.ex:26` | a page claiming "this project" requires MFA when none does, with no project named | fix |

### 6.2 Quirks and implementation details

| What | Where | Disposition |
|------|-------|-------------|
| The page does not name the project that sent the user here, and nothing passes it along (also flow-require-project-mfa 6.2) | `hooks.ex:100-101`; `mfa_required.html.heex:28-39` | decide |
| Page title and card heading are title case ("MFA Required for Project") (also flow-require-project-mfa 6.2) | `mfa_required.ex:32`; `mfa_required.html.heex:28-30` | decide |
| The top bar renders an empty heading: the header gets neither a title nor breadcrumbs | `mfa_required.html.heex:3-4`; `layout_components.ex:283-296` | decide |
| No side menu item is marked active | `mfa_required.ex:13`; `menu.ex:93-108` | preserve |
| The global project picker still lists the MFA-required projects; picking one returns the user to this page | `layout_components.ex:461-470`; `hooks.ex:98-101` | decide |
| The enrolled-user redirect is a full `redirect` to `/projects` with no flash | `mfa_required.ex:20` | preserve |
| Both links use `navigate` but `/profile` is in another live_session (`:services`), so following them is a full page load | `mfa_required.html.heex:35`, `:44`; `config/config.exs:50-59`; `router.ex:288` | preserve |
| The route sits in live_session `:default` with the project routes although it is not project-scoped | `router.ex:288-289` | preserve |
| The view's gate tests `mfa_enabled` for truthiness while the project scope requires `== true`; equivalent only because the field defaults to `false` | `mfa_required.ex:19`; `scope.ex:221-222`; `user.ex:35` | preserve |

### 6.3 Unreachable or dead code

| What | Where | Why unreachable |
|------|-------|-----------------|
| `:assign_projects` on_mount | `mfa_required.ex:9`; `hooks.ex:194-202` | assigns `@projects`, which neither this view nor the live layout reads; only a deployment's custom `:menu_items` component could take it through `assigns_keys` (`layout_components.ex:207-218`), and none is configured in this repo |

### 6.4 Performance and operational limits

| What | Where | User-visible? | Disposition |
|------|-------|---------------|-------------|
| Each mount (static and connected) runs the unused `get_projects_for_user` query as well as the picker's project tree query | `hooks.ex:197`; `layout_components.ex:466-468` | no | preserve |

### 6.5 Things seen but not understood

- The test named "redirects to / if user already has mfa enabled" asserts `/projects` (`mfa_required_live_test.exs:20-29`); S03 follows the assertion.
- Channel tests note that this page still renders the session's socket token, so a blocked member could open a websocket by hand; the channel joins refuse them on their own (`run_channel_test.exs:3097-3099`; `workflow_channel_test.exs:1768-1770`). Nothing on this page depends on that, but a rebuild that drops the socket token here would change the threat model those tests describe.

## 7. Not migrating

| Item | Reason | Decided by | Date |
|------|--------|------------|------|

## 8. Open questions

- Should `/mfa_required` refuse or redirect users who have no MFA-required project, or name the project that sent them (6.1, 6.2)? (owner: product)
- S03 here and flow-require-project-mfa S05 describe the same single-page behaviour; the lead should keep one and reference it from the other.

## Proposed flows

- none. Referenced: flow-require-project-mfa (this view is a surface; S01 there lands here, S02 here hands off to its S03, S03 here duplicates its S05). Surfaces: project-settings-security, mfa-required, profile-mfa, workflows-index.

## Proposed shared

- none. Referenced: shared-authenticated-session (S01-S07, S10, S11), shared-project-header (S04-S12, S13, S17, S18); shared-project-scope S05 is referenced as the sender, not inherited.

## Lead resolution (batch 6)

- S03 duplicates flow-require-project-mfa S05; listed for the final cleanup.
