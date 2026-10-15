---
id: flow-sso-login
type: flow
title: Sign in through an SSO provider
status: not-started
owner:

trigger:
  entry: auth-login                          # the "via external provider" link (user_session_html/new.html.heex:56-73; user_session_controller.ex:11, :75-86)
  exit: projects-dashboard                   # or the stored return path (flow-login-return-to); auth-login on every refusal
  surfaces:
    - auth-login
    - controller:oidc-authorize              # GET /authenticate/:provider, OidcController.show (router.ex:76; oidc_controller.ex:17-40)
    - external:oidc-provider                 # the provider's authorization endpoint (handler.ex:120-126)
    - controller:oidc-callback               # GET /authenticate/:provider/callback, OidcController.new (router.ex:77; oidc_controller.ex:46-73, :89-263)
    - auth-two-factor                        # only for accounts with MFA enabled (oidc_controller.ex:250-256)
    - projects-dashboard                     # default exit (user_auth.ex:63-70, :514)
    - admin-auth-providers   # added by lead (link lint)
  reachable_when:
    - an auth provider is configured and its handler is in the node's handler cache, so the login page renders the link (user_session_controller.ex:75-86; auth_providers/store.ex:13-19); the routes themselves also build an uncached handler from the `auth_providers` row (auth_providers.ex:49-51, :91-94; store.ex:23-34)
    - the visitor is not signed in; a signed-in visitor to /authenticate/:provider is sent to /projects (oidc_controller.ex:20-21; user_auth.ex:271-279)
    - every hop is in the `:browser` scope with no authentication plug (router.ex:66-67, :75-77)

inherits:
  - shared-authenticated-session             # the :browser pipeline (fetch_current_user) on both controller hops, and its S03 gate that holds a TOTP-pending session at two-factor

url_params:
  - name: state
    set_by: controller:oidc-authorize, echoed by external:oidc-provider
    effect: 32 random bytes, url-safe base64 (oidc_controller.ex:23, :265-267); must match an entry in the session's `oidc_pending` map, which is consumed on use (oidc_controller.ex:50, :137-146)
  - name: code
    set_by: external:oidc-provider
    effect: exchanged at the provider's token endpoint for an id token (oidc_controller.ex:91; handler.ex:128-140)
  - name: error
    set_by: external:oidc-provider
    effect: any callback without `code` (consent denied, bare revisit) goes back to login with no session (oidc_controller.ex:70-73)

config_variants:
  default: {}                                                                        # no provider: the link is not rendered and the flow cannot start (user_session_controller.ex:76-78)
  sso-provider: { auth provider configured at /settings/authentication }             # read under this one
  sso-trust-unverified-email: { auth_providers.allow_unverified_email: true }        # auth_config.ex:25-29; handler.ex:36, :81; oidc_controller.ex:156-157, :212
  require-email-verification: { lightning.require_email_verification: true }         # affects 6.2 only

inventory:
  routes:
    - get /authenticate/:provider  OidcController :show              # router.ex:76
    - get /authenticate/:provider/callback  OidcController :new      # router.ex:77; clauses oidc_controller.ex:46-73
  events:
    - OidcController#show
    - OidcController#new
  js_hooks: []
  policies:
    - Lightning.Accounts.login_blocked?/1 (accounts.ex:328-332)
    - Lightning.Accounts.login_blocked_reason/1 (accounts.ex:340-345)
    - LightningWeb.UserAuth.redirect_if_user_is_authenticated/2 (user_auth.ex:271-279), called inline by show
  workers: []
  api_endpoints: []
  emails: []
  config:
    - Lightning.AuthProviders handlers (Cachex :auth_providers, store.ex:13-58; warmer cache_warmer.ex:16-30)
    - auth_providers.allow_unverified_email (auth_config.ex:29)
    - Cachex :auth_provider_jwks (handler.ex:13-14; application.ex:59-61)
    - :auth_providers_allow_insecure_loopback (tls.ex:24-36), test suite only
  not_reachable_here:
    - get /authenticate/callback  OidcController :new (router.ex:75); the redirect URI the admin form builds is always /authenticate/<name>/callback (auth_config_form.ex:47-59; form_component.ex:28-30), so this route belongs to flow-oauth-credential-authorize (oidc_controller.ex:75-87)
    - OidcController broadcast_message/2 and close_browser_window/1 (oidc_controller.ex:269-294); flow-oauth-credential-authorize
    - AuthProvidersLive.Index and FormComponent (admin-auth-providers, not catalogued yet)

