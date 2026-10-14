---
id: shared-flash-messages
type: shared
title: Flash messages
status: not-started
owner:

trigger:
  old_route: every page that renders a flash, through its layout or its own template
  new_route:
  old_route_disposition: unchanged
  reachable_when:
    - the page renders in the `:live` layout (`lib/lightning_web/components/layouts/live.html.heex:92-96`), the default for every LiveView (`lib/lightning_web.ex:69-73`)
    - or in the `:settings` layout (`lib/lightning_web/components/layouts/settings.html.heex:99-100`), used by the admin LiveViews
    - or the template renders the flash itself: `UserConfirmationRequiredLive` (`user_confirmation_required_live.html.heex:1-2`) and the auth controller templates (`controllers/user_session_html/new.html.heex:18-27` and the same block in registration, reset password and confirmation templates)

inherits: []

url_params: []

config_variants:
  default: {}                     # read under this one; nothing here depends on config

inventory:
  routes: []
  events:
    - lv:clear-flash              # LiveView built-in, pushed by Common.flash and the settings-layout blocks
  js_hooks:
    - Flash                       # assets/js/hooks/index.ts:532-549, registered via app.js:34, :55-57
  policies: []
  workers: []
  api_endpoints: []
  emails: []
  config: []
  not_reachable_here:
    - Common.flash dynamic_component branch (common.ex:541-543, :583-585); see 6.3
    - Common.flash with phx-target on a live component (credential_index_component.html.heex:279-280); owned by shared-credential-index-component
    - live_info_block / live_error_block with myself (auth_providers/form_component.ex:295-296); owned by admin-auth-providers

related:
  # :live layout (Common.flash, auto-hide, :nav card)
  - projects-dashboard
  - first-setup
  - mfa-required
  - profile-account
  - profile-backup-codes
  - profile-delete-account
  - profile-experimental-features
  - profile-github
  - profile-mfa
  - profile-tokens
  - credentials-index
  - channels-index
  - channel-request-show
  - dataclip-show
  - history-work-orders
  - history-channel-logs
  - run-show
  - sandboxes-index
  - workflows-index
  - workflow-health
  - workflow-editor-canvas
  - workflow-editor-new
  - project-settings-setup
  - project-settings-collaborators
  - project-settings-security
  - project-settings-credentials
  - project-settings-webhook-security
  - project-settings-collections
  - project-settings-data-storage
  - project-settings-github-sync
  - project-settings-history-exports
  # :settings layout (sticky toasts, no :nav card)
  - admin-users
  - admin-user-edit
  - admin-projects
  - admin-audit
  - admin-maintenance
  - admin-auth-providers
  - admin-collections
  # own Common.flash in the :app layout
  - auth-confirmation-required
  # controller templates (inline alert)
  - auth-login
  - auth-register
  - auth-reset-password
  - auth-confirm-account
  # no flash rendered at all (see 6.1)
  - auth-confirm-access
  - auth-two-factor
  # source files
  - lib/lightning_web/live/components/common.ex
  - lib/lightning_web/live/live_helpers.ex
  - assets/js/hooks/index.ts
flows:
  - flow-credential-transfer      # ends on /projects with an info, error or :nav flash (credential_transfer_controller.ex:9-23)
  - flow-log-out                  # "Logged out successfully." shown on the login page (user_session_controller.ex:69-73)
---

## 1. Purpose

Every page needs one consistent way to tell someone what just happened: that a save worked, that
something failed, or that the place they tried to reach is not there for them. Without it, people
repeat actions they think did not happen, miss failures, or land on a blank page after following a
bad link. The rendering differs by layout, and this file records each variant so views can inherit
it.

## 2. What it does

