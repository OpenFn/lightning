---
id: flow-personal-access-token-use
type: flow
title: Using a personal access token
status: not-started
owner:

trigger:
  entry: profile-tokens
  exit: profile-tokens
  surfaces:
    - profile-tokens                    # "Generate New Token" (tokens_live/index.ex:49-59; accounts.ex:1094-1098)
    - capability:api                    # /api/* behind :authenticate_bearer and :require_authenticated_api_resource (router.ex:104-134; user_auth.ex:241-251, :357-368)
    - capability:collections-api        # /collections/* behind :authenticated_api, i.e. Plugs.ApiAuth (router.ex:53-56, :163-172; api_auth.ex:12-21)
    - profile-tokens                    # "Last Used at" and the delete modal (index.html.heex:93-97; token_deletion_modal.ex:29-37)
  reachable_when:
    - the token holder sends `Authorization: Bearer <token>`, exactly one header, with the "Bearer " prefix (user_auth.ex:254-261; api_auth.ex:24-31)
    - the owner's account is not disabled or scheduled for deletion (accounts.ex:1103-1107, :1002-1006, :329-332; tokens.ex:206-217)

inherits:
  - shared-local-datetime               # how "Last Used at" renders on the exit surface (index.html.heex:93-97)

url_params: []

config_variants:
  default: {}                                                                  # read under this one
  require-email-verification: { lightning.require_email_verification: true }   # adds the confirmation-deadline refusal on both hops (accounts.ex:1360-1368)

inventory:
  routes:
    - scope /api with pipe_through [:api, :authenticate_bearer, :require_authenticated_api_resource]   # router.ex:104-134
    - scope /collections with pipe_through [:authenticated_api]                                         # router.ex:163-172
  events: []                                     # generate and delete are owned by profile-tokens
  js_hooks: []
  policies: []                                   # project-level checks after authentication belong to the capabilities (e.g. Lightning.Policies.Collections, collections_controller.ex:150-158)
  workers: []
  api_endpoints:
    - LightningWeb.UserAuth.authenticate_bearer/2            # user_auth.ex:241-251
    - LightningWeb.UserAuth.require_authenticated_api_resource/2   # user_auth.ex:357-368
    - LightningWeb.Plugs.ApiAuth                              # api_auth.ex:12-46
    - LightningWeb.Plugs.AccessTokenAuth (refusal of PATs only)   # access_token_auth.ex:19-29
  emails: []
  config:
    - Lightning.Config.token_signer/0            # user_token.ex:56-62; tokens.ex:103-106
    - :lightning, :require_email_verification    # accounts.ex:1366
  not_reachable_here:
    - Lightning.VersionControl.get_repo_connection_for_token/1 and the %ProjectRepoConnection{} branch of require_authenticated_api_resource (user_auth.ex:263-266, :365-366; version_control.ex:162); repo connection tokens, owned by flow-github-sync-actions
    - Lightning.Tokens.verify/1 "run:" branch (tokens.ex:118-119); run tokens on /collections, not personal access tokens
    - Lightning.Tokens.get_subject/1 run clause (tokens.ex:186-188)

related:
  - lib/lightning_web/controllers/user_auth.ex
  - lib/lightning_web/plugs/api_auth.ex
  - lib/lightning_web/plugs/access_token_auth.ex
  - lib/lightning/tokens.ex
  - lib/lightning/accounts/user_token.ex
  - test/lightning_web/controllers/user_auth_test.exs          # :20-136
  - test/lightning_web/controllers/api/project_controller_test.exs   # :10-92
  - test/lightning_web/collections_controller_test.exs         # :21-173
  - test/lightning/tokens_test.exs                             # :18-163, :247-357
  - test/lightning/token_matrix_test.exs                       # :73-106
  - test/lightning_web/plugs/access_token_auth_test.exs        # :62-66
flows:
  - flow-account-revocation-teardown    # disable (its S05) and password change or deletion (its S06) refuse the token; not repeated here
  - flow-require-project-mfa            # an unenrolled member's token is refused on MFA-required projects (project_mfa_enforcement_test.exs:256-336)
  - flow-workflow-api-edit-conflict     # one consumer of the /api hop
---

## 1. Purpose

People who script against Lightning (the CLI, a deploy pipeline, a collections client) mint a
personal access token on their profile and send it as a bearer token. This flow is the contract
that the token they just made works on both APIs, that the tokens page tells them whether it is
being used, and that deleting it there cuts it off everywhere. Without it a user can't tell a
dead token from a live one, and a leaked token they "deleted" could keep reading and writing
project data.

## 2. What it does

1. A user generates a personal access token on the tokens page of their profile.
2. A script uses it to call the main API and the collections API, with the user's own project access.
   - It can't be used to manage user accounts
   - An account that hasn't confirmed its email in time is refused until it does, then the same token works again
