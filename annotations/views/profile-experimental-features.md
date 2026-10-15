---
id: profile-experimental-features
type: view
title: User profile › Experimental features
status: not-started
owner:

trigger:
  old_route: /profile                        # card on ProfileLive.Edit, components.ex:67-71
  new_route:
  old_route_disposition: unchanged
  reachable_when:
    - everything profile-account lists for `/profile` (signed in, config-injected `:services` live_session, `router.ex:340-356`, `config/config.exs:50-61`)
    - rendered on every `/profile` load, for every user, with no condition (`components.ex:67-71`)

inherits:
  - shared-authenticated-session    # login redirect and session handling for /profile; S01 to S10
  - shared-project-header           # no-project parts only, as profile-account: account menu S18; experimental mode indicators S16 (menu.ex:18-37, layout_components.ex:111-134)
  - shared-flash-messages   # added by lead (final pass)

url_params: []

config_variants:
  default: {}                                                          # user.preferences has no "experimental_features" key, or it is false; read under this
  experimental-features: { user.preferences.experimental_features: true }   # same variant name as shared-project-header and shared-project-scope; also read under this

inventory:
  routes: []                                         # the route is owned by profile-account
  events:
    - ProfileLive.ExperimentalFeaturesComponent#update_preferences   # experimental_features_component.ex:32-56
  js_hooks: []
  policies: []                                       # no policy check; the card edits the session's own user (components.ex:67-71)
  workers: []
  api_endpoints: []
  emails: []
  config: []
  not_reachable_here:
    - Accounts.update_user_preference/3 (accounts.ex:1417-1424); the single-key writer used by the sidebar toggle, the editor channel, run streaming and the book-demo banner, not by this card
    - Accounts.experimental_features_enabled?/1 consumers (accounts.ex:1445-1448): menu.ex:18-37, :54-61; layout_components.ex:111-134; hooks.ex:295-299; workflow_channel.ex:1379-1380, :1507-1510; collaborate.ex:86-87; workflow_live/index.ex:105; run_live/index.ex:143; run_live/show.ex:327-328; channel_request_live/show.ex:23; dataclip_controller.ex:148. Owned by the views and shared annotations that read the flag

related:
  - profile-account                 # page host
  - shared-project-header           # where the setting shows up once on, and the "Turn off in your profile" link back here
flows: []
---

## 1. Purpose

Any signed-in user can opt their own account into features that are still being built, and opt out
again. It lets the team put unfinished work in front of people who have chosen to try it, without
changing anything for their collaborators. Without it, early features would have to ship to
everyone or to no one, and a user who had been opted in would have no way to get back to the
standard product on their own.

## 2. What it does

- Any signed-in user sees whether experimental features are on for their account
- Any signed-in user turns experimental features on or off for their own account, saved as soon as they flip the switch
- Turning the setting on or off leaves the user's other saved preferences alone

**Straightforwardness: 3 of 5.** It's one switch, but the page works from a copy of your settings taken when it loaded, which leads to changes quietly undoing each other.

### Most surprising behaviours

- **(2)** Collapsing or expanding the sidebar after using the switch undoes the change: the switch flips back and the setting is lost, even though the user saw a success message. (6.1)
- **(2)** Using the switch can undo preferences changed in another tab since this page loaded, such as sidebar or editor layout, so "leaves other preferences alone" only holds if nothing changed elsewhere. (6.1)
- **(3)** After turning experimental features off, the sidebar still says "Experimental" until the page is reloaded, so a user who came here to turn it off thinks it didn't work. (6.1)
- **(4)** The card doesn't say which features the setting turns on, and other open tabs keep the old setting until they're reloaded. (6.2)

## 3. Who can do what

Pulled from the code, not a policy module: the card calls no policy and is bound to the session's
`current_user` (`components.ex:67-71`, `experimental_features_component.ex:22-29`, `:33`).

| Action | Signed-in user (own account) | Superuser (own account) | Support user (own account) | Anyone, on another user's account |
|--------|------------------------------|-------------------------|----------------------------|-----------------------------------|
| See the card and its current state | yes | yes | yes | no |
| Turn experimental features on | yes | yes | yes | no |
| Turn experimental features off | yes | yes | yes | no |

**Preconditions beyond role**
- Self only: the card has no user parameter; it always writes the session's user (`components.ex:67-71`, `experimental_features_component.ex:33`, `:39`).
- No sudo, password or MFA check before the change (`experimental_features_component.ex:32-46`).

## 4. What it touches

**Reads**: `users.preferences` from the session user loaded on mount (`experimental_features_component.ex:9-11`, `:22-29`); nothing else

**Writes**: `users.preferences`, the whole map replaced by the in-memory map merged with `%{"experimental_features" => true | false}` (`experimental_features_component.ex:35-39`, `accounts.ex:631-637`, `user.ex:383-386`)

