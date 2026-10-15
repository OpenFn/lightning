---
id: profile-github
type: view
title: User profile › GitHub access
status: not-started
owner:

trigger:
  old_route: /profile                         # "GitHub Access" card on the profile page
  new_route:
  old_route_disposition: unchanged
  reachable_when:
    - the profile page is reachable (owned by profile-account; config-injected `:services` route, `config/config.exs:58-59`, `router.ex:340-356`)
    - the card is always rendered on `/profile` for the signed-in user, with no role or project check (`components.ex:62-66`, `github_component.ex:9-11`)
    - it is also rendered under the delete-account modal on `/profile/:id/delete` (`components.ex:41-48`, `:62-66`; owned by profile-delete-account)

inherits:
  - shared-authenticated-session    # page host; S01, S02, S03 (login redirect, disabled account, pending second factor)
  - shared-project-header           # no-project header and side menu of the host page, as profile-account; S11, S12, S17, S18
  - shared-flash-messages   # added by lead (final pass)

url_params: []

config_variants:
  default: { github_app: { app_id, app_name, client_id, client_secret, cert all set } }   # config/test.exs:168-175; everything below read under this one unless tagged
  github-disabled: { github_app: { any of cert, app_id, client_id, client_secret unset } }   # version_control.ex:562-568; read from code only, no test

inventory:
  routes: []                                          # /profile is listed by profile-account
  events:
    - ProfileLive.GithubComponent#disconnect-github   # github_component.ex:14-30
  js_hooks:
    - Tooltip on the disabled "Connect your GitHub account" button   # github_component.ex:70-78; new_inputs.ex:289-302
    - show_modal / hide_modal JS commands for disconnect_github_modal   # github_component.ex:54, :103, :128
  policies: []                                        # no policy; the card acts on @user only (github_component.ex:15)
  workers: []
  api_endpoints: []
  emails: []
  config:
    - :lightning, :github_app cert, app_id, client_id, client_secret   # github_enabled? (github_component.ex:86-88; version_control.ex:562-568)
    - :lightning, :github_app client_id, client_secret                 # revocation (version_control.ex:491-493)
  not_reachable_here:
    - GithubComponents.connect_to_github_link, its Tooltip hook, query params and the OAuth callback (github_components.ex:16-40); owned by flow-github-connect
    - ProfileLive.Edit handle_info OauthTokenAdded / OauthTokenFailed and VersionControl.subscribe (edit.ex:15-17, :33-53); owned by flow-github-connect
    - GithubComponents.connect_to_github_link `disabled` attr (github_components.ex:14, :25); this card never passes it
    - GithubComponents.connect_to_github_link `github_query_params` override (github_components.ex:13, :17-18); listed in flow-github-connect 6.3

related:
  - profile-account                   # page host
  - project-settings-github-sync      # the other entry to flow-github-connect; reads the same users.github_oauth_token (settings.ex:916)
  - lib/lightning_web/live/profile_live/github_component.ex
  - lib/lightning_web/components/github_components.ex
  - lib/lightning/version_control/version_control.ex
  - lib/lightning/version_control/github_client.ex
  - lib/lightning/accounts/user.ex
  - test/lightning_web/live/profile_live_test.exs
flows:
  - flow-github-connect               # entry and exit on this card
---

## 1. Purpose

GitHub sync acts with the GitHub identity of the user who sets it up, so every OpenFn user needs one
place to see whether their account is linked to GitHub, link it, and unlink it. This card is that
place. Without it a user couldn't set up version control from the profile, couldn't tell that their
link had lapsed, and couldn't withdraw OpenFn's access to their GitHub account when they leave an
organisation or stop trusting the instance.

## 2. What it does

- Any signed-in user sees whether their own GitHub account is linked, and is told when the link has lapsed
- **Link GitHub**
  - A user with no valid link starts the GitHub connection from here, or reconnects if it lapsed
  - On an instance without GitHub configured, users see that connecting is unavailable (scenario owned by flow-github-connect S06)
- **Unlink GitHub**
  - A linked user disconnects GitHub after confirming, which revokes OpenFn's access on GitHub and removes the stored token
  - A user can back out of the disconnect confirmation without changing anything

**Straightforwardness: 3 of 5.** Connect and disconnect are simple on the surface, but what disconnecting actually does on GitHub's side, and to other accounts, takes explaining.

### Most surprising behaviours