- Pages in the live layout show info and error flashes as a toast at the bottom of the screen
- Live-layout toasts hide themselves after about 5 seconds; pointing at one restarts the timer
- Anyone can dismiss a toast by clicking it
- A flash set before a redirect or live navigation shows on the page the user lands on
- A `:nav` flash replaces the page content with a "Not Found" or "No Access" card, with or without a Back button
- Admin pages (settings layout) show toasts that stay until clicked, and never show the `:nav` card
- Sign-in and account forms served by controllers show the flash inline at the top of the form

## 3. Who can do what

| Action | Signed out | Any signed-in user | Superuser |
|--------|------------|--------------------|-----------|
| See a flash on a page they can open | yes | yes | yes |
| Dismiss a toast | n/a (controller pages have no dismiss) | yes | yes |

No policy is involved; a flash is shown to whoever holds the session or socket it was put on.

**Preconditions beyond role**
- Auto-hide and click-to-dismiss need a connected LiveView socket; the hook only runs after connect (`index.ts:532-549`).
- The `:nav` card renders only in the live layout (`live.html.heex:94-96`); every caller redirects to `/projects`, which is in that layout (`hooks.ex:50`, `:124`, `:130`; `maintenance_live/index.ex:26`; `user_auth.ex:433`, `:514`; `credential_transfer_controller.ex:17`).

## 4. What it touches

**Reads**: none (flash lives in the session cookie across redirects and in socket assigns on a live page; `router.ex:22-23` `fetch_session`, `fetch_live_flash`)

**Writes**: none

**Immediate side effects**
- Dismiss and auto-hide push `lv:clear-flash` to the LiveView, which removes the key from socket assigns (`common.ex:530-534`, `:571-575`; `live_helpers.ex:34-36`, `:62-64`; `index.ts:533-537`)

**Deferred side effects**
- none

**External, non-transactional effects**
- none

**Depends on config**
- none

**Product limits**
- Live-layout toasts auto-hide 5 seconds after they mount or after the last mouseover (`index.ts:539-544`).

## 5. Scenarios

