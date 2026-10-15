---
id: profile-tokens
type: view
title: User profile › API tokens (personal access tokens)
status: not-started
owner:

trigger:
  old_route: /profile/tokens (and /profile/tokens/:id/delete for the confirmation modal)
  new_route:
  old_route_disposition: unchanged
  reachable_when:
    - the user is signed in and admitted by shared-authenticated-session (`router.ex:288`, `:326-327`, `:default` live_session with `on_mount: LightningWeb.InitAssigns`)
    - the account is not locked out pending email confirmation; `/profile/tokens` is deliberately not on the lockout allow list (`confirmation_lockout.ex:14-23`; `confirmation_lockout_live_test.exs:79-97`)
    - no role or project is required; the page only ever lists and deletes the signed-in user's own tokens (`index.ex:14-17`, `:61-63`; `accounts.ex:1128-1131`)

inherits:
  - shared-authenticated-session    # login redirect S01, revoked session S02, TOTP pending S03, lockout S04 (confirmation_lockout_live_test.exs:79-97 covers this route), sidebar S07, book-a-demo banner S08 in the :banner slot (index.html.heex:2-8; book_demo_banner_test.exs:143-158), GDPR banner S10
  - shared-project-header           # no-project header only: global picker S11, S12; role menu S17; account menu S18 ("API Tokens" entry, layout_components.ex:165-170); confirmation banner S13, S14 (layout_components.ex:259-296)
  - shared-local-datetime           # "Created on" and "Last Used at" (index.html.heex:88, :95); S01, S02, S04, S05
  - shared-flash-messages   # added by lead (final pass)

url_params:
  - name: id (path segment of /profile/tokens/:id/delete)
    set_by: profile-tokens (the trash link on each row, index.html.heex:101-107)
    effect: opens the delete confirmation modal for that token if the signed-in user owns it, otherwise flashes "You can't perform this action" and patches back to /profile/tokens (index.ex:31-47)

config_variants:
  default: {}                                                                  # everything below was read under this one
  require-email-verification: { lightning.require_email_verification: true }   # lockout and header banner only, owned by shared-authenticated-session S04 and shared-project-header S13, S14

inventory:
  routes:
    - live /profile/tokens  TokensLive.Index :index               # router.ex:326
    - live /profile/tokens/:id/delete  TokensLive.Index :delete   # router.ex:327
  events:
    - TokensLive.Index#generate_new_token                         # index.ex:49-59
    - Components.TokenDeletionModal#delete_token                  # token_deletion_modal.ex:12-22, :29-42
    - Components.TokenDeletionModal#close_modal                   # token_deletion_modal.ex:24-27
  js_hooks:
    - Copy                                                        # data-to="#new_token" path, index.html.heex:54-63; assets/js/hooks/index.ts:738-817
    - Tooltip                                                     # "Copy to clipboard" / "Copied!", index.html.heex:48-53; assets/js/hooks/index.ts:566-612
    - ModalHook                                                   # components/modal.ex:31-37, via TokenDeletionModal
    # LocalTimeConverter comes through shared-local-datetime
  policies:
    - Lightning.Policies.Users :delete_api_token                  # policies/users.ex:32-38
  workers: []
  api_endpoints: []                                               # tokens made here are consumed by /api and /collections; see Proposed flows
  emails: []
  config: []
  not_reachable_here:
    - shared-usage-limits-banner; this LiveView never mounts `:check_limits`, so `:banner` only carries the book-a-demo banner (index.ex:11, init_assigns.ex:46-54)
    - shared-project-header breadcrumbs, project picker button and project menu items; this page renders the header `:title` branch (index.html.heex:9-20, layout_components.ex:283-296) and `Menu.profile_items` (menu.ex:91-110, layout_components.ex:220-228)
    - Modal `on_open`, `subtitle` and `footer` slots of LightningWeb.Components.Modal (modal.ex:20-28); TokenDeletionModal uses `:title`, the body and `.modal_footer` only
    - Copy hook `data-content` and `phx-then` paths (assets/js/hooks/index.ts:747-751, :801-806); this page sets only `data-to`

