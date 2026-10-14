---
id: flow-github-connect
type: flow
title: Connect a GitHub account
status: not-started
owner:

trigger:
  entry: project-settings-github-sync           # or profile-github; both render GithubComponents.connect_to_github_link
  exit: project-settings-github-sync            # the originating page, whichever it was (settings.ex:688-708; profile_live/edit.ex:33-53)
  surfaces:
    - project-settings-github-sync              # "Connect your GitHub Account" prompt (settings.html.heex:819-836)
    - profile-github                            # "GitHub Access" card (profile_live/github_component.ex:49-79)
    - external:github-oauth-authorize           # https://github.com/login/oauth/authorize in a new tab (github_components.ex:21-24)
    - controller:oauth-github-callback          # GET /oauth/:provider/callback, OauthController.new (router.ex:79; oauth_controller.ex:7-29)
    - pubsub:version_control_events:<user_id>   # events.ex:14-32
    - project-settings-github-sync              # or profile-github: handle_info reloads the page
  reachable_when:
    - the GitHub app is configured (cert, app_id, client_id, client_secret all set; version_control.ex:562-568)
    - on project-settings-github-sync, the viewer can write the GitHub connection (admin or owner), the project has no connection, and the viewer's own token is not valid (settings.html.heex:779-800, :819-836; project_users.ex:29-31)
    - on profile-github, the viewer's own token is not valid (profile_live/github_component.ex:49-50, :63-67)

inherits:
  - shared-authenticated-session          # both entry pages; profile is a config-injected :services route (config/config.exs:58)
  - shared-project-scope                  # entry and exit on project-settings-github-sync only

url_params:
  - name: client_id
    set_by: connect_to_github_link (github_components.ex:33-39)
    effect: identifies the GitHub app to GitHub's authorize page
  - name: redirect_uri
    set_by: connect_to_github_link, built from the endpoint URL (github_components.ex:37)
    effect: sends GitHub back to /oauth/github/callback on this instance
  - name: code
    set_by: external:github-oauth-authorize
    effect: exchanged for the user's token (oauth_controller.ex:7-9; version_control.ex:359-380)

config_variants:
  default: { github_app: { app_id, app_name, client_id, client_secret, cert all set } }   # config/test.exs:168-175; read under this one
  github-disabled: { github_app: { cert: nil, app_id: nil, client_id: nil, client_secret: nil } }   # version_control.ex:562-568; GITHUB_APP_* env, bootstrap.ex:960-1020

inventory:
  routes:
    - get /oauth/:provider/callback  OauthController :new          # router.ex:79
  events:
    - ProjectLive.Settings#handle_info OauthTokenAdded             # settings.ex:688-696
    - ProjectLive.Settings#handle_info OauthTokenFailed            # settings.ex:698-708
    - ProfileLive.Edit#handle_info OauthTokenAdded                 # profile_live/edit.ex:33-41
    - ProfileLive.Edit#handle_info OauthTokenFailed                # profile_live/edit.ex:43-53
  js_hooks:
    - Tooltip on the reconnect link                                # github_components.ex:26
    - inline window.close() in the callback response               # oauth_controller.ex:18-28
  policies:
    - Lightning.Policies.ProjectUsers (:write_github_connection)    # project_users.ex:29-31; gates the settings entry only
  workers: []
  api_endpoints: []
  emails: []
  config:
    - :lightning, :github_app client_id, client_secret             # github_components.ex:34-35; version_control.ex:360-366
    - :lightning, :github_app cert, app_id                         # only through github_enabled? (version_control.ex:562-568)
    - LightningWeb.Endpoint url                                    # redirect_uri host (github_components.ex:37)
  not_reachable_here:
    - VersionControl.delete_github_oauth_grant/1 and the "Disconnect from GitHub" modal (version_control.ex:489-513; profile_live/github_component.ex:14-30, :94-134); owned by profile-github
    - VersionControl.refresh_oauth_token/1 and the refresh inside fetch_user_access_token/1 (version_control.ex:386-410, :470-484); saves with notify false, so it never enters this flow

related:
  - lib/lightning_web/components/github_components.ex
  - lib/lightning_web/controllers/oauth_controller.ex
  - lib/lightning/version_control/version_control.ex
  - lib/lightning/version_control/events.ex
  - lib/lightning/version_control/github_client.ex
  - lib/lightning_web/live/project_live/settings.ex
  - lib/lightning_web/live/project_live/settings.html.heex
  - lib/lightning_web/live/profile_live/edit.ex
  - lib/lightning_web/live/profile_live/github_component.ex
  - lib/lightning/accounts/user.ex
flows: []
---

## 1. Purpose