related:
  - lib/lightning_web/router.ex
  - lib/lightning_web/controllers/oidc_controller.ex
  - lib/lightning_web/controllers/user_session_controller.ex
  - lib/lightning_web/controllers/user_session_html/new.html.heex
  - lib/lightning_web/controllers/user_auth.ex
  - lib/lightning_web/controllers/user_totp_controller.ex
  - lib/lightning_web/controllers/fallback_controller.ex
  - lib/lightning_web/views/error_view.ex
  - lib/lightning/auth_providers.ex
  - lib/lightning/auth_providers/handler.ex
  - lib/lightning/auth_providers/store.ex
  - lib/lightning/auth_providers/cache_warmer.ex
  - lib/lightning/auth_providers/well_known.ex
  - lib/lightning/auth_providers/tls.ex
  - lib/lightning/auth_providers/auth_config.ex
  - lib/lightning/auth_providers/auth_config_form.ex
  - lib/lightning/accounts.ex
  - test/lightning_web/controllers/oidc_controller_test.exs
  - flow-oauth-credential-authorize       # same controller module; see section 1 for what differs
flows:
  - flow-login-return-to                  # the landing hop
---

## 1. Purpose

Organisations that run their own identity provider want their staff to sign in to Lightning with
that identity instead of a separate Lightning password. This flow sends a signed-out visitor from the
login page to the provider and back, checks that the answer really came from the provider for this
login, matches the provider's verified email to an existing Lightning account, and signs them in,
through two-factor if the account has it. Getting it wrong either locks SSO users out, or lets a
forged or replayed provider response sign someone in as another person.

It differs from flow-oauth-credential-authorize, which shares OidcController and the `/authenticate`
routes: that flow's `state` is an encrypted pointer to a LiveView, its callback is the provider-less
`/authenticate/callback`, and it broadcasts the code over PubSub and closes a popup without signing
anyone in (oidc_controller.ex:75-83, :269-294). This flow's `state` is a random value bound to the
browser session, and its callback signs the user in.

## 2. What it does

1. A signed-out visitor clicks "via external provider" on the login page and is sent to their organisation's sign-in page.
2. They sign in there and are sent back to Lightning, which checks the answer really came from the provider for this login.
   - Anything that doesn't check out (a wrong or reused link, a bad token, an email the provider hasn't verified) goes back to the login page with a generic "couldn't sign you in"
   - Cancelling at the provider, or the provider being unreachable, also lands back on the login page
3. Lightning matches the provider's verified email to an existing account.
   - No matching account, a disabled account or one scheduled for deletion each go back to the login page with their own message
4. Users without two-factor are signed in; users with two-factor go through the code step first.
5. They land on the page they originally asked for, or the projects list, kept signed in for 60 days.

**Straightforwardness: 3 of 5.** The journey is the usual single sign-on dance, and most of the many checks just make it safe; the surprises are in how accounts are matched and what different failures show.

### Most surprising behaviours

- **(2)** Accounts are matched by email address alone. If the provider reassigns an address to someone new, that person gets into the old owner's Lightning account. (3, 8)
- **(3)** "Keep me logged in for 60 days" is always on for single sign-on and the user is never asked, even on a shared computer. (S01, 6.2)
- **(3)** Most failures share one vague message, but unknown, disabled and scheduled-for-deletion accounts each get a specific one, which tells anyone with a provider login whether an account exists for that email. (6.2)
- **(3)** If the provider rejects Lightning's own credentials, the user seems to get a dead-end error page showing the provider's technical error instead of the login page. (6.1)
- **(3)** On a setup with several servers, removing the provider in admin may leave single sign-on working on some servers for up to 30 minutes. (6.1)

## 3. Who can do what

Sources: `oidc_controller.ex:17-40`, `:46-73`, `:89-105`, `:227-263`; `accounts.ex:318-345`.
No project role applies; the gate is the account and the provider's assertion.