3. Back on the tokens page, "Last Used at" shows when the token was last used.
4. The user deletes the token there, and both APIs refuse it from then on; their other tokens keep working.

**Straightforwardness: 3 of 5.** The journey is what you'd expect, but the two APIs check the token in different ways, and "Last Used at" doesn't mean quite what it says.

### Most surprising behaviours

- **(3)** "Last Used at" only moves for the main API. A token used only by a collections client shows "Never used", which invites the user to delete one that is keeping an integration alive. (6.1)
- **(3)** "Last Used at" also moves for requests that were refused because the account hadn't confirmed its email, so it can show recent use of a token that isn't working. (6.1)
- **(3)** Every refusal is the same bare "Unauthorized", whether the token was deleted, the account is blocked, or the user simply isn't on that project, so it's hard to tell what went wrong. (6.2)
- **(3)** The two APIs check tokens separately, so a server-side key change could stop every token on collections while they keep working on the main API. (6.2)

## 3. Who can do what

Source: `user_auth.ex:241-251`, `:357-368`; `api_auth.ex:12-46`; `tokens.ex:98-117`, `:190-218`;
`access_token_auth.ex:19-29`. Columns are the state of the token and its owner, since no role is
checked at the authentication hop.

| Action | Active owner | Owner disabled or scheduled for deletion | Owner past confirmation deadline (`require-email-verification`) | Token row deleted |
|--------|--------------|------------------------------------------|-----------------------------------------------------------------|-------------------|
| Authenticate on `/api/*` (bearer scope) | yes | no, 401 | no, 401 | no, 401 |
| Authenticate on `/collections/*` | yes | no, 401 | no, 401 | no, 401 |
| Authenticate on `/api/users` (service account scope) | no, 401 | no, 401 | no, 401 | no, 401 |
| Moves "Last Used at" on the tokens page | `/api` only | no | yes, although refused (6.1) | no |

**Preconditions beyond role**
- Authenticating is not authorizing: once through, each endpoint applies the owner's project access (e.g. `collections_controller.ex:150-158`; `project_controller_test.exs:133-137`), and MFA-required projects refuse unenrolled members (flow-require-project-mfa).
- `/collections` additionally checks the JWT signature, issuer, `sub` prefix and `iat` (60 s skew allowed); `/api` only looks the token string up in `user_tokens` (`tokens.ex:18-35`, `:102-106`; `user_token.ex:104-109`; `token_matrix_test.exs:97-106`). See 6.2.

## 4. What it touches

**Hop 1: profile-tokens, generate** (owned by profile-tokens S02)
- Writes `user_tokens` insert, context `api`, value a JWT signed with `token_signer` (`accounts.ex:1094-1098`; `user_token.ex:56-65`).

**Hop 2: capability:api**
- Reads `user_tokens` joined to `users` by token value and context `api` (`user_auth.ex:263-266`; `accounts.ex:1103-1107`; `user_token.ex:104-109`); falls back to `project_repo_connections` (not this flow).
- Writes `user_tokens.last_used_at = now()` on every request whose token resolves to a user, before the lockout check (`user_auth.ex:234-239`, `:244-246`; `user_token.ex:74-80`).
- Refusal: 401 `{"error": "Unauthorized"}` via `ErrorView` (`user_auth.ex:357-375`; `project_controller_test.exs:17-23`).

**Hop 3: capability:collections-api**
- Reads `user_tokens` existence by value (`tokens.ex:192-196`), then `users` twice: once for account status (`tokens.ex:206-217`) and once to assign `:subject` (`api_auth.ex:34-38`; `tokens.ex:182-184`).
- Writes nothing at the authentication hop; `last_used_at` is not touched (6.1).
- Refusal: 401 `{"error": "Unauthorized"}` (`api_auth.ex:40-46`; `collections_controller_test.exs:21-25`).

**Hop 4: profile-tokens, view and delete** (owned by profile-tokens S05, S07)
- Reads `user_tokens.last_used_at` (`index.html.heex:93-97`); deletes one `user_tokens` row (`accounts.ex:1121-1123`).

**Immediate side effects** (in the same request)
- `UPDATE user_tokens SET last_used_at` per `/api` request (`user_auth.ex:234-239`).
- A `Logger.warning` for a token whose claims can't be read, on `/collections` only (`tokens.ex:163-172`).

**Deferred side effects** (later, elsewhere)
- none: no audit event, email, broadcast or job on use or refusal.

**External, non-transactional effects**
- none

**Depends on config**
- `Lightning.Config.token_signer()`: signs at hop 1, verified at hop 3 only (`user_token.ex:56-62`; `tokens.ex:103-106`).
- `require_email_verification`: variant `require-email-verification` (`accounts.ex:1360-1368`).