- **(2)** Disconnect always says "GitHub connection removed successfully", even when GitHub refused to revoke access. OpenFn can still act on the user's GitHub account and they aren't told to revoke it themselves. A page left open a while makes this more likely. (6.1, S06)
- **(2)** Disconnecting revokes OpenFn's access for that GitHub user everywhere, so another OpenFn account (or another instance) linked to the same GitHub user quietly stops working while still showing as connected. (6.1)
- **(3)** Other open pages for the same user, like another profile tab or a project's GitHub sync tab, keep showing GitHub as connected until reloaded, and then fail. (6.1)
- **(3)** If an instance turns GitHub off, a user who already has a stored link has no way to remove it from the page. (6.2)
- **(4)** Disconnecting doesn't stop any project's existing GitHub sync; it only stops this user setting up or changing sync. (6.2)

## 3. Who can do what

Pulled from the code, not a policy module: the card calls no policy and acts only on the `user`
assign, which the host sets to `current_user` (`components.ex:62-66`; `github_component.ex:15`).

| Action | Signed-in user (own account) | Superuser (own account) | Support user (own account) | Anyone, on another user's account |
|--------|------------------------------|-------------------------|----------------------------|-----------------------------------|
| See the card and link state | yes | yes | yes | no |
| Start connecting GitHub | yes | yes | yes | no |
| Disconnect GitHub | yes | yes | yes | no |

**Preconditions beyond role**
- Self only: there is no user parameter; the card always shows and changes the session's user (`components.ex:62-66`).
- GitHub must be fully configured on the instance (cert, app id, client id, client secret) for either connect or disconnect to be offered (`github_component.ex:49`, `:69-78`; `version_control.ex:562-568`).
- Disconnect is offered only while the stored token is valid: a non-expiring access token, or a refresh token not yet past `refresh_token_expires_at` (`github_component.ex:50-62`; `version_control.ex:419-432`).
- Connect or reconnect is offered only while the stored token is not valid (`github_component.ex:63-67`).

## 4. What it touches

**Reads**: `users.github_oauth_token` from the `user` assign, loaded with the session at mount, no extra query (`github_component.ex:50`, `:15`; `user.ex:37`); `:lightning, :github_app` config (`version_control.ex:491-493`, `:562-568`)

**Writes**
- `users.github_oauth_token` set to `nil` on disconnect (`version_control.ex:515-517`; `user.ex:372-375`)
- When the access token has expired but the refresh token hasn't, the refreshed token is first saved to `users.github_oauth_token`, without a broadcast, then removed (`version_control.ex:470-484`, `:521-538`)

**Immediate side effects**
- Flash "GitHub connection removed successfully" and a push-navigate to `/profile` (`github_component.ex:17-20`)
- `Logger.error` when revocation on GitHub fails (`version_control.ex:509-511`)
- No audit event and no PubSub broadcast on disconnect (`version_control.ex:490-517`)
- Connect: the link opens GitHub's authorize page in a new tab; everything after is owned by flow-github-connect (`github_component.ex:63-67`; `github_components.ex:21-24`)

**Deferred side effects**
- none

**External, non-transactional effects**
- Possible POST to `https://github.com/login/oauth/access_token` with `grant_type=refresh_token` to get a usable access token (`version_control.ex:388-410`, `:476-481`)
- DELETE `https://api.github.com/applications/<client_id>/grant` with basic auth (client id and secret) and the access token, revoking the user's authorization of the OpenFn GitHub app (`version_control.ex:495-506`; `github_client.ex:94-100`, `:152-160`)
- Both happen before the local token is removed; GitHub's side is not rolled back if the local update fails, and the local token is removed even when GitHub's side fails (`version_control.ex:507-512`)