```gherkin
Feature: Flash messages
  In order to know whether what I just did worked
  As anyone using Lightning
  I want short, consistent messages after my actions and when a page is not available to me

  @S01 @pending
  Scenario: An info flash appears as a toast and hides itself
    # Value: people get confirmation that an action worked without having to clear it themselves.
    Given I am on a page in the live layout
    When an action on the page puts the info flash "Project user updated successfuly"
    Then I see a blue toast with a check icon reading "Project user updated successfuly"
    And after about 5 seconds the toast is gone
    # common.ex:558-592 (info branch, check-circle icon); live.html.heex:92; index.ts:532-539

  @S02 @pending
  Scenario: An error flash is styled as an error
    # Value: people can tell at a glance that something failed rather than succeeded.
    Given I am on a page in the live layout
    When an action on the page puts the error flash "Runs limit exceeded"
    Then I see a red toast with an exclamation icon reading "Runs limit exceeded"
    And the toast is marked as an alert
    # common.ex:517-555 (error branch, exclamation-circle icon, role="alert"); live.html.heex:93
    # work_order_live_test.exs:1950 (asserts [data-flash-kind='error'] with the text)

  @S03 @pending
  Scenario: Pointing at a toast keeps it on screen
    # Value: someone still reading a message does not lose it mid-sentence.
    Given I see an info toast
    When I move the pointer over it 4 seconds after it appeared
    Then it is still visible 4 seconds later
    # index.ts:540-544 (mouseover clears and restarts the 5 second timer)

  @S04 @pending
  Scenario: Clicking a toast dismisses it
    # Value: a toast covering the bottom of the page can be cleared at once, and it does not come back on the next render.
    Given I see an info toast
    When I click it
    Then the toast is gone
    And it does not reappear when the page next updates
    # common.ex:571-575 (JS.push "lv:clear-flash" with phx-value-key="info", :576); project_live_test.exs:2069-2071

  @S05 @pending
  Scenario: A flash carried in by a redirect shows on the page I land on
    # Value: the outcome of an action that moves me to another page (a deletion, a transfer, a refusal) is still reported.
    Given an action put the info flash "Credential transfer confirmed successfully." and redirected me to "/projects"
    When "/projects" renders
    Then I see an info toast reading "Credential transfer confirmed successfully."
    # router.ex:22-23 (fetch_live_flash); live.html.heex:92-93; handoff from flow-credential-transfer (credential_transfer_controller.ex:9-13)

  @S06 @pending
  Scenario: A Not Found or No Access flash replaces the page with a card
    # Value: someone who followed a link they can't use is told so plainly instead of seeing an empty or unrelated page, and can step back.
    Given I was redirected to "/projects" with the nav flash "not found"
    Then the main area shows "Not Found" and "Sorry, we can't find anything here for you."
    And the list of my projects is not shown
    And the side menu is still shown
    When I click "Back"
    Then the browser goes back one page
    # live_helpers.ex:78-152 (:not_found heading and blurb :81-86, inner content only when no :nav :148-150, history.back() :137);
    # live.html.heex:94-96 (card wraps @inner_content only; sidebar is outside)
    # "No Access" with and without Back is covered by shared-admin-space S02 and S04; the non-member case by shared-project-scope S03

  @S07 @pending
  Scenario: Admin pages show a toast that stays until clicked
    # Value: an admin can clear a confirmation that sits over the bottom of a table.
    Given I am a superuser on "/settings/projects"
    When I cancel a scheduled project deletion
    Then I see the toast "Project deletion canceled"
    When I click the toast
    Then it is gone
    # settings.html.heex:99-100; live_helpers.ex:18-44 (phx-click lv:clear-flash, phx-value-key info :34-36); project_live/index.ex:105

  @S08 @pending
  Scenario: Sign-in and account forms show the flash inside the form
    # Value: someone retrying a password still sees why the last attempt failed, next to the fields they are retyping.
    Given I am on "/users/log_in"
    When I sign in with a wrong password
    Then I see "Invalid email or password" at the top of the form card
    And it stays there until the page is reloaded or submitted again
    # user_session_controller.ex:22-25 (render, not redirect); user_session_html/new.html.heex:18-27;
    # same block in user_registration_html/new.html.heex:18-27, user_reset_password_html/new.html.heex:18-27, edit.html.heex:17-26, user_confirmation_html/new.html.heex:18-27, edit.html.heex:18-27
    # user_session_controller_test.exs:274
```

## 6. Unclear value

### 6.1 Possible bugs

| What | Where | What a user sees | Disposition |
|------|-------|------------------|-------------|
| `Common.flash` passes the bare id ("flash-1A2B3C", no `#`) as the `to:` selector of `JS.hide` and the error branch's `JS.remove_class`, so they match no element; the fade-out never runs and the `phx:hide-start` listener that cancels the timer never fires | `common.ex:521`, `:532-533`, `:574`, `:600-608`; `index.ts:540` | the toast vanishes abruptly once the server re-renders; with the socket disconnected, clicking or the timer does nothing | fix |
| The error toast pushes `lv:clear-flash` with no `phx-value-key` (the info toast sets `"info"`), so LiveView clears every flash key | `common.ex:530-534` vs `:576`; behaviour of `lv:clear-flash` without a key read from Phoenix LiveView 1.0.19, not vendored here | dismissing an error also removes an info toast shown at the same time, and a `:nav` card if one is up | fix |
| Pages in the `:app` layout that don't render the flash themselves drop it: the re-auth page never shows "You must verify yourself again in order to access this page." | `layouts/app.html.heex:1-5`; `re_authenticate_live/new.ex:16`; `user_auth.ex:401-407`, `:450-454` (also auth-confirm-access 6.1) | arrives on "Confirm access" with no explanation | fix |
| Back on the `:nav` card is `javascript:history.back()` | `live_helpers.ex:137` | in a fresh tab (link opened from an email or chat) Back does nothing | decide |