| Action | Account, no MFA | Account with MFA | Disabled account | Scheduled for deletion | No Lightning account | Already signed in |
|--------|-----------------|------------------|------------------|------------------------|----------------------|-------------------|
| See "via external provider" | yes (sso-provider) | yes | yes | yes | yes | n/a, login page redirects (auth-login) |
| Start the flow at /authenticate/:provider | yes | yes | yes | yes | yes | no, sent to /projects (`oidc_controller.ex:20-21`) |
| Be signed in by the callback | yes | after a valid code at two-factor | no, "This user account is disabled" (`oidc_controller.ex:242-248`; `user_auth.ex:42`) | no, "This user account is scheduled for deletion" (`user_auth.ex:44-45`) | no, "Could not find user account" (`oidc_controller.ex:228-232`) | n/a |

**Preconditions beyond role**
- The callback's `state` must match one this browser session was issued and has not used (`oidc_controller.ex:50`, `:137-146`).
- The id token must verify against the provider's published keys with an asymmetric algorithm, name the discovered issuer, list this client in `aud` (and in `azp` when present or when `aud` has several entries), be unexpired, and carry the nonce stored with the state (`handler.ex:179-184`, `:194-203`, `:300-338`).
- The email must be asserted verified by the provider, from the id token or from a userinfo response bound to the same `sub`, unless the provider is marked trusted for unverified emails (`oidc_controller.ex:148-225`).
- Discovery, token, JWKS and userinfo endpoints must be HTTPS with a verified chain (`tls.ex:10-37`; `well_known.ex:31-37`, `:52-56`; `handler.ex:131-139`, `:152-154`, `:279-283`).
- The account is matched by email only (case-insensitive citext column); no provider subject is stored (`accounts.ex:318-320`). See section 8.
- A disabled account with MFA is refused before two-factor (`oidc_controller.ex:242-256`; `oidc_controller_test.exs:238-253`).

## 4. What it touches

**Reads**
- auth-login: handler cache only (`user_session_controller.ex:75-86`; `store.ex:13-19`)
- controller:oidc-authorize: handler cache, else the `auth_providers` row and the provider's discovery document (`auth_providers.ex:49-51`, `:91-94`; `store.ex:23-41`; `handler.ex:94-113`; `well_known.ex:31-37`); `users` and `user_tokens` for a current session (`user_auth.ex:175-206`)
- controller:oidc-callback: session `oidc_pending` (`oidc_controller.ex:137-141`); the provider's token endpoint, JWKS (cached 10 minutes) and, when needed, userinfo (`handler.ex:128-163`, `:207-233`); `users` by email (`accounts.ex:318-320`); session `user_return_to` (`user_auth.ex:64`, `:97`)

**Writes**
- controller:oidc-authorize: session `oidc_pending` (`state => nonce`, at most five entries) (`oidc_controller.ex:115-135`); handler cache entry with a 30 minute TTL when it was built from the row (`store.ex:26-28`, `:49-52`)
- controller:oidc-callback, every outcome: the used `state` is removed from `oidc_pending` before anything else runs (`oidc_controller.ex:50`, `:71`)
- controller:oidc-callback, on success: `user_tokens` insert, a "session" token (`user_auth.ex:28-31`; `accounts.ex:985-989`); session renewed and cleared except `user_return_to`, then `user_token` set (`user_auth.ex:54-58`, `:96-103`)
- no MFA: remember-me cookie, signed, 60 days, always (`oidc_controller.ex:258-260`; `user_auth.ex:19-21`, `:72-75`); `user_return_to` deleted (`user_auth.ex:68`)
- MFA: session `user_totp_pending` (`user_auth.ex:478-480`); remember-me is passed on as `user[remember_me]=true` and written by auth-two-factor after the code (`oidc_controller.ex:254-256`; `user_totp_controller.ex:9-14`, `:17-24`)

**Immediate side effects**
- Flash on every refusal: "We couldn't sign you in. Please try again." for state, token, signature, claim and email-verification failures and for a provider that can't be built (`oidc_controller.ex:96-111`); the specific copy in section 3 for unknown, disabled and scheduled accounts
- No audit event, email or PubSub broadcast at any hop

**Deferred side effects**
- none