related:
  - profile-account                 # API tokens on this page are deleted by a password change there (its 6.2)
  - lib/lightning/accounts.ex       # generate_api_token/1 (:1094-1098), get_user_by_api_token/1 (:1103-1107), delete_token/1 (:1121-1123), list_api_tokens/1 (:1128-1131), get_token!/1 (:401)
  - lib/lightning/accounts/user_token.ex   # build_token "api" (:56-65), verify_token_query "api" (:104-109), user_and_contexts_query :api (:246-251)
  - lib/lightning/tokens.ex         # PersonalAccessToken claims (:8-36), verify/1 (:98-117)
  - test/lightning_web/live/tokens_live_test.exs
  - test/lightning_web/live/confirmation_lockout_live_test.exs   # :79-97
  - test/lightning_web/components/menu_test.exs                  # :115-133, "API Tokens" side menu link
flows:
  - flow-account-revocation-teardown                 # a password change or account deletion deletes every token listed here (its S06)
  - flow-personal-access-token-use
---

## 1. Purpose

Anyone who scripts against Lightning (the CLI, a deploy pipeline, a collections client or their
own integration) comes here to mint the personal access token those tools authenticate with, and
to revoke it when it leaks or is no longer needed. Without this page a user would need an
administrator to grant or cut off programmatic access, and a leaked token would keep working with
the user's full project access until someone noticed.

## 2. What it does

- Any signed-in user generates a new personal access token, sees it in full once with a copy button, and never again
- Any signed-in user sees their own tokens, masked, with when each was created and last used, or an empty state pointing them to generate one
- Any signed-in user deletes one of their own tokens after confirming, or backs out without losing it
- No user can open the deletion of, or delete, another user's token

**Straightforwardness: 4 of 5.** A small page that mostly does what it says; the surprises are about what a token is allowed to do once it leaves the page, not about the page itself.

### Most surprising behaviours

- **(3)** "Last used" only counts calls to the main API. A token used only to read and write collections shows "Never used", which invites the user to delete a token that is keeping an integration alive. (6.1)
- **(3)** Changing your password deletes every token you have. It's the right security call, but nothing here says so, and the scripts using them just start failing. (S11)
- **(3)** Clicking a trash icon before you've copied a token you just made wipes it from the screen for good, so you have to generate another. (6.2)
- **(4)** Tokens have no name, no expiry and no scope. Each one is your full access to every project you're on until you delete it, and generating or deleting one leaves no audit trail. (6.2)

## 3. Who can do what

Source: `lib/lightning/policies/users.ex:32-38`; listing scoped by `user_id` in `user_token.ex:246-251`.
This page has no project or instance role checks; the columns are the relationship to the token.

| Action | Token owner | Another signed-in user | Superuser (not the owner) | Support user (not the owner) |
|--------|-------------|------------------------|---------------------------|------------------------------|
| See the page | yes | yes | yes | yes |
| See the token in the list | yes | no | no | no |
| Generate a token (for themselves) | yes | yes | yes | yes |
| Open the delete modal | yes | no | no | no |
| Delete the token | yes | no | no | no |

**Preconditions beyond role**
- Signed in, with a session that is not disabled, TOTP pending or locked out (shared-authenticated-session S01 to S04).
- Ownership is checked twice: when the `:delete` route loads (`index.ex:31-46`) and when "Yes" is clicked, by comparing the event's id with the one the modal was opened for (`token_deletion_modal.ex:13-21`).
- The policy looks the token up by its value in the `api` context, so a session or other token row id is refused even if it belongs to the user (`policies/users.ex:32-37`; `accounts.ex:1103-1107`).

## 4. What it touches

**Reads**: `user_tokens` where `context = 'api'` and `user_id` is the current user, newest first (`accounts.ex:1128-1131`; `user_token.ex:246-251`); one `user_tokens` row by id on the delete route and on confirm (`accounts.ex:401`); `users` joined from the token for the ownership check (`accounts.ex:1103-1107`, `:1002-1006`); the user's projects for the header picker (`hooks.ex:194-202`)