**Product limits**
- Tokens have no expiry, scope or per-token rate limit; owned by profile-tokens 6.2.

## 5. Scenarios

```gherkin
Feature: Using a personal access token
  In order to script against Lightning and keep control of that access
  As a user with a personal access token
  I want the token to work on the APIs until I delete it, and to see when it was last used

  @S01 @pending
  Scenario: A newly generated token works on the API
    # Value: a user gets their CLI or deploy pipeline talking to Lightning on their own, minutes after deciding to.
    Given "amara@example.org" is a member of project "Malawi HIV"
    And she has generated a token on "/profile/tokens"
    When a request to "/api/projects" is sent with "Authorization: Bearer <token>"
    Then the response is 200 and lists "Malawi HIV"
    # router.ex:104-117; user_auth.ex:241-251, :357-368; accounts.ex:1103-1107
    # project_controller_test.exs:70-92 (token minted by assign_bearer_for_api, conn_case.ex:156-163)

  @S02 @pending
  Scenario: The same token works on collections
    # Value: one credential serves both the CLI and a collections client, so the user doesn't manage a second kind of key.
    Given "amara@example.org" is a member of the project that owns collection "patients"
    And she has generated a token on "/profile/tokens"
    When a request to "/collections/patients" is sent with that token as a bearer
    Then the response is 200
    # router.ex:163-166; api_auth.ex:12-21; tokens.ex:98-117; collections_controller_test.exs:71-84

  @S03 @pending
  Scenario: Using a token on the API updates "Last Used at"
    # Value: a user deciding which tokens to revoke can see which ones their integrations still use.
    Given "amara@example.org" has a token that shows "Never used" on "/profile/tokens"
    When a request to "/api/projects" is sent with that token
    And she reloads "/profile/tokens"
    Then that token's "Last Used at" shows the time of the request
    # user_auth.ex:234-239, :244-246; user_token.ex:74-80; index.html.heex:93-97
    # not asserted by any test; read from code. Collections use does not update it (6.1 row 1)

  @S04 @pending
  Scenario Outline: A deleted token is refused on both APIs
    # Value: a leaked or retired token stops working the moment its owner deletes it, even though the owner keeps their project access.
    Given "amara@example.org" is a member of the project that owns collection "patients"
    And she has a token that has worked on <path>
    When she deletes the token on "/profile/tokens"
    And a request to <path> is sent with that token
    Then the response is 401 with body {"error": "Unauthorized"}
    # profile-tokens S07 (the delete); accounts.ex:1121-1123
    # /api: user_token.ex:104-109; user_auth.ex:263-266, :357-360 (no end-to-end test; accounts_test.exs:1642-1650 only checks the row is gone)
    # /collections: tokens.ex:107, :111, :190-196; collections_controller_test.exs:88-104; tokens_test.exs:127-138

    Examples:
      | path                    |
      | "/api/projects"         |
      | "/collections/patients" |

  @S05 @pending
  Scenario: Deleting one token leaves the others working
    # Value: revoking a leaked token doesn't break the user's other integrations.
    Given "amara@example.org" has tokens "A" and "B"
    When she deletes token "A" on "/profile/tokens"
    Then requests with token "B" to "/api/projects" and "/collections/patients" still succeed
    # accounts.ex:1121-1123 (one row by id); user_token.ex:104-109 and tokens.ex:192-196 (lookup by value)
    # tokens_test.exs:151-163 asserts this across two users only; same-user case read from code

  @S06 @pending
  Scenario: A personal access token can't manage user accounts
    # Value: a leaked personal token, even a superuser's, can't be used to create or change user accounts through the API.
    Given "amara@example.org" has generated a token on "/profile/tokens"
    When a request to "/api/users" is sent with that token
    Then the response is 401 with body {"error": "invalid_token"}
    And the response carries 'www-authenticate: Bearer error="invalid_token"'
    # router.ex:95-101; access_token_auth.ex:19-29, :38-44; access_token_auth_test.exs:62-66

  @S07 @pending @variant:require-email-verification
  Scenario Outline: An account past its confirmation deadline can't use its token until confirmed
    # Value: an account that never proved its email address can't keep scripts running, and confirming restores them without reissuing the token.
    Given email verification is required
    And "amara@example.org" registered 50 hours ago, has not confirmed her email, and has a token
    When a request to <path> is sent with that token
    Then the response is 401
    When she confirms her email address
    Then the same token is accepted on <path>
    # /api: user_auth.ex:362-363; accounts.ex:1360-1368; project_controller_test.exs:26-66; user_auth_test.exs:89-136
    # /collections: tokens.ex:108, :114, :214; collections_controller_test.exs:128-173

    Examples:
      | path                    |
      | "/api/projects"         |
      | "/collections/patients" |
```