GitHub sync acts with the GitHub identity of the person who sets it up, so before an admin can
connect a project to a repository, their OpenFn account has to hold a GitHub token. This flow gets
that token: the user authorizes the OpenFn GitHub app in a new tab, and the page they started from
updates on its own to show they are connected. Without it, nobody could set up or modify version
control, and a user whose token lapsed would have no way back.

## 2. What it does

User clicks "Connect your GitHub Account" (or "Reconnect") on the profile or a project's Sync to GitHub tab; authorizes on GitHub in a new tab; the callback stores the token and closes that tab; the original page reloads showing "GitHub account linked successfully", or shows "Oops! GitHub account failed to link. Please try again".

## 3. Who can do what

Sources: `lib/lightning/policies/project_users.ex:29-31` (`:write_github_connection` is an admin
action), checked as `can_install_github` (`settings.ex:152-157`) and applied at
`settings.html.heex:797-798`. The profile card has no role check (`profile_live/github_component.ex:49-68`).
The callback checks only that someone is logged in (`oauth_controller.ex:5`, `:8`).

| Action                                       | Viewer | Editor | Admin | Owner | Superuser | Support |
|----------------------------------------------|--------|--------|-------|-------|-----------|---------|
| Start from profile-github                    | yes    | yes    | yes   | yes   | yes       | yes     |
| Start from project-settings-github-sync      | no     | no     | yes   | yes   | as shared-project-scope | as shared-project-scope |
| Complete the callback and store a token      | any logged-in user, for their own account only | | | | | |

**Preconditions beyond role**
- The GitHub app must be fully configured; otherwise neither entry offers the link (`version_control.ex:562-568`; `profile_live/github_component.ex:49`, `:69-78`; `settings.html.heex:779`, `:838-848`).
- The link is offered only when the user's own token is not valid: none stored, or a refresh token past its expiry (`version_control.ex:418-432`; `settings.html.heex:800`, `:819`; `profile_live/github_component.ex:50`, `:63`).
- On the settings entry, the project must have no GitHub connection (`settings.html.heex:780`, `:797`).
- The token is always stored against the user whose browser session completes the callback (`oauth_controller.ex:8-11`), not against a project.

## 4. What it touches

**Reads**
- Entry: `users.github_oauth_token` for the valid check and the Connect/Reconnect label (`github_components.ex:26-28`; `version_control.ex:418-432`)
- Callback: the session's user via `users_tokens` (`user_auth.ex:175-182`)

**Writes**
- Callback: `users.github_oauth_token`, stored encrypted (`Lightning.Encrypted.Map`, `redact: true`; `user.ex:37`), with `expires_at` and `refresh_token_expires_at` computed from `expires_in` and `refresh_token_expires_in` (`version_control.ex:519-561`; `user.ex:377-381`)

**Immediate side effects**
- Entry: the link opens GitHub's authorize page in a new tab with `client_id` and `redirect_uri` (`github_components.ex:21-24`, `:33-39`)
- Callback: POST to `https://github.com/login/oauth/access_token` with client id, secret and code (`version_control.ex:359-380`; `github_client.ex:126-137`)
- Callback, on success: PubSub `OauthTokenAdded` on `version_control_events:<user_id>` (`version_control.ex:529-534`; `events.ex:14-19`)
- Callback, on failure: PubSub `OauthTokenFailed` with GitHub's error body on the same topic; nothing written (`oauth_controller.ex:13-14`; `events.ex:21-26`)
- Callback response: an HTML page that closes its own tab on load (`oauth_controller.ex:18-28`)
- Exit, success: the subscribed page flashes "GitHub account linked successfully" and push-navigates to itself, `/projects/:id/settings#vcs` or `/profile` (`settings.ex:688-696`; `profile_live/edit.ex:33-41`)
- Exit, failure: the subscribed page flashes "Oops! GitHub account failed to link. Please try again" and stays (`settings.ex:698-708`; `profile_live/edit.ex:43-53`)
- Every connected settings page and profile page the user has open is subscribed (`settings.ex:104-106`; `profile_live/edit.ex:15-17`) and reacts, not only the one that started the flow (6.2)

**Deferred side effects**
- none

**External, non-transactional effects**
- GitHub records the user's authorization of the app on its side as soon as they approve, whether or not the code exchange or save succeeds. Undoing it is profile-github's disconnect (`version_control.ex:489-513`).

**Depends on config**
- `:lightning, :github_app` (all four keys gate the entry; `client_id` and `client_secret` are used in the URL and exchange) (`version_control.ex:360-366`, `:562-568`; `github_components.ex:34-35`)
- Endpoint URL config sets the `redirect_uri` host, which must match the GitHub app's registered callback (`github_components.ex:37`)