**Writes**: `user_tokens` insert with context `api` and a signed JWT as the token value (`accounts.ex:1094-1098`; `user_token.ex:56-65`); `user_tokens` delete of one row (`accounts.ex:1121-1123`)

**Immediate side effects** (in the same request)
- none: no audit event, email or broadcast on generate or delete (`accounts.ex:1094-1098`, `:1121-1123`)

**Deferred side effects** (later, elsewhere)
- A generated token authenticates `/api/*` through `authenticate_bearer` and `/collections/*` through `Plugs.ApiAuth` (`router.ex:109-112`, `:163-171`; `user_auth.ex:241-251`; `api_auth.ex:12-21`). Owned by the proposed `flow-personal-access-token-use`.
- Each `/api` request with the token writes `last_used_at`, which this page shows (`user_auth.ex:234-246`; `user_token.ex:74-80`).
- A deleted token fails the existence check on both routes (`user_token.ex:104-109`; `tokens.ex:190-196`).

**External, non-transactional effects**
- none

**Depends on config**
- The JWT is signed with `Lightning.Config.token_signer()` (`user_token.ex:56-62`); rotating the signer would invalidate every listed token while leaving the rows here. Not a variant this view exercises.

**Product limits**
- The full token is shown once, immediately after it is generated (`index.ex:25-29`, `:49-58`; `index.html.heex:29-36`).

## 5. Scenarios

