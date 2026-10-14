---
id: admin-users
type: view
title: Admin settings › Users
status: not-started
owner:

trigger:
  old_route: /settings/users (config-injected), /settings/users/:id/delete
  new_route:
  old_route_disposition: unchanged
  reachable_when:
    - the session is admitted by shared-authenticated-session (`router.ex:189-190` for the delete route, `router.ex:349` for the index route)
    - the viewer is a superuser (`user_live/index.ex:7`; `hooks.ex:40-53`; `policies/users.ex:19-21`); the gate itself is the proposed shared-admin-space
    - "/settings/users exists only because `Lightning.Extensions.Routing` lists it (`config/config.exs:50-61`); the router mounts those routes in the `:services` live_session (`router.ex:340-355`)"
    - "/settings/users/:id/delete is a static route in the `:settings` live_session (`router.ex:268-271`) and needs an existing user id (`user_live/index.ex:28-32`; `accounts.ex:372`)"
    - entered from the "Users" item in the admin side menu (`layouts/settings.html.heex:48-54`) or the "Admin Menu" link in the project side menu (shared-project-header S17)

inherits:
  - shared-admin-space
  - shared-authenticated-session      # login redirect, revoked sessions, TOTP and lockout gates, sidebar; S01 to S07 and S11. S08 to S10 do not apply (6.3)
  - shared-project-header             # no-project parts only: the confirmation banner in LayoutComponents.header (S13, S14), the global project picker opened by keyboard (S04, S06, S08, S10, S11, S12), the account menu (S18)
  - shared-user-deletion-modal        # the /delete route; is_current_user false, logout false, return_to /settings/users (user_live/components.ex:17-27); S01 to S09
  - shared-flash-messages   # added by lead (final pass)

url_params:
  - name: id (path segment of /settings/users/:id/delete)
    set_by: admin-users (the "Delete" and "Delete now" links, user_live/components.ex:150, :193, :199)
    effect: loads that user into the deletion modal with `Accounts.get_user!/1`; an unknown id raises (6.2)

config_variants:
  default: { Lightning.Extensions.Routing.routes: "includes {\"/settings/users\", UserLive.Index, :index, []}" }   # read under this one (config/config.exs:50-61)
  routing-without-users-index: { Lightning.Extensions.Routing.routes: "a deployment's list that omits /settings/users" }   # router.ex:341-355; the delete route and the menu link remain (6.5)
  require-email-verification: { lightning.require_email_verification: true }   # inherited; shared-authenticated-session S04 to S06, shared-project-header S13, S14

inventory:
  routes:
    - live /settings/users  UserLive.Index :index              # config/config.exs:60, mounted by router.ex:351-355 in :services
    - live /settings/users/:id/delete  UserLive.Index :delete  # router.ex:271, :settings live_session
  events:
    - UserLive.Index#cancel_deletion                   # user_live/index.ex:34-52
    - UserLive.TableComponent#sort                     # table_component.ex:46-62
    - UserLive.TableComponent#filter                   # table_component.ex:64-73
    - UserLive.TableComponent#clear_filter             # table_component.ex:75-84
    - Components.UserDeletionModal#validate            # owned by shared-user-deletion-modal
    - Components.UserDeletionModal#delete              # owned by shared-user-deletion-modal
    - Components.UserDeletionModal#close_modal         # owned by shared-user-deletion-modal
  js_hooks:
    - ModalHook                                        # via the deletion modal; owned by shared-user-deletion-modal
    - Common.simple_dropdown show_dropdown / hide_dropdown JS commands (common.ex:677-709)
    - TableHelpers.filter_input phx-keyup with phx-debounce 300 (table_helpers.ex:33-43)
  policies:
    - Lightning.Policies.Users :access_admin_space (policies/users.ex:19-21), through LightningWeb.Hooks :ensure_admin (hooks.ex:31-53)
  workers: []                                          # cancelling keeps the account out of oban:accounts-purge-deleted, owned by flow-account-revocation-teardown
  api_endpoints: []
  emails: []                                           # scheduling sends email:account-deletion-scheduled via shared-user-deletion-modal S04 and flow-account-revocation-teardown S07; cancelling sends none
  config:
    - :lightning, Lightning.Extensions.Routing         # config/config.exs:50-61; router.ex:341-355
  not_reachable_here:
    - UserDeletionModal logout true clause and is_current_user true copy (user_deletion_modal.ex:89-93, :17, :120, :171); owned by profile-delete-account
    - BookDemoBanner and the GDPR banner from shared-authenticated-session (S08 to S10); the settings layout renders neither (layouts/settings.html.heex:1-107; page has no :banner slot, index.html.heex:1-24)
    - shared-project-header breadcrumbs, picker button and project side menu (S01 to S03, S05, S07, S09, S15 to S17); this page has no project and uses the settings layout
    - UserLive.Components users_table attr defaults for target, user_deletion_modal and delete_user (user_live/components.ex:9, :12-15, :43); always passed by TableComponent (table_component.ex:14-24) (6.3)