**Immediate side effects** (in the same request)
- Flash "Experimental features updated successfully" (`experimental_features_component.ex:46`)
- No audit event (`accounts.ex:631-637` does not touch `Accounts.Audit`)
- No PubSub broadcast; other open tabs and this page's own header and side menu keep the old value (see 6.1, 6.2)

**Deferred side effects** (later, elsewhere)
- Every page that mounts after the change reads the new value through `Accounts.experimental_features_enabled?/1` (`accounts.ex:1445-1448`) and shows or hides experimental behaviour; owned by the views listed in `inventory.not_reachable_here`, with the visible indicator in shared-project-header S16

**External, non-transactional effects**
- none

**Depends on config**
- none. The setting is per user; there is no instance switch that hides the card or forces the flag (`components.ex:67-71`, `accounts.ex:1445-1448`)

**Product limits**
- none

## 5. Scenarios

```gherkin
Feature: Experimental features on the user profile
  In order to try features before they are generally available, and to stop trying them
  As any signed-in user
  I want to switch experimental features on and off for my own account

  @S01 @pending
  Scenario: The card shows experimental features off by default
    # Value: nobody is put on unfinished features without choosing to be.
    Given I am signed in and have never changed the setting
    When I open "/profile"
    Then I see the card "Experimental features"
    And I see "Enable access to new features and improvements before they're generally available"
    And the switch is off
    # experimental_features_component.html.heex:5-10, :20; experimental_features_component.ex:9-11
    # new_inputs.ex:865-870, :892-899
    # profile_live_test.exs:660-667 (asserts the copy only, not the switch state)

  @S02 @pending @variant:experimental-features
  Scenario: The card shows the setting is on when it is on
    # Value: a user who is seeing unusual behaviour can check, in one place, whether they opted into it.
    Given I have experimental features turned on
    When I open "/profile"
    Then the switch in "Experimental features" is on
    # experimental_features_component.ex:9-11, :22-29; new_inputs.ex:865-870, :898
    # profile_live_test.exs:669-686 (asserts the heading only, not the switch state)

  @S03 @pending
  Scenario: A user turns experimental features on
    # Value: a user can opt into early features themselves, without asking an administrator.
    Given I am on "/profile" with experimental features off
    When I switch on "Experimental features"
    Then I see "Experimental features updated successfully"
    And experimental features are on for my account
    # experimental_features_component.html.heex:12-21; experimental_features_component.ex:32-46
    # accounts.ex:631-637; user.ex:383-386
    # profile_live_test.exs:688-708, :781-795 (assert the stored value; neither asserts the flash)

  @S04 @pending @variant:experimental-features
  Scenario: A user turns experimental features off
    # Value: a user who finds an early feature getting in the way can get back to the standard product on their own.
    Given I am on "/profile" with experimental features on
    When I switch off "Experimental features"
    Then I see "Experimental features updated successfully"
    And experimental features are off for my account
    # new_inputs.ex:891 (hidden "false" sent when unchecked); experimental_features_component.ex:32-46
    # profile_live_test.exs:710-734

  @S05 @pending
  Scenario: Changing the setting keeps my other preferences
    # Value: opting in or out doesn't quietly reset other personal settings, such as a collapsed sidebar.
    Given I have other saved preferences
    When I switch on "Experimental features"
    Then my other saved preferences are unchanged
    And experimental features are on for my account
    # user.ex:383-386 (Map.merge); experimental_features_component.ex:35-39
    # profile_live_test.exs:736-764

  @S06 @pending
  Scenario: The setting reaches the rest of the app
    # Value: opting in actually changes what the user gets, and they are told it is on wherever they go.
    Given I switched on "Experimental features" on "/profile"
    When I next open a page in a project I belong to
    Then shared-project-header S16 applies to my account
    # handoff only; accounts.ex:1445-1448 read on mount by menu.ex:18-37, :54-61 and layout_components.ex:111-134
    # the end-to-end check, including "Turn off in your profile" landing here, is shared-project-header S16
```

## 6. Unclear value

### 6.1 Possible bugs