```gherkin
Feature: Personal access tokens
  In order to give my scripts and tools access to Lightning, and take it back
  As a signed-in user
  I want to generate, see and delete my own API tokens

  @S01 @pending
  Scenario: A user with no tokens is pointed to generate one
    # Value: someone setting up the CLI or an integration for the first time can see they have no token yet and how to get one.
    Given I am signed in and have no API tokens
    When I open "/profile/tokens"
    Then I see "Personal Access Tokens" as the page title
    And I see "No Personal Access Tokens" and "Get started by creating a new access token."
    And I see a "Generate New Token" button
    And the side menu marks "API Tokens" as current
    # index.ex:25-29, :17; index.html.heex:114-140; menu.ex:105-108
    # tokens_live_test.exs:15-28 (the button assertion at :26-27 is vacuous, see 6.5)

  @S02 @pending
  Scenario: A user generates a token and sees it in full once
    # Value: a user gets a working credential for their scripts on their own, without asking an administrator.
    Given I am signed in and on "/profile/tokens"
    When I click "Generate New Token"
    Then I see "Token created successfully"
    And I see "Make sure to copy your token now as you will not be able to see it again."
    And the token field shows the full token
    And the token list has a new row showing "..." followed by the token's last 10 characters
    # index.ex:49-59, :65-67; index.html.heex:29-46, :77-82; accounts.ex:1094-1098
    # tokens_live_test.exs:30-53 (full value 539 characters), :55-70 (masked list)

  @S03 @pending
  Scenario: A token can't be read back after leaving the page
    # Value: someone who later sits at the user's browser, or replays its history, can't recover a working token from the page.
    Given I have just generated a token on "/profile/tokens"
    When I reload "/profile/tokens"
    Then I do not see the token field
    And the token's row shows only "..." followed by its last 10 characters
    # index.ex:25-29 (new_token reset on every index load), :65-67; index.html.heex:29, :80-84

  @S04 @pending
  Scenario: Copying the new token puts the whole token on the clipboard
    # Value: a 500-character token is pasted into the script exactly, without a hand-selection that drops characters.
    Given I have just generated a token on "/profile/tokens"
    When I click "Copy to clipboard"
    Then my clipboard holds the full token
    And I briefly see "Copied!"
    # index.html.heex:40-63; assets/js/hooks/index.ts:738-817 (Copy, data-to reads the input value), :595-607 (Tooltip "Copied!")
    # tokens_live_test.exs:42-44 asserts only that the hooked button renders

  @S05 @pending
  Scenario: Each token shows when it was created and whether it has been used
    # Value: a user can spot tokens that are stale or were never used and revoke them before they leak.
    Given I have a token created on 1 March that was last used on 10 March
    And I have a token that has never been used
    When I open "/profile/tokens"
    Then the first token shows its "Created on" and "Last Used at" dates
    And the second token shows "Never used" under "Last Used at"
    # index.html.heex:71-73, :86-98; user_token.ex:42; dates rendered by shared-local-datetime S01
    # how last_used_at gets set belongs to flow-personal-access-token-use (see 6.1 row 1)

  @S06 @pending
  Scenario: A user only sees their own tokens
    # Value: one user can't see another's token fragments or usage, which would hint at their integrations.
    Given "amara@example.org" has an API token
    And I am signed in as "bob@example.org" with one API token
    When I open "/profile/tokens"
    Then the list has exactly one row, for my token
    # index.ex:14-17, :61-63; accounts.ex:1128-1131; user_token.ex:246-251
    # not asserted by any test; read from code

  @S07 @pending
  Scenario: A user deletes a token after confirming
    # Value: a leaked or retired token can be cut off immediately by its owner.
    Given I have an API token listed on "/profile/tokens"
    When I click the delete icon on its row
    Then I am on "/profile/tokens/<token id>/delete"
    And I see "Delete API Access Token"
    And I see "Any applications or scripts using this token will no longer be able to access the API."
    When I click "Yes"
    Then I am on "/profile/tokens"
    And I see "Token deleted successfully"
    And the token's row is gone
    And the flow "flow-personal-access-token-use" refuses that token from now on
    # index.html.heex:101-107; index.ex:31-42; token_deletion_modal.ex:12-15, :29-37, :45-84; accounts.ex:1121-1123
    # tokens_live_test.exs:76-111 (the final refute at :109-110 is vacuous, see 6.5)

  @S08 @pending
  Scenario: Backing out of a deletion keeps the token
    # Value: a misclick on the trash icon doesn't break integrations that depend on the token.
    Given I have opened the delete modal for one of my tokens
    When I click "Cancel"
    Then I am on "/profile/tokens"
    And the token's row is still listed
    # token_deletion_modal.ex:24-27, :86-93 (Cancel and the close button both send close_modal)
    # not asserted by any test; read from code

  @S09 @pending
  Scenario: A user can't open the deletion of someone else's token
    # Value: a guessed or shared token id can't be used to revoke another user's integration.
    Given "amara@example.org" has an API token
    And I am signed in as "bob@example.org"
    When I open "/profile/tokens/<Amara's token id>/delete"
    Then I am on "/profile/tokens"
    And I see "You can't perform this action"
    And I do not see "Delete API Access Token"
    # index.ex:31-46; policies/users.ex:32-38; tokens_live_test.exs:113-125

  @S10 @pending
  Scenario: A forged delete request for someone else's token deletes nothing
    # Value: the confirmation can't be repointed at another user's token by editing the request, and the user's own token isn't removed in its place.
    Given I have opened the delete modal for my own token
    And "amara@example.org" has an API token
    When a delete is submitted from that modal naming Amara's token id
    Then I am on "/profile/tokens"
    And I see "You can't perform this action"
    And both tokens still exist
    # token_deletion_modal.ex:13-21; tokens_live_test.exs:127-151

  @S11 @pending
  Scenario: Tokens revoked by a password change are gone from the list
    # Value: after a user changes a password they believed was leaked, this page shows that their old tokens no longer exist rather than suggesting they still work.
    Given I have an API token listed on "/profile/tokens"
    When the flow "flow-account-revocation-teardown" has run for my own password change
    And I open "/profile/tokens" again
    Then I see "No Personal Access Tokens"
    # handoff only; the revocation is flow-account-revocation-teardown S06 (accounts.ex:927-930; accounts_test.exs:1488-1495)
```

The page shell is not restated: sign-in, lockout and banners are shared-authenticated-session; the
header, account menu and picker are shared-project-header; timestamp display is
shared-local-datetime.

## 6. Unclear value

### 6.1 Possible bugs