related:
  - admin-user-edit                   # "New User" and "Edit" land there (S08); email, role, disable and password changes happen there
  - profile-delete-account            # the other host of the deletion modal
  - lib/lightning_web/live/user_live/index.ex
  - lib/lightning_web/live/user_live/index.html.heex
  - lib/lightning_web/live/user_live/table_component.ex
  - lib/lightning_web/live/user_live/components.ex
  - lib/lightning_web/live/helpers/table_helpers.ex
  - lib/lightning/accounts.ex         # list_users/0 (:290-292), get_user!/1 (:372), cancel_scheduled_deletion/1 (:667-675)
  - lib/lightning/accounts/user.ex    # details_changeset/2 (:287-305)
  - test/lightning_web/live/user_live_test.exs        # :33-41, :43-118, :301-574, :576-724, :726-748
  - test/lightning_web/live/confirmation_lockout_live_test.exs   # :21-72
  - test/lightning_web/live/hooks_test.exs            # :38-70
flows:
  - flow-account-revocation-teardown  # deletion from this list is one of its entries (its S01 row 5, S07); cancelling is owned here (its not_reachable_here)
  - flow-change-email-confirm         # cross-reference only: superusers change a user's email without confirmation on admin-user-edit, reached from this list (S08); admin-users is in that flow's related list, not its surfaces
---

## 1. Purpose

Superusers, the people who run a Lightning instance, use this page to see every account on it and
to remove or rescue them: who is a superuser, who is disabled, who has support access and who is
due to be deleted. It is where an administrator goes when someone leaves an organisation or asks
for their account back. Without it, cutting off a departed user or reversing a mistaken deletion
would need direct database access, and a superuser could not tell at a glance who holds
instance-wide access.

## 2. What it does

- Superusers see every account with its name, email, role, enabled state, support flag and scheduled deletion date
- Superusers filter the list by name, email or role
- Superusers sort the list by any column and reverse the order
- Superusers open the deletion dialog for a non-superuser account
- Superusers cancel a scheduled deletion, which re-enables the account
- Superuser accounts are never offered an active delete action
- Superusers go from the list to create a user or edit one

## 3. Who can do what

Sources: `policies/users.ex:19-21`; `hooks.ex:31-53`; `user_live/components.ex:172-204`;
`user_live/index.ex:34-52`.

| Action | Signed out | Signed-in non-superuser | Superuser |
|--------|-----------|-------------------------|-----------|
| See the users list | no (login) | no (redirect to /projects) | yes |
| Filter and sort | n/a | n/a | yes |
| Open the deletion dialog for a `user` account | no | no | yes |
| Open the deletion dialog for a `superuser` account from the list | no | no | no (the action is inert) |
| Open the deletion dialog for a `superuser` by typing its URL | no | no | yes (scheduling is then refused, shared-user-deletion-modal S03) |
| Cancel a scheduled deletion | no | no | yes, any role |
| Delete now (account already scheduled) | no | no | yes, `user` accounts only from the list |
| Go to "New User" or "Edit" | no | no | yes |