**Product limits**
- none. The settings entry restyles the link under the GitHub sync limit but does not stop it (owned by project-settings-github-sync 6.1).

## 5. Scenarios

```gherkin
Feature: Connect a GitHub account
  In order to set up version control for my projects
  As an OpenFn user
  I want to link my GitHub account and see that it worked without leaving the page I was on

  @S01 @pending
  Scenario: User connects GitHub from the profile
    # Value: a user can link GitHub once and is told it worked on the page they started from.
    Given I am logged in with no GitHub account connected
    And I am on my profile page
    When I click "Connect your GitHub Account"
    Then GitHub's authorization page opens in a new tab
    When I authorize the app on GitHub
    Then the GitHub tab closes
    And eventually the original tab shows "GitHub account linked successfully"
    And I see "Disconnect from GitHub"
    And I do not see "Connect your GitHub Account"
    # github_components.ex:16-31; oauth_controller.ex:7-29; version_control.ex:359-380, :516-535
    # events.ex:14-19; profile_live/edit.ex:15-17, :33-41; profile_live/github_component.ex:50-68
    # profile_live_test.exs:423-448

  @S02 @pending
  Scenario: Admin connects GitHub from a project's Sync to GitHub tab and can then set up sync
    # Value: an admin blocked on a missing GitHub link fixes it in place and goes straight on to connecting the project.
    Given I am an admin on project "Malawi HIV", which has no GitHub connection
    And I have no GitHub account connected
    And I am on the "Sync to GitHub" tab
    When I click "Connect your GitHub Account" and authorize the app on GitHub in the new tab
    Then the GitHub tab closes
    And eventually the original tab reloads on the "Sync to GitHub" tab with "GitHub account linked successfully"
    And I see "Create/update GitHub installations or modify permissions."
    And I do not see "Connect your GitHub Account"
    # settings.html.heex:797-836; settings.ex:104-106, :688-696; oauth_controller.ex:7-11
    # project_live_test.exs:4774-4806

  @S03 @pending
  Scenario: A failed link is reported and can be retried
    # Value: the user knows the link did not take, rather than assuming they are connected, and can try again.
    Given I have no GitHub account connected
    And I am on my profile page, or on the "Sync to GitHub" tab of a project I administer
    When I authorize the app on GitHub
    But GitHub rejects the code exchange
    Then eventually the original tab shows "Oops! GitHub account failed to link. Please try again"
    And I still see "Connect your GitHub Account"
    And no GitHub token is stored on my account
    # oauth_controller.ex:12-14; version_control.ex:374-378; events.ex:21-26
    # settings.ex:698-708; profile_live/edit.ex:43-53
    # profile_live_test.exs:450-475; project_live_test.exs:4808-4846

  @S04 @pending
  Scenario: A user whose GitHub access expired reconnects
    # Value: lapsed GitHub access can be restored by the user alone, without disconnecting first or asking an admin.
    Given my stored GitHub refresh token has expired
    When I open my profile page
    Then I see "Reconnect your GitHub Account" with the tooltip "Your token has expired"
    When I click it and authorize the app on GitHub
    Then eventually the original tab shows "GitHub account linked successfully"
    And I see "Disconnect from GitHub"
    # github_components.ex:26-28; version_control.ex:418-432; profile_live/github_component.ex:50, :63-67
    # oauth_controller.ex:7-11 (save overwrites the column, user.ex:377-381)
    # profile_live_test.exs:478-514 (label and tooltip only; the completed reconnect is read from code)

  @S05 @pending
  Scenario: A callback without a signed-in user stores nothing
    # Value: a GitHub token is only ever attached to the OpenFn user whose session completed the authorization.
    Given my OpenFn session has ended
    When GitHub redirects to "/oauth/github/callback" with a valid code
    Then the code is not exchanged
    And no GitHub token is stored on any account
    # oauth_controller.ex:5, :8-16; user_auth.ex:175-182

  @S06 @pending @variant:github-disabled
  Scenario: The flow cannot start when GitHub is not configured on the instance
    # Value: users are not sent to a GitHub authorization that can never complete.
    Given the instance has no GitHub app configured
    When I open my profile page
    Then "Connect your GitHub account" is disabled with the tooltip "GitHub OAuth has not been enabled for this instance."
    And no link to GitHub's authorization page is shown
    # profile_live/github_component.ex:49, :69-78; version_control.ex:562-568
    # settings tab equivalent is owned by project-settings-github-sync (settings.html.heex:838-848)
```

## 6. Unclear value

### 6.1 Possible bugs