| What | Where | What a user sees | Disposition |
|------|-------|------------------|-------------|
| `last_used_at` is written only by `authenticate_bearer` on the `/api` scope; `/collections` authenticates the same token through `Plugs.ApiAuth` and `Tokens.verify/1`, which never update it | `user_auth.ex:234-246`; `router.ex:109-112` vs `:163-164`; `api_auth.ex:12-21` | a token used only for collections reads "Never used", inviting the user to delete a token that is in use | fix |
| Escape, click-away and the backdrop hide the modal client-side only, leaving the URL on `/profile/tokens/:id/delete`; clicking the same row's trash icon again patches to the same URL, the live component keeps its id, and `phx-mounted` does not fire again | `modal.ex:31-48`, `:62-75`; `token_deletion_modal.ex:48`; `index.html.heex:22-28` | possibly nothing happens on the second click until the page is reloaded; not verified in a browser | decide (verify, then fix) |
| `/profile/tokens/:id/delete` with an id that doesn't exist, or isn't a UUID, raises in `get_token!/1` before the ownership check | `index.ex:32`; `accounts.ex:401` | an error page instead of "You can't perform this action" | fix |
| A token deleted elsewhere (a second tab, or a password change through flow-account-revocation-teardown) while its modal is open makes "Yes" raise in `get_token!/1` | `token_deletion_modal.ex:29-31` | the LiveView crashes and reloads instead of a message | fix |

### 6.2 Quirks and implementation details

| What | Where | Disposition |
|------|-------|-------------|
| Tokens never expire, carry no name or description, and have no scope: each grants the owner's full API access until deleted | `user_token.ex:56-65`, `:104-109`; `tokens.ex:18-35` | decide |
| Opening the delete modal (or any patch back to the index) clears the just-generated token, so a user who clicks a trash icon before copying loses the only view of the new token | `index.ex:28`, `:42` | decide |
| The new token field is a disabled input, so in most browsers the copy button is the only way to copy it | `index.html.heex:40-46` | decide |
| Naming differs across the surface: page title "Personal Access Tokens", side menu and account menu "API Tokens", modal "Delete API Access Token"; labels are title case ("Generate New Token", "Last Used at") | `index.ex:27`, `:40`; `menu.ex:105-108`; `layout_components.ex:165-170`; `token_deletion_modal.ex:51-53`; `index.html.heex:16`, `:73` | decide |
| The confirm button reads "Yes" rather than naming the action | `token_deletion_modal.ex:75-85` | decide |
| The delete link on each row is an icon with no text or accessible label | `index.html.heex:101-107` | decide |
| Cancel, the close button and a successful delete all `push_navigate` (a full remount) back to the index rather than patching | `token_deletion_modal.ex:20`, `:26`, `:37` | preserve |
| Tokens are listed newest first | `user_token.ex:246-251` | preserve |
| The mask shows the last 10 characters of the JWT, which fall in its signature | `index.ex:65-67` | preserve |
| With no tokens, "Generate New Token" appears twice: in the header and in the empty state | `index.html.heex:13-18`, `:129-140` | preserve |
| Generating and deleting tokens write no audit event | `accounts.ex:1094-1098`, `:1121-1123` | decide |
| The ownership policy resolves the owner through `get_user_by_api_token/1`, which also returns nil for a disabled or deleted owner; such an owner can't sign in anyway | `policies/users.ex:32-37`; `accounts.ex:1002-1006`, `:1103-1107` | preserve |
| `:delete_api_token` is missing from the policy's `@type actions` | `policies/users.ex:12-16` | preserve |
| `mount/3` loads the token list, and the `:delete` path loads the token row twice (route, then confirm) | `index.ex:14-17`, `:32`; `token_deletion_modal.ex:30` | preserve |

### 6.3 Unreachable or dead code

| What | Where | Why unreachable |
|------|-------|-----------------|
| `{:error, _changeset}` branch with "Something went wrong." | `token_deletion_modal.ex:39-40` | `Repo.delete/1` on a bare struct with no constraints returns `{:ok, _}` or raises (`Ecto.StaleEntryError`), so the branch never runs (`accounts.ex:1121-1123`) |
| Modal `on_open`, `subtitle`, `footer` slots; Copy hook `data-content` and `phx-then` | `modal.ex:20-28`; `assets/js/hooks/index.ts:747-751`, `:801-806` | not used by this view (listed in `not_reachable_here`) |