**Preconditions beyond role**
- The superuser check runs once, at mount (`user_live/index.ex:7`); `cancel_deletion`, `sort` and `filter` check nothing themselves (`user_live/index.ex:34-52`; `table_component.ex:46-84`). A superuser demoted while the page is open loses it through the revocation broadcast (flow-account-revocation-teardown S01 row 3), not here.
- "Delete" for a never-scheduled account and "Delete now" for a scheduled one are both chosen from the row as loaded, by `role` and `scheduled_deletion` (`user_live/components.ex:172-204`).
- A superuser's own row is a superuser row, so nobody can open the dialog on themselves from the list.

## 4. What it touches

**Reads**: `users`, every row, with `Repo.all` on page mount and again on every filter keystroke, sort click and clear (`table_component.ex:30-38`, `:86-97`; `accounts.ex:290-292`); one `users` row by id on the delete route (`user_live/index.ex:28-32`; `accounts.ex:372`) and on cancel (`accounts.ex:667-669`). Inherited reads belong to the shared files.

**Writes**: `users.scheduled_deletion = nil` and `users.disabled = false` on cancel, through `User.details_changeset/2` and a plain `Repo.update` (`accounts.ex:667-675`; `user.ex:287-305`). Deletion writes belong to shared-user-deletion-modal.

**Immediate side effects** (in the same request)
- Cancel: flash "User deletion canceled" and `push_navigate` to `/settings/users`, or flash "Cancel user deletion failed" in place (`user_live/index.ex:40-51`)
- Cancel writes no audit event, sends no email and broadcasts nothing (`accounts.ex:667-675`); see 6.2
- Opening the deletion dialog and what it does: shared-user-deletion-modal

**Deferred side effects** (later, elsewhere)
- A cancelled account is no longer picked up by the nightly purge sweep, which selects on `scheduled_deletion <= now` (`accounts.ex:103-130`); the purge belongs to flow-account-revocation-teardown. See 6.1 for the job already in the queue.

**External, non-transactional effects**
- none

**Depends on config**
- `Lightning.Extensions.Routing` must list `/settings/users` for the index route to exist (`config/config.exs:50-61`; `router.ex:341-355`)

**Product limits**
- none

## 5. Scenarios

Verified by reading code and tests under `default`. Nothing was run.