### 6.2 Quirks and implementation details

| What | Where | Disposition |
|------|-------|-------------|
| Error toasts auto-hide after 5 seconds like info toasts, including failure messages carried in from another page | `common.ex:535`; `index.ts:539` | decide |
| The settings layout uses `live_info_block`/`live_error_block`: no Flash hook, so toasts never auto-hide, and no icon or close button; it has no `live_nav_block` (also shared-admin-space 6.2) | `settings.html.heex:99-100`; `live_helpers.ex:18-73` | decide |
| Controller form flashes use the phx.new `.alert` classes, are not dismissable and don't auto-hide | `user_session_html/new.html.heex:18-27`; `assets/css/app.css:746-775` | preserve |
| Each render of `Common.flash` and the settings blocks generates a new random id, so any change to the flash map (for example clearing info) gives the other toast a new DOM id, remounting the hook and restarting its timer | `common.ex:520-522`, `:561-563`; `live_helpers.ex:24`, `:52` | decide |
| The close "x" in `Common.flash` has no handler of its own; the whole toast is the click target | `common.ex:547-552`, `:588-594` | preserve |
| With a `:nav` flash set, the underlying LiveView still mounts and loads its data; only its markup is hidden | `live_helpers.ex:148-150`; `dashboard_live/index.ex:8-13` | preserve |
| Info and error toasts render outside the `:nav` card, so both can show at once | `live.html.heex:92-96` | preserve |
| The `:nav` card's heading carries `id="modal-title"` though it is not a modal | `live_helpers.ex:119-122` | decide |
| `UserConfirmationRequiredLive` renders `Common.flash` in the `:app` layout itself, the only page outside the live layout with auto-hiding toasts | `user_confirmation_required_live.html.heex:1-2`; `user_confirmation_required_live.ex:36` | preserve |

### 6.3 Unreachable or dead code

| What | Where | Why unreachable |
|------|-------|-----------------|
| `Common.flash` renders a function component when the flash value is `%{function:, args:}` | `common.ex:541-543`, `:583-585`; `live/components/dynamic.ex:10-11` | nothing in this repo puts a map flash; the similar-looking `:banner` assign in `init_assigns.ex:46-52` is not a flash |

### 6.4 Performance and operational limits

| What | Where | User-visible? | Disposition |
|------|-------|---------------|-------------|
| Auto-hide delay 5000 ms, restarted on every mouseover | `index.ts:539`, `:543` | yes (S01, S03) | preserve |
| Hide transition 300 ms (never runs, see 6.1) | `common.ex:600-608` | no | fix |

### 6.5 Things seen but not understood

- `click_close_error_flash/1` refutes `div[phx-click='lv:clear-flash'][phx-value-key='error']`, markup only the settings-layout block has; on live-layout pages the refute passes whether or not the toast closed (`test/support/workflow_live_helpers.ex:92-98`).
- The E2E page object finds toasts by `[id^="flash-"][phx-hook="Flash"]`, so settings-layout toasts are invisible to `expectFlashMessage` (`assets/test/e2e/pages/base/liveview.page.ts:11`, `:41-45`).

## 7. Not migrating

| Item | Reason | Decided by | Date |
|------|--------|------------|------|

## 8. Open questions

- Should error toasts stay until dismissed rather than auto-hide (6.2 row 1)? (owner: product)
- Should admin pages use the same toast and `:nav` card as the rest of the app (6.2 row 2)? (owner: product)
- Should every page, including the `:app` layout pages, render flashes, so redirect reasons are never dropped (6.1 row 3)? (owner: product)
- What should Back do on the `:nav` card when there is no history (6.1 row 4)? (owner: product)

---

**Proposed flows**: none new. Referenced: `flow-credential-transfer` (S05 asserts only the arrival), `flow-log-out`.

**Proposed shared**: none.