| What | Where | What a user sees | Disposition |
|------|-------|------------------|-------------|
| Collapsing or expanding the sidebar on `/profile` after changing this switch writes the page's stale `current_user.preferences` back with only `sidebar_collapsed` changed, undoing the experimental features change; the card then receives that user and flips its switch back | `init_assigns.ex:84-95`; `accounts.ex:1417-1424`; `experimental_features_component.ex:40-45` (only the card's own `user` is updated, never the page's `current_user`); `components.ex:67-71` | turns experimental features on, sees the success flash, clicks "Toggle sidebar", and the switch goes back to off; the setting is lost | fix |
| The write merges into the preferences map loaded when the page mounted, so any preference saved since then from another tab (sidebar, editor layout, run log settings, book-demo banner) is overwritten with its old value | `experimental_features_component.ex:33-39`; `user.ex:383-386`; writers at `init_assigns.ex:89`, `workflow_channel.ex:333`, `run_live/streaming.ex:220`, `book_demo_banner.ex:32` | a preference changed in another tab silently reverts after the switch is used here | fix |
| The page's own side menu "Experimental" indicator and the account menu's "Experimental features on" notice don't change after the switch is used, because `current_user` on the page is never updated | `experimental_features_component.ex:40-45`; `layouts/live.html.heex:83-86`; `layout_components.ex:112-114`; `menu.ex:20-21` | a user who followed "Turn off in your profile", switched it off and saw "Experimental features updated successfully" still sees "Experimental" in the sidebar until they reload | fix |
| The switch has no accessible name: the card passes `label=""` and the `role="switch"` element is not labelled by the card heading | `experimental_features_component.html.heex:20`; `new_inputs.ex:902-905`, `:944-954` | a screen reader announces an unnamed switch | fix |

### 6.2 Quirks and implementation details

| What | Where | Disposition |
|------|-------|-------------|
| The setting saves on every change of the switch; there is no save button | `experimental_features_component.html.heex:16` | preserve |
| The card heading is title case "Experimental Features"; the rebuild uses sentence case "Experimental features" | `experimental_features_component.html.heex:6`; asserted at `profile_live_test.exs:665`, `:685` | preserve (wording), fix (case) |
| Other open tabs keep the old setting until they remount; there is no broadcast | `experimental_features_component.ex:32-46`; readers call `experimental_features_enabled?/1` on mount, e.g. `run_live/show.ex:327-328`, `collaborate.ex:86-87` | decide |
| A change event without the field keeps the stored value; the test sees `false` only because the user started with none | `experimental_features_component.ex:9-16`; `profile_live_test.exs:766-779` | preserve |
| A value that can't be cast to a boolean shows "Failed to update experimental features. Please try again."; the rendered form always sends "true" or "false", so only a hand-crafted event reaches it | `experimental_features_component.ex:37`, `:47-54`; `new_inputs.ex:891-896` | preserve |
| No audit event is recorded for opting in or out | `accounts.ex:631-637` | decide |
| The component id is the fixed string "experimental-features", while the other profile cards are keyed by user id | `components.ex:57-71` | preserve |
| The card does not say which features the setting turns on; the gated behaviour is spread across a dozen call sites | `experimental_features_component.html.heex:5-10`; consumers listed in `inventory.not_reachable_here` | decide |

### 6.3 Unreachable or dead code

| What | Where | Why unreachable |
|------|-------|-----------------|
| `{:error, _changeset}` from `Accounts.update_user_preferences/2` | `experimental_features_component.ex:39`, `:48` | `User.preferences_changeset/2` has no validations (`user.ex:383-386`), so `Repo.update` only fails by raising; the branch is reached only through the cast failure in 6.2 |
| `on_click` branch of the toggle input | `new_inputs.ex:882-888` | this card passes no `on_click`; it uses the form's `phx-change` |

### 6.4 Performance and operational limits

| What | Where | User-visible? | Disposition |
|------|-------|---------------|-------------|
| Every switch change is one `users` update with no debounce | `experimental_features_component.html.heex:16`; `accounts.ex:631-637` | no | preserve |

### 6.5 Things seen but not understood

- No test asserts either flash message: the test comments that component flashes "may not be visible in test render" and checks only the database (`profile_live_test.exs:701-707`). Disposition: preserve (write S03 and S04's flash assertions).
- No test asserts the switch's checked state on load; `"renders experimental features section with enabled state"` asserts only the heading (`profile_live_test.exs:669-686`). Disposition: preserve (write S01 and S02's tests).
- The toggle renders both a focusable `sr-only` checkbox and a `tabindex="0"` `role="switch"` div; it is not clear the div responds to the keyboard, so keyboard users may meet two tab stops for one control (`new_inputs.ex:892-905`). Shared input, not specific to this card. Disposition: decide.

## 7. Not migrating

| Item | Reason | Decided by | Date |
|------|--------|------------|------|

## 8. Open questions

- Should opting in or out be audited, given it changes what the user sees across projects (6.2)?
- Should the card list what the setting currently turns on (6.2)?
- Should other open tabs pick up the change without a reload (6.2)?

## Proposed flows

- none. The cross-page effect of the setting, including the account menu's "Turn off in your profile" link into this card, is already owned by shared-project-header S16; this file asserts only the handoff (S06).

## Proposed shared

- none. The toggle input (`new_inputs.ex:865-958`) is a generic form input; its accessibility notes are recorded here in 6.1 and 6.5 rather than as a shared annotation.

## Lead resolution (batch 7)

- No proposals; the cross-page effect stays with shared-project-header S16.