```gherkin
Feature: Admin users list
  In order to know who has access to this instance and to remove or rescue accounts
  As a superuser
  I want a list of every account with its status and the actions that change it

  @S01 @pending
  Scenario: A superuser sees every account on the instance
    # Value: instance administrators can see who holds an account, who is a superuser, who is disabled and who is about to be removed, in one place.
    Given I am a superuser
    And "amara@example.org" is a user with first name "Amara", support access and a disabled account
    And "bob@example.org" is a superuser
    When I visit "/settings/users"
    Then I see the heading "Users"
    And I see the columns "First name", "Last name", "Email", "Role*", "Enabled?", "Support?", "Scheduled Deletion" and "Actions"
    And the row for "amara@example.org" shows role "user", a support tick and no enabled tick
    And the row for "bob@example.org" shows role "superuser" and an enabled tick
    And I see the note that a superuser can access everything in a Lightning installation
    # user_live/index.ex:13, :22-26; index.html.heex:3-4; user_live/components.ex:35-165; table_component.ex:30-38; accounts.ex:290-292
    # user_live_test.exs:36-41 (heading and own email only); confirmation_lockout_live_test.exs:70-71 (another user's email)
    # The superuser gate itself: proposed shared-admin-space

  @S02 @pending
  Scenario: Filtering narrows the list by name, email or role
    # Value: on an instance with many accounts, an administrator finds the one they need without scrolling.
    Given I am a superuser
    And "alice@example.org" is a user named "Alice Smith"
    And "bob@example.org" is a superuser named "Bob Johnson"
    When I visit "/settings/users"
    Then the clear filter button is hidden
    When I type "alice" in "Filter users..."
    Then I see "alice@example.org"
    And I do not see "bob@example.org"
    And I see the clear filter button
    When I type "superuser" in "Filter users..."
    Then I see "bob@example.org"
    And I do not see "alice@example.org"
    When I click the clear filter button
    Then I see "alice@example.org" and "bob@example.org"
    # table_component.ex:64-84, :86-97, :114-116; table_helpers.ex:26-58, :130-141
    # user_live_test.exs:662-707, :709-723

  @S03 @pending
  Scenario: The list is sorted by email and any column can be sorted
    # Value: an administrator can bring disabled accounts, superusers or pending deletions together to review them.
    Given I am a superuser
    And users "alpha@example.org", "beta@example.org" and "charlie@example.org" exist
    And "disabled@example.org" is disabled
    When I visit "/settings/users"
    Then the rows are in ascending email order
    When I click the "Email" header
    Then the rows are in descending email order
    When I click the "Enabled?" header
    Then "disabled@example.org" is listed before the enabled accounts
    When I click the "Role*" header
    Then superusers are listed before users
    # table_component.ex:30-38, :46-62, :100-112; table_helpers.ex:110-118, :152-164, :213-228
    # user_live_test.exs:576-603 (email both ways), :605-621 (first name), :623-638 (role), :640-660 (enabled)
    # Ordering details (case, blanks, unscheduled rows) are 6.2

  @S04 @pending
  Scenario Outline: Superuser accounts are never offered an active delete action
    # Value: an instance can't lose an administrator, including the one using the page, through a click on the users list.
    Given I am a superuser
    And "root@example.org" is a superuser <state>
    When I open the "Actions" menu for "root@example.org"
    Then I see <label> as plain text, not a link
    And I see "Cancel deletion" only when "root@example.org" is scheduled for deletion
    # user_live/components.ex:172-187
    # user_live_test.exs:349-367 (own row, Delete), :413-429 (Cancel deletion kept), :510-536 (Delete now inert)
    # The scheduled superuser state is built directly in the tests; the app's own paths keep it from arising (shared-user-deletion-modal 6.1 row 3)
    Examples:
      | state                         | label        |
      | not scheduled for deletion    | "Delete"     |
      | scheduled for deletion        | "Delete now" |

  @S05 @pending
  Scenario: Delete on a user account opens the deletion dialog over the list
    # Value: an administrator can begin removing a departed user's access from the row where they found them.
    Given I am a superuser
    And "amara@example.org" is a user not scheduled for deletion
    When I open the "Actions" menu for "amara@example.org"
    And I click "Delete"
    Then I am on "/settings/users/<amara id>/delete"
    And the users list is still shown behind the dialog
    And shared-user-deletion-modal is open for "amara@example.org" with return to "/settings/users"
    # user_live/components.ex:17-27, :148-151, :189-203; user_live/index.ex:28-32; index.html.heex:16-22; router.ex:271
    # user_live_test.exs:315-319; scheduling, cancel and close are shared-user-deletion-modal S02, S04, S09; the revocation is flow-account-revocation-teardown S01, S07

  @S06 @pending
  Scenario: A scheduled account shows when it will go and offers to cancel or delete now
    # Value: an administrator can see who is about to lose their account, and when, before it happens.
    Given I am a superuser
    And "amara@example.org" is a user scheduled for deletion on 21 Oct at 09:30 UTC
    When I visit "/settings/users"
    Then the row for "amara@example.org" shows "21 Oct  09:30" under "Scheduled Deletion"
    And its "Actions" menu offers "Cancel deletion" and "Delete now" links
    When I click "Delete now"
    Then I am on "/settings/users/<amara id>/delete"
    And shared-user-deletion-modal shows its delete-now branch
    # user_live/components.ex:131-134, :189-196, :206-217
    # user_live_test.exs:301-347 (date shown after scheduling, "%d %b" only), :431-458, :538-574; delete now itself is shared-user-deletion-modal S06 to S08

  @S07 @pending
  Scenario: Cancelling a scheduled deletion restores the account
    # Value: a deletion made by mistake, or one the user regrets, can be reversed before the purge removes the account and its credentials.
    Given I am a superuser
    And "amara@example.org" is a user scheduled for deletion and disabled
    When I open the "Actions" menu for "amara@example.org"
    And I click "Cancel deletion"
    Then I am on "/settings/users"
    And I see "User deletion canceled"
    And the row for "amara@example.org" shows no scheduled deletion date and an enabled tick
    And "amara@example.org" can sign in again with her password
    # user_live/index.ex:34-46; accounts.ex:667-675; user_live/components.ex:206-217
    # user_live_test.exs:396-411 asserts only the flash and the redirect; the database state and sign-in are untested
    # Her API tokens and sessions stay revoked (flow-account-revocation-teardown 6.2); see 6.1 rows 1 and 2 and 6.2 here

  @S08 @pending
  Scenario Outline: The list leads to the user form
    # Value: an administrator can add an account on an instance without self sign-up, or change a user's details, role or access, starting from the list.
    Given I am a superuser
    And "amara@example.org" is a user
    When I visit "/settings/users"
    And I <action>
    Then I am on "<path>"
    # index.html.heex:5-12; user_live/components.ex:145-147
    # user_live_test.exs:43-56 (New User), :109-118 (Edit); what the form does is admin-user-edit
    # An email changed there takes effect without confirmation, unlike flow-change-email-confirm
    Examples:
      | action                                                  | path                              |
      | click "New User"                                        | /settings/users/new               |
      | open the "Actions" menu for "amara@example.org" and click "Edit" | /settings/users/<amara id> |
```