**External, non-transactional effects**
- Redirect to the provider's authorization endpoint with `scope=openid email profile`, `state` and `nonce` (`handler.ex:11`, `:120-126`)
- Token request carrying the client secret and the code (`handler.ex:128-140`); JWKS and userinfo GETs with 10 second timeouts (`handler.ex:156-162`, `:285-297`); discovery fetch when a handler is built (`handler.ex:94-113`)

**Depends on config**
- `sso-provider`: the flow exists only when a provider is configured; the login page shows the link only when a handler is cached (`user_session_controller.ex:75-86`)
- `sso-trust-unverified-email`: an id token email with no `email_verified` claim is accepted without a userinfo call (`oidc_controller.ex:154-157`, `:212`)

**Product limits**
- none

## 5. Scenarios

```gherkin
Feature: Sign in through an SSO provider
  In order to use one identity across my organisation's tools
  As a Lightning user whose organisation runs an identity provider
  I want to sign in to Lightning through that provider

  @S01 @pending @variant:sso-provider
  Scenario: A user signs in through the provider and lands on the projects list
    # Value: SSO users get in without a Lightning password.
    Given an external authentication provider "acme" is configured
    And "amara@example.org" is a Lightning user without MFA
    And I am not logged in
    When I click "via external provider" on the login page
    Then I am at the provider's sign-in page
    When I sign in at the provider as "amara@example.org" with a verified email
    Then I am on "/projects" as "amara@example.org"
    And the flow ends on projects-dashboard
    And a remember-me cookie valid for 60 days is set
    # user_session_controller.ex:75-86; oidc_controller.ex:17-29, :89-94, :227-235, :257-261; user_auth.ex:63-75
    # oidc_controller_test.exs:46-59 (redirect to authorize url with stored state and nonce), :93-104 (lands on /projects with a session token)

  @S02 @pending @variant:sso-provider
  Scenario: Signing in through the provider returns to the page the user asked for
    # Value: deep links work the same for SSO users as for password users.
    Given the flow "flow-login-return-to" stored the run page I opened while signed out
    When I complete this flow as a user without MFA
    Then the flow "flow-login-return-to" continues to that run page
    # oidc_controller.ex:258-260; user_auth.ex:63-70, :96-103; flow-login-return-to S06 owns the journey

  @S03 @pending @variant:sso-provider
  Scenario: An MFA account must pass two-factor after the provider
    # Value: single sign-on doesn't bypass the account's second factor.
    Given "amara@example.org" has MFA enabled
    When I sign in at the provider as "amara@example.org"
    Then I am on "/users/two-factor"
    When I open "/projects" instead
    Then I am sent back to "/users/two-factor"
    When I enter a valid authentication code
    Then I am on "/projects"
    # oidc_controller.ex:250-256; user_auth.ex:478-480; user_totp_controller.ex:17-24
    # oidc_controller_test.exs:106-124; auth-two-factor S13 asserts the arrival; shared-authenticated-session S03 owns the hold

  @S04 @pending @variant:sso-provider
  Scenario: A provider identity with no Lightning account is refused
    # Value: having an identity at the provider does not create or grant a Lightning account; access stays with whoever provisions users.
    Given no Lightning user has the email "chen@example.org"
    When I sign in at the provider as "chen@example.org" with a verified email
    Then I am on the login page
    And I see "Could not find user account"
    And I am not signed in
    # oidc_controller.ex:227-232; oidc_controller_test.exs:272-285

  @S05 @pending @variant:sso-provider
  Scenario Outline: Disabled and scheduled-for-deletion accounts can't sign in through the provider
    # Value: disabling or scheduling an account for deletion cuts off SSO access too, even when the provider still vouches for the person.
    Given "amara@example.org" is <state>
    And her account <mfa> MFA enabled
    When I sign in at the provider as "amara@example.org"
    Then I am on the login page
    And I see "<message>"
    And I am not signed in and not waiting on two-factor

    Examples:
      | state                     | mfa      | message                                     |
      | disabled                  | does not | This user account is disabled               |
      | disabled                  | does     | This user account is disabled               |
      | scheduled for deletion    | does not | This user account is scheduled for deletion |
    # oidc_controller.ex:241-248; accounts.ex:328-345; user_auth.ex:41-45
    # oidc_controller_test.exs:224-236, :238-253 (asserts redirect and no session only), :255-270

  @S06 @pending @variant:sso-provider
  Scenario Outline: A callback whose state this browser was not issued is refused
    # Value: an attacker can't log a victim into the attacker's account (login CSRF) by getting them to open a crafted callback link.
    Given I started a sign-in through the provider on this browser
    When the provider callback arrives with <state>
    Then I am on the login page
    And I see "We couldn't sign you in. Please try again."
    And I am not signed in

    Examples:
      | state                         |
      | no state parameter            |
      | a state this session never saw |
    # oidc_controller.ex:50, :90, :137-146; oidc_controller_test.exs:379-394, :396-414

  @S07 @pending @variant:sso-provider
  Scenario: A callback URL can be used only once
    # Value: a callback URL leaked from browser history, logs or a referrer can't be replayed to sign in again.
    Given I signed in through the provider and then logged out
    When I open the same callback URL again
    Then I am on the login page
    And I see "We couldn't sign you in. Please try again."
    # oidc_controller.ex:47-50, :137-141 (state popped before verification); user_auth.ex:96-103 (logout clears the session)
    # no test replays a used callback

  @S08 @pending @variant:sso-provider
  Scenario Outline: Only an id token the provider minted for this login and this client signs anyone in
    # Value: a forged, replayed or misdirected token can't sign someone in as another user.
    Given I started a sign-in through the provider
    When the provider returns an id token <defect>
    Then I am on the login page
    And I see "We couldn't sign you in. Please try again."
    And I am not signed in

    Examples:
      | defect                                         |
      | whose nonce is from a different login          |
      | signed with a key the provider doesn't publish |
      | issued for a different client                  |
      | from a different issuer                        |
      | that has expired                               |
    # handler.ex:179-184, :194-203, :255-275, :300-341; oidc_controller.ex:92
    # oidc_controller_test.exs:416-430, :432-449, :451-465, :467-481, :483-497

  @S09 @pending @variant:sso-provider
  Scenario Outline: A provider email that isn't verified can't claim a Lightning account
    # Value: someone who can merely type another person's address into their provider profile can't take over that person's Lightning account.
    Given "amara@example.org" is a Lightning user
    When I sign in at the provider and it returns "amara@example.org" <condition>
    Then I am on the login page
    And I see "We couldn't sign you in. Please try again."
    And I am not signed in

    Examples:
      | condition                                                              |
      | with email_verified false in the id token                              |
      | with no email_verified claim anywhere                                  |
      | only in userinfo, marked unverified                                    |
      | only in userinfo, for a different subject than the id token            |
      | in the id token, with userinfo vouching for a different address        |
    # oidc_controller.ex:148-225; oidc_controller_test.exs:499-515, :540-557, :517-538, :588-607, :202-218

  @S10 @pending @variant:sso-provider
  Scenario: A verified flag from userinfo completes a login the id token left open
    # Value: providers that put email_verified only in userinfo still work, without trusting an unbound response.
    Given "amara@example.org" is a Lightning user
    When the provider's id token carries "amara@example.org" without email_verified
    And its userinfo for the same subject says the email is verified
    Then I am on "/projects" as "amara@example.org"
    # oidc_controller.ex:159-183, :198-207, :219-225
    # oidc_controller_test.exs:638-658, :126-145, :147-160, :162-179

  @S11 @pending @variant:sso-trust-unverified-email
  Scenario: A provider marked trusted signs users in without an email_verified claim
    # Value: single-tenant providers that never emit email_verified can still be used, by an explicit operator choice.
    Given the provider "acme" is marked to allow unverified emails
    And "amara@example.org" is a Lightning user
    When the provider's id token carries "amara@example.org" with no email_verified claim
    Then I am on "/projects" as "amara@example.org"
    # auth_config.ex:25-29; oidc_controller.ex:154-157, :212; oidc_controller_test.exs:559-586

  @S12 @pending @variant:sso-provider
  Scenario Outline: Cancelling at the provider returns to a working login page
    # Value: someone who backs out of SSO can still log in with a password instead of hitting an error page.
    Given I started a sign-in through the provider
    When the provider returns to the callback <with>
    Then I am on the login page
    And I am not signed in

    Examples:
      | with                                  |
      | error "access_denied"                 |
      | neither a code nor an error           |
    # oidc_controller.ex:67-73; oidc_controller_test.exs:609-626, :628-636

  @S13 @pending @variant:sso-provider
  Scenario Outline: A provider that can't be reached fails back to the login page
    # Value: a provider outage leaves people on a login page where password login still works, not on a server error.
    Given the provider's <endpoint> is unreachable
    When I <step>
    Then I am on the login page
    And I am not signed in

    Examples:
      | endpoint           | step                             |
      | discovery document | click "via external provider"    |
      | discovery document | return from the provider         |
      | token endpoint     | return from the provider         |
    # oidc_controller.ex:31-38, :52-63, :96-99; handler.ex:94-113, :135
    # oidc_controller_test.exs:79-87, :296-310, :330-349

  @S14 @pending @variant:sso-provider
  Scenario: A provider endpoint served over plain http can't sign anyone in
    # Value: a network attacker can't substitute keys, tokens or claims on an unencrypted hop to forge a login.
    Given the provider's token endpoint is configured as an http URL
    When I return from the provider
    Then I am on the login page
    And I see "We couldn't sign you in. Please try again."
    # handler.ex:131-139 (:insecure_token_endpoint); tls.ex:29-37; well_known.ex:52-56 (discovery); handler.ex:152-154 (userinfo), :279-283 (JWKS)
    # no controller test drives a non-loopback http endpoint; the suite allows loopback http (tls.ex:24-28)

  @S15 @pending @variant:sso-provider
  Scenario: Two sign-ins started on one browser don't break each other
    # Value: double-clicking the button or starting SSO in two tabs doesn't strand the user with an invalid-state error.
    Given I started a sign-in through the provider in one tab
    And I started another in a second tab
    When I finish the first one at the provider
    Then I am on "/projects"
    # oidc_controller.ex:113-135; oidc_controller_test.exs:660-692, :351-377 (newest state survives the cap)
```