### 6.4 Performance and operational limits

| What | Where | User-visible? | Disposition |
|------|-------|---------------|-------------|
| No cap on how many tokens a user can generate, and the list is unpaginated | `accounts.ex:1094-1098`, `:1128-1131` | yes, on a long list | decide |
| Each `/api` request with a token issues an `UPDATE` on its row for `last_used_at` | `user_auth.ex:234-239` | no | preserve |
| Header picker loads every project for the user on mount | `hooks.ex:194-202` | no | preserve |
| A new token is accepted up to 60 seconds before its `iat` to absorb replica clock skew | `tokens.ex:12-16`, `:26-34` | no; it prevents a 401 right after generating | preserve |

### 6.5 Things seen but not understood

- `tokens_live_test.exs:26-27` asserts `element(token_live, "a", "Generate New Token")`, which is always truthy (no `has_element?`) and names an `a` where the control is a button. S01's button line is not actually verified. Disposition: preserve (fix the test).
- `tokens_live_test.exs:109-110` refutes `tr#token-<id>`, but rows are `tr#tokens-<id>` (`index.html.heex:78`), so the "row is gone" check is vacuous. Disposition: preserve (fix the test).
- `/api` authenticates a token with `get_user_by_api_token/1`, which rejects disabled accounts but not accounts locked out pending confirmation, while `/collections` uses `Tokens.verify/1`, which rejects both (`user_auth.ex:263-266`; `accounts.ex:1103-1107`; `tokens.ex:98-117`). Belongs to the proposed flow, noted so it isn't lost. Disposition: decide.
- Whether superusers or support users should be able to see or revoke another user's tokens (for offboarding) is not addressed anywhere; today only the owner, or the account revocation flow, can. Disposition: decide.

## 7. Not migrating

| Item | Reason | Decided by | Date |
|------|--------|------------|------|

## 8. Open questions

- Should tokens get names, expiry or scopes in the rebuild (6.2)? (owner: product)
- Should generate and delete be audited (6.2)?
- Does the modal fail to reopen after an Escape close in a real browser (6.1 row 2)?
- Should `last_used_at` reflect collections use as well (6.1 row 1)?

## Proposed flows

- `flow-personal-access-token-use` (new): a token generated on this page is sent as a bearer token to `/api/*` (`authenticate_bearer`, `router.ex:109-112`; `user_auth.ex:241-251`) or `/collections/*` (`Plugs.ApiAuth`, `router.ex:163-171`; `api_auth.ex:12-21`); `/api` requests set `last_used_at`, which this page then shows as "Last Used at" (`user_auth.ex:234-239`); once the token is deleted here both routes refuse it with 401 (`user_token.ex:104-109`; `tokens.ex:190-196`). Surfaces: profile-tokens, controller:api (authenticate_bearer), controller:collections (ApiAuth), profile-tokens. This file asserts only the handoff (S05, S07).
- Referenced, not proposed: `flow-account-revocation-teardown`. A password change or account deletion deletes every token listed here (its S06; `accounts.ex:927-930`, `:964-967`). This file asserts only the end state (S11). The flow's `surfaces` does not yet list profile-tokens although its S06 ends here; the lead may want to add it for the flow lint.

## Proposed shared

- `shared-project-header` (already proposed by projects-dashboard and profile-account): the side menu on non-project pages, `Menu.profile_items` with Projects, User Profile, Credentials and API Tokens, the current one marked; this page sets `active_menu_item: :tokens` (`index.ex:17`, `menu.ex:105-108`, `layout_components.ex:220-228`; `menu_test.exs:115-133`). Surfaces: projects-dashboard, credentials-index, profile-account, profile-tokens.

## Lead resolution (batch 7)

- `flow-personal-access-token-use` created. profile-tokens added to flow-account-revocation-teardown surfaces.
- The side menu stays with shared-project-header, as decided in batch 4.