Disabling an account, changing its password and deleting it are refusals owned by
flow-account-revocation-teardown (its S05, S06). Project membership and MFA refusals after
authentication belong to the capabilities and flow-require-project-mfa.

## 6. Unclear value

### 6.1 Possible bugs

| What | Where | What a user sees | Disposition |
|------|-------|------------------|-------------|
| `last_used_at` is written only on `/api`; `/collections` authenticates through `Plugs.ApiAuth` and `Tokens.verify/1`, which never write it | `user_auth.ex:234-246`; `api_auth.ex:12-21`; `tokens.ex:98-117` | a token used only by a collections client reads "Never used", inviting the user to delete a token that is in use | fix |
| `last_used_at` is written in `authenticate_bearer` before `require_authenticated_api_resource` refuses a locked-out account | `user_auth.ex:244-246` runs before `:362-363` | under `require-email-verification`, "Last Used at" moves for requests that were refused with 401 | fix |
| `update_last_used/1` re-queries the row and calls `Repo.update!`; if the token is deleted between the lookup and the update, `last_used_changeset(nil)` raises | `user_auth.ex:234-239`, `:243-246` | a 500 instead of a 401 for a request racing a delete on the tokens page; not reproduced | fix |

### 6.2 Quirks and implementation details

| What | Where | Disposition |
|------|-------|-------------|
| The two hops are separate implementations of the same check: `/api` looks the raw string up in `user_tokens` with no signature or claim check, `/collections` verifies the JWT then checks the row and account. Consequence: rotating `token_signer` kills every token on `/collections` but not on `/api`, and the 60 s `iat` skew applies only to `/collections` | `user_auth.ex:263-266`; `user_token.ex:104-109`; `tokens.ex:12-35`, `:98-117`, `:190-191` ("Mirror /api"); `token_matrix_test.exs:97-106` | decide |
| Both hops return the same bare 401 `{"error": "Unauthorized"}` with no `www-authenticate` header or reason, whether the token is unknown, revoked, or its owner is blocked or locked out; `/api/users` uses RFC 6750 style instead | `user_auth.ex:370-375`; `api_auth.ex:40-46`; `access_token_auth.ex:38-44`; `tokens.ex:111-114` (reasons computed, then discarded at `api_auth.ex:19-20`) | decide |
| On `/collections`, a valid token for a non-member is refused with the same 401 as a revoked token, so a user can't tell "no access" from "bad token" | `collections_controller.ex:150-158`; `collections_controller_test.exs:53-69` | decide |
| A missing or duplicated `Authorization` header, or one without the "Bearer " prefix, is treated as no token | `user_auth.ex:254-261`; `api_auth.ex:24-31` | preserve |
| `/collections` loads the user twice per request (status, then subject) | `tokens.ex:207`; `api_auth.ex:34-38`; `tokens.ex:182-184` | preserve |

### 6.3 Unreachable or dead code

| What | Where | Why unreachable |
|------|-------|-----------------|
| none | | |

### 6.4 Performance and operational limits

| What | Where | User-visible? | Disposition |
|------|-------|---------------|-------------|
| One extra `SELECT` and one `UPDATE` on `user_tokens` per `/api` request, unthrottled | `user_auth.ex:234-239` | no | preserve |
| A malformed token on `/collections` is refused with 401 and logged at warning, not a 500 | `tokens.ex:152-172`; `tokens_test.exs:247-297` | no | preserve |

### 6.5 Things seen but not understood

- profile-tokens 6.5 says `/api` does not reject accounts locked out pending confirmation. It does: `require_authenticated_api_resource/2` refuses them (`user_auth.ex:362-363`; `project_controller_test.exs:26-66`). The only remaining asymmetry is the `last_used_at` write in 6.1 row 2. Disposition: preserve (correct the view's note).
- No test drives a deleted token against `/api` end to end, and nothing asserts `last_used_at` is ever written (S03, S04 `/api` row). Disposition: preserve (add tests).
- The capability annotations `capability:api` and `capability:collections-api` named in `surfaces` don't exist yet (`annotations/capabilities/` is empty). Disposition: decide.

## 7. Not migrating

| Item | Reason | Decided by | Date |
|------|--------|------------|------|

## 8. Open questions

- Should the rebuild have one token gate for both APIs, and should it verify the signature on `/api` too (6.2 row 1)? (owner: security)
- Should refusals say why (revoked, blocked, unconfirmed, no access) (6.2 rows 2 and 3)? (owner: product)
- Should collections use count as "Last Used at" (6.1 row 1)? (owner: product)
- Who writes `capability:api` and `capability:collections-api` (6.5)? (owner: cataloguing lead)

## Proposed flows

- none. Referenced: flow-account-revocation-teardown (S05, S06), flow-require-project-mfa, flow-workflow-api-edit-conflict.

## Proposed shared

- none. Referenced: shared-local-datetime.