## 6. Unclear value

### 6.1 Possible bugs

| What | Where | What a user sees | Disposition |
|------|-------|------------------|-------------|
| A provider error body from the token endpoint is not sent back to login: a map body renders the "Authorization Error" page with the provider's error fields, a string body returns raw JSON `{"error": ...}`. The comment above says failures shouldn't reveal which check tripped | `oidc_controller.ex:100-103`; `fallback_controller.ex:65-76`; `error_view.ex:27-39`; asserted by `oidc_controller_test.exs:312-328` | a dead-end page showing e.g. "invalid_client / No client credentials found." instead of the login page | decide |
| Removing or renaming a provider clears only the cache of the node that served the admin request; other nodes keep the old handler for up to 30 minutes, and the callback uses the cached handler | `form_component.ex:124-126`; `auth_providers.ex:33-41`, `:77-79`; `store.ex:23-41`, `:49-52` | on a multi-node install, SSO keeps working (and the login link keeps showing) on some nodes after an admin removed the provider | fix |

### 6.2 Quirks and implementation details

| What | Where | Disposition |
|------|-------|-------------|
| "Keep me logged in for 60 days" is always on for SSO logins; the visitor never sees the choice | `oidc_controller.ex:255`, `:260`; `user_auth.ex:19-21` | decide |
| Refusal copy differs by account state ("Could not find user account", "disabled", "scheduled for deletion") while every other failure shares one generic message, so a verified provider identity learns whether and in what state a Lightning account exists for its email | `oidc_controller.ex:96-99`, `:228-248` | decide |
| A provider name with no `auth_providers` row renders the 404 page on both hops | `oidc_controller.ex:34-35`, `:59-60`; `store.ex:36-37`, `:64-66`; `oidc_controller_test.exs:72-77`, `:287-294` | preserve |
| A signed-in visitor to `/authenticate/:provider` is sent to `/projects`; the callback has no such check | `oidc_controller.ex:20-21`; `oidc_controller_test.exs:61-70` | preserve |
| A verified email from the provider does not mark an unconfirmed Lightning account confirmed; under require-email-verification such an account is signed in and then held by the confirmation lockout | `oidc_controller.ex:227-263`; shared-authenticated-session S04 | decide |
| When `oidc_pending` holds five entries the oldest are not necessarily evicted: eviction drops in map order | `oidc_controller.ex:126-135` | preserve |
| Signing in (or a password login in another tab) renews the session, which discards every other in-flight SSO state | `user_auth.ex:96-103` | preserve |
| A request to the provider-less `/authenticate/callback` carrying `code` and an SSO-style random `state` is treated as a credential callback and fails decrypting the state; only reachable by editing a URL, since the admin form always builds `/authenticate/<name>/callback` | `oidc_controller.ex:75-78`, `:269-271`; `oauth_credential_helper.ex:32-42`; `safety_string.ex:19-23`; `auth_config_form.ex:47-59` | decide |
| The provider's scope is fixed at "openid email profile" | `handler.ex:11` | preserve |