**Depends on config**
- `:lightning, :github_app` (all four keys gate the card's controls; client id and secret are used for revocation) (`github_component.ex:86-88`; `version_control.ex:491-493`, `:562-568`)

**Product limits**
- none

## 5. Scenarios

```gherkin
Feature: GitHub access on the user profile
  In order to control whether OpenFn can act on GitHub as me
  As any signed-in user
  I want to see, link and unlink my GitHub account from my profile

  @S01 @pending
  Scenario: A user with no GitHub link is offered the connection
    # Value: a user who needs version control knows where to link GitHub and can start without an admin.
    Given I am signed in with no GitHub account connected
    When I open "/profile"
    Then I see the card "GitHub Access"
    And I see "Connect your GitHub Account"
    And I do not see "Disconnect from GitHub"
    When I click "Connect your GitHub Account"
    Then the flow "flow-github-connect" has started for my account
    # github_component.ex:35-48, :63-67; github_components.ex:21-28
    # profile_live_test.exs:424-436 (the completed connection is flow-github-connect S01)

  @S02 @pending
  Scenario: A linked user sees they are connected
    # Value: a user can tell at a glance that OpenFn holds a working link to their GitHub account.
    Given I am signed in with a valid GitHub token
    When I open "/profile"
    Then I see "Disconnect from GitHub"
    And I do not see "Connect your GitHub Account"
    # github_component.ex:50-58; version_control.ex:419-432
    # profile_live_test.exs:495-496, :541-542

  @S03 @pending
  Scenario: A user whose GitHub link lapsed is told and can reconnect
    # Value: a user whose access expired learns why version control stopped working for them and how to restore it.
    Given I am signed in with a GitHub token whose refresh token has expired
    When I open "/profile"
    Then I see "Reconnect your GitHub Account" with the tooltip "Your token has expired"
    And I do not see "Disconnect from GitHub"
    When I click "Reconnect your GitHub Account"
    Then the flow "flow-github-connect" has started for my account
    # github_component.ex:50, :63-67; github_components.ex:26-28; version_control.ex:421-424
    # profile_live_test.exs:478-516 (the completed reconnect is flow-github-connect S04)

  @S04 @pending
  Scenario: A user disconnects GitHub after confirming
    # Value: a user can withdraw OpenFn's access to their GitHub account themselves, both on GitHub and in OpenFn.
    Given I am signed in with a valid, non-expiring GitHub token
    When I click "Disconnect from GitHub"
    Then I see the dialog "Disconnect from GitHub?"
    And I see "Until you reconnect, you will not be able to set up or modify version control for your projects."
    When I click "Disconnect"
    Then OpenFn's grant is revoked on GitHub
    And I am on "/profile" with "GitHub connection removed successfully"
    And I see "Connect your GitHub Account"
    And no GitHub token is stored on my account
    # github_component.ex:14-20, :51-62, :94-134; version_control.ex:490-507, :515-517; github_client.ex:94-100
    # profile_live_test.exs:518-557

  @S05 @pending
  Scenario: Disconnecting with an expired access token still revokes the grant on GitHub
    # Value: unlinking really removes OpenFn's access on GitHub, not only OpenFn's copy, even when the short-lived access token has lapsed.
    Given I am signed in with a GitHub token whose access token has expired but whose refresh token has not
    When I disconnect GitHub and confirm
    Then OpenFn refreshes the access token with GitHub
    And OpenFn's grant is revoked on GitHub with the refreshed access token
    And I see "GitHub connection removed successfully"
    And no GitHub token is stored on my account
    # version_control.ex:441-456, :470-484, :495-507
    # profile_live_test.exs:560-611

  @S06 @pending
  Scenario: Disconnecting succeeds locally even when GitHub refuses
    # Value: a user who wants out is never stuck linked because GitHub is down or rejects the request.
    Given I am signed in with a valid GitHub token
    And GitHub answers the revocation request with an error
    When I disconnect GitHub and confirm
    Then I see "GitHub connection removed successfully"
    And I see "Connect your GitHub Account"
    And no GitHub token is stored on my account
    # version_control.ex:508-512; github_client.ex:212-220
    # profile_live_test.exs:614-653 (see 6.1 for what the user is not told)

  @S07 @pending
  Scenario: Backing out of the disconnect dialog keeps the link
    # Value: one misclick doesn't cut a user off from setting up version control.
    Given I am signed in with a valid GitHub token
    When I click "Disconnect from GitHub"
    And I click "Cancel"
    Then the dialog closes
    And I still see "Disconnect from GitHub"
    And my GitHub token is unchanged
    # github_component.ex:102-110, :128-130
    # no test; read from code
```

## 6. Unclear value

### 6.1 Possible bugs

| What | Where | What a user sees | Disposition |
|------|-------|------------------|-------------|
| When revocation on GitHub fails (refresh fails, network error, any non-204), the error is only logged and the local token is removed, so OpenFn's grant stays live on GitHub | `version_control.ex:508-512`; `github_component.ex:17-20`; asserted as success in `profile_live_test.exs:614-653` | "GitHub connection removed successfully", while GitHub still lists the OpenFn app as authorized; the user has to revoke it on GitHub themselves and is not told | decide |
| The `user` assign is the session user from page load; the validity check and the revocation both use it. A refresh elsewhere (GitHub sync on a settings page saves with `notify: false`, no broadcast) rotates the refresh token, so a later disconnect from this page refreshes with a spent refresh token, fails, and falls into the row above | `github_component.ex:9-11`, `:15`, `:50`; `version_control.ex:479-481`; `components.ex:62-66` | success flash, grant not revoked on GitHub; and a card left open past `refresh_token_expires_at` keeps showing "Disconnect from GitHub" | fix |
| GitHub's grant is per GitHub user and app, so revoking it invalidates every token the app holds for that GitHub user, including one stored on another OpenFn account (or another instance sharing the app) linked to the same GitHub user; that account still looks valid locally because `oauth_token_valid?` only checks expiry | `github_client.ex:94-100`; `version_control.ex:419-432` | the other account still shows "Disconnect from GitHub", but its GitHub calls fail until it reconnects | decide |
| Disconnect broadcasts nothing, so other open pages for the same user (another profile tab, a project's Sync to GitHub tab) keep showing the connected state | `version_control.ex:490-517`; `events.ex:14-32` | stale "Disconnect from GitHub" or installation controls until reload, which then fail | fix |

### 6.2 Quirks and implementation details

| What | Where | Disposition |
|------|-------|-------------|
| On an instance with GitHub not configured, a user who still has a stored token is shown only the disabled connect button; there is no way to remove the token from the UI | `github_component.ex:49`, `:69-78` | decide |
| Success push-navigates to `/profile`, remounting the whole page, rather than updating the card in place | `github_component.ex:20` | preserve |
| Disconnecting from `/profile/:id/delete` (card behind the delete modal) lands on `/profile` and closes the delete modal | `components.ex:41-48`, `:62-66`; `github_component.ex:20` | preserve |
| Disconnecting does not touch any project's GitHub sync: existing repo connections use installation tokens, not the user's | `github_client.ex:162-170`; modal copy `github_component.ex:113-116` | preserve |
| A token that has a refresh token is treated as valid after its access token expires; the refresh happens only when disconnecting | `version_control.ex:419-432`, `:470-484` | preserve |
| Card title "GitHub Access" is title case; the disabled button reads "Connect your GitHub account" and the link "Connect your GitHub Account" (copy mismatch owned by flow-github-connect 6.2) | `github_component.ex:43`, `:77`; `github_components.ex:28` | decide |
| The disabled button's tooltip says "GitHub OAuth has not been enabled for this instance." but the gate also needs cert and app id (owned by flow-github-connect 6.2) | `github_component.ex:75`, `:86-88` | decide |
| The confirm button shows "Disconnecting..." while the GitHub calls run | `github_component.ex:122` | preserve |
| Revocation failure is logged at error level with the full response inspected | `version_control.ex:510` | decide |
| Disconnect records no audit event | `version_control.ex:490-517` | decide |

### 6.3 Unreachable or dead code

| What | Where | Why unreachable |
|------|-------|-----------------|
| `handle_event("disconnect-github")` `{:error, _}` branch and its "Oops! An error occurred while trying to remove the connection. Please try again" flash | `github_component.ex:22-28` | `delete_github_oauth_grant/1` always ends in `remove_oauth_token/1`, a `change/2` to `nil` with no validations; `Repo.update` can only fail by raising (`version_control.ex:507-517`; `user.ex:372-375`) |
| `fetch_user_access_token/1` "user refresh token has expired" and "user has not configured an oauth token" paths from this card | `version_control.ex:451-455`, `:465-468` | the disconnect button only renders when the token is valid (`github_component.ex:50`) |
| `disabled` attr on `connect_to_github_link` | `github_components.ex:14`, `:25` | this card never passes it (`github_component.ex:64-67`) |

### 6.4 Performance and operational limits

| What | Where | User-visible? | Disposition |
|------|-------|---------------|-------------|
| Refresh and revocation run synchronously in the LiveView event with Tesla's default adapter timeout | `github_component.ex:15`; `version_control.ex:398-400`, `:495-506` | yes, "Disconnecting..." until GitHub answers | preserve |

### 6.5 Things seen but not understood

- Whether the Tooltip hook on the wrapping span shows its tooltip over a disabled button in every browser was not checked (`new_inputs.ex:289-302`; `github_component.ex:70-78`). Disposition: preserve.
- `maybe_refresh_access_token/1` parses `token["expires_at"]` without a nil guard; a stored token with `refresh_token_expires_at` but no `expires_at` would crash the disconnect. Whether GitHub can return one without the other was not checked (`version_control.ex:470-472`). Disposition: decide.
- No test covers the github-disabled variant on this card or the cancel path (S07).

## 7. Not migrating

| Item | Reason | Decided by | Date |
|------|--------|------------|------|

## 8. Open questions

- Should a failed revocation on GitHub be reported to the user, with a pointer to revoke on GitHub, instead of a plain success flash (6.1)?
- Should the card reload the user before disconnecting, and should disconnect broadcast so other open pages update (6.1)?
- Is revoking the whole app grant, which affects other OpenFn accounts linked to the same GitHub user, intended (6.1)?
- Should a user be able to remove a stored token when the instance has GitHub turned off (6.2)?
- Should disconnect be audited (6.2)?
- The github-disabled card state is a scenario in flow-github-connect (S06) though it never leaves this card; should it move here?

## Proposed flows

none (references `flow-github-connect`: S01 and S03 assert only that it starts here; its success and failure exits land back on this page through `ProfileLive.Edit` handle_info. Surfaces: profile-github, external:github-oauth-authorize, controller:oauth-github-callback, pubsub:version_control_events:<user_id>)

## Proposed shared

none

## Lead resolution (batch 7)

- No proposals. The github-disabled card state stays with flow-github-connect S06.