## 6. Unclear value

### 6.1 Possible bugs

| What | Where | What a user sees | Disposition |
|------|-------|------------------|-------------|
| Cancelling does not stop a purge job the nightly sweep already queued: `perform/1` for one user checks only that the row exists, not that it is still scheduled | `accounts.ex:94-101`, `:103-135`; `user_live/index.ex:40` | "User deletion canceled", then the account and its credentials are purged anyway if the cancel lands between the sweep and the job | fix |
| Cancel re-enables the account unconditionally; whether it was disabled for another reason before deletion was scheduled is not kept anywhere | `accounts.ex:667-674`; scheduling sets `disabled` itself (`accounts.ex:948-968`) | an account an administrator had disabled on purpose comes back enabled | decide |
| Cancel looks the user up with `get_user!`; if the account was purged since the list loaded (another superuser's "Delete now", or the nightly purge) the LiveView crashes | `user_live/index.ex:40`; `accounts.ex:667-669`; stale list `table_component.ex:30-38` | the page reloads instead of showing "Cancel user deletion failed" | fix |
| The "Actions" dropdown button always says `aria-expanded="true"`, open or closed | `common.ex:681-687` (shared Common component) | screen readers announce every row's menu as expanded | fix |

### 6.2 Quirks and implementation details

| What | Where | Disposition |
|------|-------|-------------|
| The list is loaded once when the table component mounts and never refreshed; other superusers' edits, deletions and the nightly purge show only after navigation | `table_component.ex:30-43`; no PubSub in `user_live/index.ex` | decide |
| `/settings/users` is in the `:services` live_session and `/settings/users/:id/delete` in `:settings`; "Delete", "Delete now" and closing the dialog each cross sessions and do a full page load | `router.ex:268-271`, `:351-355`; `config/config.exs:51`, `:60` | decide |
| Filter and sort live only in component assigns: not in the URL, lost on reload, on opening the dialog and on the navigation after cancel | `table_component.ex:30-38`; `user_live/index.ex:45` | decide |
| Sorting compares raw strings, so it is case-sensitive ("alice" sorts after "Zoe") | `table_helpers.ex:152-164`, `:228` | decide |
| Blank first or last names sort before every name in ascending order | `table_helpers.ex:220` | preserve |
| Sorting "Scheduled Deletion" ascending puts unscheduled accounts last by mapping them to 9999-12-31 | `table_component.ex:108-110` | preserve |
| Sorting "Enabled?" ascending puts disabled accounts first (false before true); the test asserts this | `table_component.ex:106`; `user_live_test.exs:640-660` | preserve |
| The role filter is a substring match, so "user" matches superusers too | `table_component.ex:114-116`; `table_helpers.ex:132-141` | decide |
| The scheduled date is `Calendar.strftime("%d %b  %H:%M")`: UTC without saying so, no year, two spaces, and not `Common.datetime`, so it does not inherit shared-local-datetime | `user_live/components.ex:131-134` | decide |
| Role is shown as the raw enum, lowercase "user" or "superuser"; the header "Role*" points to the footnote | `user_live/components.ex:72`, `:116`, `:160-165` | decide |
| The inert "Delete" and "Delete now" for superusers are plain spans with `cursor-not-allowed` and no explanation | `user_live/components.ex:172-187` | decide |
| "Cancel user deletion failed" drops the changeset errors, so the reason is never shown | `user_live/index.ex:47-50` | decide |
| Cancel goes through `details_changeset` but straight to `Repo.update`, not `update_user/3`, so unlike other admin edits it writes no audit event (also flow-account-revocation-teardown 6.2) | `accounts.ex:667-675` vs `:177-228` | decide |
| An unknown or malformed id on `/settings/users/:id/delete` raises in `get_user!` rather than showing the "No Access" or "Not Found" panel | `user_live/index.ex:28-32`; `accounts.ex:372` | decide |
| Labels are title case ("New User", "Scheduled Deletion") against sentence case elsewhere | `index.html.heex:11`; `user_live/components.ex:99` | decide |
| The page title is "Users" on both routes; the dialog does not change it | `user_live/index.ex:22-32` | preserve |
| The index route is injected from config while its own delete route, the menu link and `push_navigate` targets are hard-coded | `config/config.exs:60`; `router.ex:271`; `layouts/settings.html.heex:48-54`; `user_live/index.ex:45` | decide |
| "Cancel deletion" is an `<a href="#">` with `phx-click`, handled by the parent LiveView rather than the table component | `user_live/components.ex:206-217`; `user_live/index.ex:34-52` | preserve |

### 6.3 Unreachable or dead code

| What | Where | Why unreachable |
|------|-------|-----------------|
| `users_table` default `target: nil` and the `else: []` branch on each sortable header | `user_live/components.ex:9`, `:43`, `:52`, `:61`, `:70`, `:79`, `:88`, `:97` | the only caller always passes `target={@myself}` (`table_component.ex:14-17`) |
| `users_table` defaults for `user_deletion_modal` and `delete_user` | `user_live/components.ex:12-15` | always passed (`table_component.ex:18-24`; `index.html.heex:16-22`) |
| shared-authenticated-session S08 to S10 (book-a-demo and GDPR banners) | `layouts/settings.html.heex:1-107`; `index.html.heex:1-24` | the settings layout renders neither and the page has no `:banner` slot |

### 6.4 Performance and operational limits

| What | Where | User-visible? | Disposition |
|------|-------|---------------|-------------|
| Every user row is loaded with `Repo.all`, then filtered and sorted in memory; no pagination | `accounts.ex:290-292`; `table_component.ex:86-97` | yes, on large instances the page grows without limit | decide |
| The full user table is re-queried on every filter keystroke, sort click and clear | `table_component.ex:46-97` | no | decide |
| Filter input debounced 300 ms on keyup | `table_helpers.ex:39-40` | no | preserve |

### 6.5 Things seen but not understood

- Cancel validates names through `details_changeset` (`user.ex:287-305`, `:102-110`). An account whose stored first or last name is blank or fails `validate_name` (for example one created outside the registration form) may be impossible to cancel, with only "Cancel user deletion failed". Not traced to a real source of such rows. Disposition: decide.
- Whether a deployment is meant to replace this page through `Lightning.Extensions.Routing` (variant `routing-without-users-index`). If it omits the route, the side menu link and the delete route's `push_navigate` targets still point at `/settings/users` (`router.ex:341-355`). Disposition: decide.
- No test asserts the database after "Cancel deletion" (S07), the date and time format (S06 checks only "%d %b"), or the superuser footnote (S01). Disposition: preserve (write the tests).

## 7. Not migrating

| Item | Reason | Decided by | Date |
|------|--------|------------|------|

## 8. Open questions

- Should the per-user purge job re-check `scheduled_deletion` so a cancel always wins (6.1)? (owner: security)
- Should cancelling restore the account's earlier disabled state instead of always enabling it, and should it be audited like other admin edits (6.1, 6.2)? (owner: product)
- Should the list refresh live, paginate, and keep filter and sort in the URL (6.2, 6.4)? (owner: product)
- Should scheduled dates show the year and the viewer's local time, as `Common.datetime` does elsewhere (6.2)? (owner: product)
- Should the inert delete actions on superuser rows explain why (6.2)? (owner: product)
- Is the config-injected index route a supported extension point (6.5)? (owner: engineering)

## Proposed flows

none. Referenced:
- `flow-account-revocation-teardown`: S05 and S06 hand off to shared-user-deletion-modal, whose scheduling starts this flow (its S01 row 5, S07); admin-users is already in its surfaces. Cancelling is owned here (S07).
- `flow-change-email-confirm`: cross-reference only. Superusers change a user's email without that confirmation on admin-user-edit, which S08 leads to. admin-users is in the flow's `related`, not its `surfaces`.

## Proposed shared

- `shared-admin-space` (new): the superuser gate, settings layout and admin side menu shared by admin-users, admin-user-edit, admin-projects, admin-audit, admin-maintenance, admin-auth-providers and admin-collections. Gate: `on_mount {LightningWeb.Hooks, :ensure_admin}` on each module (`user_live/index.ex:7`, `user_live/edit.ex:8`, `project_live/index.ex:7`, `audit_live/index.ex:7`, `auth_providers/index.ex:7`, `collection_live/index.ex:4`); no current user halts to `/users/log_in` (`hooks.ex:31-38`); a user failing `Users :access_admin_space` (role `:superuser` only, `policies/users.ex:19-21`) halts with flash `:nav :no_access` and a redirect to `/projects` (`hooks.ex:40-53`), which renders "No Access" / "Sorry, you don't have access to that." (`live_helpers.ex:89-95`). Tests: `hooks_test.exs:38-70`, `user_live_test.exs:726-748`, `user_permissions_test.exs:62`, `:82`. The halt also stops per-event handlers on a non-admin socket (comment `hooks.ex:28-30`). Exceptions to check: admin-maintenance does its own check in `mount` and `handle_event` with `push_navigate` instead of the hook (`maintenance_live/index.ex:14-28`, `:31-33`); LiveDashboard `/dashboard` adds the `:require_superuser` plug and the hook but is not on the settings layout (`router.ex:358-369`). Layout: `{LightningWeb.Layouts, :settings}` set in each mount (`user_live/index.ex:14` and peers); side menu items Projects, Users, Authentication, Audit, Collections, Maintenance, a config extension slot (`settings_menu_items_extension`, `layout_components.ex:188-203`), Back to `/projects`, the experimental mode item and sidebar footer, with the current item from `active_menu_item` (`layouts/settings.html.heex:31-96`); account menu and global project picker as in shared-project-header S18 and S04, S06, S08, S10 to S12 (`layouts/settings.html.heex:29`, `:104-106`); no GDPR or book-a-demo banner. The routes split across live_sessions: `/settings/users` in `:services` via config, the rest in `:settings` (`router.ex:268-285`, `:351-355`). Surfaces: the seven admin views above.

## Summary

- Scenarios: 8 (S01 to S08), all `@pending`.
- Section 6: 6.1 has 4, 6.2 has 18, 6.3 has 3, 6.4 has 3, 6.5 has 3.
- Flows: none proposed; references flow-account-revocation-teardown and flow-change-email-confirm (cross-reference).
- Shared: proposes shared-admin-space; references shared-user-deletion-modal, shared-authenticated-session and shared-project-header.
- Unsure: the queued-purge race (6.1 row 1) is read from code, not run; admin-users is not in flow-change-email-confirm's surfaces, so the flow lint may flag it; whether the confirmation banner, Ctrl+P picker and account menu behave on the settings layout exactly as shared-project-header describes for the live layout.

## Lead resolution (batch 9)

- `shared-admin-space` created from this file's Proposed shared entry; the other admin views inherit it. admin-users added to flow-change-email-confirm surfaces as a cross-reference.