### 6.3 Unreachable or dead code

| What | Where | Why unreachable |
|------|-------|-----------------|
| `{:ok, :not_found}` clause in `Store.get_handler/2` | `store.ex:36-37` | nothing in lib writes `:not_found` into the handler cache; a missing provider reaches the controllers' 404 branch through the finder instead (`store.ex:26-33`; `handler.ex:92`; `oidc_controller.ex:34-35`, `:59-60`) |

### 6.4 Performance and operational limits

| What | Where | User-visible? | Disposition |
|------|-------|---------------|-------------|
| At most five in-flight SSO states per browser session | `oidc_controller.ex:132-135` | only with six or more unfinished attempts, where an older tab's callback is refused | preserve |
| JWKS cached 10 minutes per `jwks_uri`, refetched once when a token names an unknown `kid` | `handler.ex:13-14`, `:207-238` | no | preserve |
| JWKS and userinfo requests time out after 10 seconds | `handler.ex:157`, `:286` | yes, a slow provider fails the login back to the login page | preserve |
| Handler cache TTL 30 minutes; warmer reloads the single provider row every 30 minutes (moduledoc says 30 seconds) | `store.ex:50`; `cache_warmer.ex:2-3`, `:16-30` | yes, see auth-login 6.4 | preserve |

### 6.5 Things seen but not understood