| What | Where | What a user sees | Disposition |
|------|-------|------------------|-------------|
| The callback matches only `provider: "github"` with a `code`; GitHub's redirect when the user clicks Cancel (`error=access_denied`, no code) raises `Phoenix.ActionClauseError` | `oauth_controller.ex:7` | a 400 error page in the GitHub tab, which stays open; the original page never hears anything | fix |
| The authorize URL carries no `state` and the callback checks none, so any page can drive a logged-in user's browser to `/oauth/github/callback?code=<attacker's code>` and link the attacker's GitHub account to them | `github_components.ex:33-39`; `oauth_controller.ex:7-11` | nothing visible; the victim's later GitHub sync setup runs against the attacker's installations | decide |
| With no signed-in user the callback closes the tab and broadcasts nothing | `oauth_controller.ex:8-16` | the GitHub tab closes and the original page silently keeps showing "Connect" | fix |
| The result of `save_oauth_token` is ignored; a failed update neither broadcasts success nor failure | `oauth_controller.ex:10-11`; `version_control.ex:521-538` | the tab closes and nothing happens on the original page | fix |

### 6.2 Quirks and implementation details

| What | Where | Disposition |
|------|-------|-------------|
| The broadcast goes to every page the user has open on profile or any project's settings, whichever tab; a settings page open on another project and another tab is navigated to that project's `#vcs` with the success flash | `events.ex:14-19`, `:28-32`; `settings.ex:104-106`, `:688-696`; `profile_live/edit.ex:15-17` | decide |
| Success reloads the page with `push_navigate` rather than updating the component in place | `settings.ex:695`; `profile_live/edit.ex:40` | preserve |
| The PubSub topic is `version_control_events:<user_id>`; the template's example names it `github_oauth:<user_id>` | `events.ex:32` | preserve |
| The controller route is generic (`/oauth/:provider/callback`) but only GitHub is handled | `router.ex:79`; `oauth_controller.ex:7` | decide |
| A token with a refresh token still counts as valid after its access token expires; the entry hides the link and the refresh happens on the next GitHub call | `version_control.ex:418-432`, `:470-484` | preserve |
| Label reads "Reconnect" whenever any token is stored, but the link is only rendered when the token is invalid, so in practice "Reconnect" means expired | `github_components.ex:26-28`; `settings.html.heex:800`, `:819`; `profile_live/github_component.ex:50`, `:63` | preserve |
| Copy differs between the disabled profile button ("Connect your GitHub account") and the link ("Connect your GitHub Account") | `profile_live/github_component.ex:77`; `github_components.ex:28` | decide |
| The profile card checks `github_enabled?` (needs cert and app_id too) although its tooltip says "GitHub OAuth has not been enabled", which only needs client id and secret | `profile_live/github_component.ex:75`, `:86-88`; `version_control.ex:562-568` | decide |
| The settings link is visually disabled under a GitHub sync limit but still opens GitHub (owned by project-settings-github-sync 6.1) | `github_components.ex:21-25`; `settings.html.heex:833` | decide |

### 6.3 Unreachable or dead code

| What | Where | Why unreachable |
|------|-------|-----------------|
| `User.github_token_changeset/2` `validate_required` failing | `user.ex:377-381` | the exchange only returns `{:ok, body}` when the body has `access_token`, so the map is never empty |
| `github_query_params` attr override | `github_components.ex:13`, `:17-18` | neither caller passes it (`settings.html.heex:830-834`; `profile_live/github_component.ex:64-67`) |

### 6.4 Performance and operational limits

| What | Where | User-visible? | Disposition |
|------|-------|---------------|-------------|
| The code exchange runs synchronously in the callback request with Tesla's default adapter timeout | `oauth_controller.ex:9`; `github_client.ex:126-137` | yes, a slow GitHub keeps the GitHub tab blank until it answers | preserve |

### 6.5 Things seen but not understood

- Whether `window.close()` succeeds in every browser for a tab opened by a plain `target="_blank"` link was not checked (`github_components.ex:24`; `oauth_controller.ex:22-24`). If it fails, the user is left on a blank tab while the original page has already updated.
- No controller test exists for `OauthController`; the callback is exercised only through the two LiveView tests (`profile_live_test.exs:423-475`; `project_live_test.exs:4774-4846`).

## 7. Not migrating

| Item | Reason | Decided by | Date |
|------|--------|------------|------|

## 8. Open questions

- Should the authorize URL carry a `state` bound to the session, and should the callback reject a mismatch (6.1)?
- Should only the page that started the flow react, rather than every open profile and settings page (6.2)?
- Should GitHub's cancel or error redirect be shown on the original page like an exchange failure (6.1)?
- Should a callback with no session tell the original page to log in again, rather than closing silently (6.1)?

## Proposed flows

none

## Proposed shared

none (`shared-github-connect-link` folded into this flow by the lead)