- The lead's scope names `/authenticate/callback` as a possible SSO return. In the code the only SSO callback is `/authenticate/:provider/callback`; the provider-less route is the credential flow's (see 6.2 row and `not_reachable_here`). No configuration path was found that sends an SSO response to the provider-less route.
- `Handler.get_userinfo/2` raises on a non-200 or plaintext endpoint and the caller rescues to an empty map (`handler.ex:152-162`; `oidc_controller.ex:201-207`), so a userinfo outage reads as an unverified email rather than as a provider outage. Same user-visible message either way.

## 7. Not migrating

| Item | Reason | Decided by | Date |
|------|--------|------------|------|

## 8. Open questions

- Should SSO accounts be linked by the provider's `sub` rather than by email alone, so an address reassigned at the provider can't inherit a Lightning account (section 3)? (owner: security)
- Should refusals for unknown, disabled and scheduled accounts share the generic message (6.2)? (owner: security)
- Should a token-endpoint error return to the login page like every other failure (6.1)? (owner: security)
- Should SSO logins offer the "keep me logged in" choice instead of forcing 60 days (6.2)? (owner: product)
- Should a provider-verified email confirm an unconfirmed Lightning account (6.2)? (owner: product)
- Should the rebuild support more than one provider at once; the store and the routes are keyed by name but the login page and warmer handle one (auth-login 6.2; `cache_warmer.ex:16-30`)? (owner: product)

## Proposed flows

none. Referenced: flow-login-return-to (the landing hop, its S06), flow-oauth-credential-authorize (shares OidcController and the `/authenticate` routes). Admin configuration of providers belongs to `admin-auth-providers`, not catalogued yet; 6.1 row 2 should move there when it is.

## Proposed shared

none. Referenced: shared-authenticated-session (the `:browser` pipeline on both controller hops and its S03 two-factor hold in S03).

## Summary

- 15 scenarios (S01 to S15), all `@pending`; S11 tagged `@variant:sso-trust-unverified-email`, the rest `@variant:sso-provider`.
- Section 6: 6.1 two, 6.2 nine, 6.3 one, 6.4 four, 6.5 two.
- Flows referenced: flow-login-return-to, flow-oauth-credential-authorize; none proposed.
- Shared referenced: shared-authenticated-session; none proposed.
- Unsure: `/authenticate/callback` as an SSO return (6.5); S07 and S14 have no test; the 6.3 clause may be reachable through a cache write outside lib.
