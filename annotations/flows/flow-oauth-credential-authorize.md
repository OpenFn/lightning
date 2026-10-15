---
id: flow-oauth-credential-authorize
type: flow
title: Authorize an OAuth credential with a provider
status: not-started
owner:

trigger:
  entry: credentials-index                  # also project-settings-credentials and workflow-editor-inspectors; all render CredentialFormComponent
  exit: credentials-index                   # the originating page, whichever it was; the flow ends with the form showing the result, before save
  surfaces:
    - credentials-index                     # or project-settings-credentials, or workflow-editor-inspectors
    - external:oauth-provider               # second window named "oauth_authorization" (hooks/index.ts:378-384)
    - controller:oidc-callback              # GET /authenticate/callback, OidcController.new (router.ex:75); see 6.5 on the scope's /oauth/:provider/callback
    - pubsub:oauth_credential:<socket id>   # oauth_credential_helper.ex:51-53, :72-82
    - credentials-index                     # the originating LiveView's handle_info({:forward, ...}) and GenericOauthComponent
    - workflow-editor-inspectors   # added by lead (link lint)
    - project-settings-credentials   # added by lead (link lint)
    - workflow-editor-ide   # added by lead (link lint)
  reachable_when:
    - the credential form is open with an OAuth client selected, as a new credential (credentials-index S27) or an existing one being edited
    - the client is offered to this user: own or global on /credentials, shared with the project or global elsewhere (oauth_clients.ex:60-89; credential_form_component.ex:1359-1362)

inherits: []                                # the controller hop is unauthenticated and mounts no shared gate; entry views carry their own

url_params:
  - name: state
    set_by: GenericOauthComponent via the provider's redirect (generic_oauth_component.ex:70, :102, :320-326)
    effect: encrypted [socket id, component module, component id, environment name]; picks the page, component and tab that receive the code (oauth_credential_helper.ex:23-42, safety_string.ex:17-59)
  - name: code
    set_by: external:oauth-provider
    effect: authorization code exchanged by the originating page (oidc_controller.ex:75-78, generic_oauth_component.ex:123-145)
  - name: error
    set_by: external:oauth-provider
    effect: provider refusal, shown in the originating page (oidc_controller.ex:80-83, generic_oauth_component.ex:147-161)

config_variants:
  default: {}                               # read under this variant
  # Provider-side behaviour (userinfo endpoint present, introspection endpoint present, refresh token issued)
  # is OAuth client data, not instance config; scenarios name it in Given steps instead.

inventory:
  routes:
    - get /authenticate/callback  OidcController :new   # router.ex:75, pipe_through [:browser] (router.ex:67); clauses oidc_controller.ex:75-87
  events:
    - GenericOauthComponent#authorize_click   # entry handoff, also owned by credentials-index (S27)
    - GenericOauthComponent#check_scope
  js_hooks:
    - OpenAuthorizeUrl (hooks/index.ts:378-384; generic_oauth_component.ex:469)
  policies: []                               # no policy on any hop; see section 3
  workers: []
  api_endpoints: []
  emails: []
  config: []
  not_reachable_here:
    - OidcController :new clauses with a provider param (oidc_controller.ex:46-73) and :show; these are the SSO login flow
    - OauthController :new (router.ex:79); GitHub version-control connect, not this flow

related:
  - lib/lightning_web/router.ex
  - lib/lightning_web/controllers/oidc_controller.ex
  - lib/lightning_web/oauth_credential_helper.ex
  - lib/lightning/safety_string.ex
  - lib/lightning_web/route_helpers.ex
  - lib/lightning_web/live/credential_live/generic_oauth_component.ex
  - lib/lightning_web/live/credential_live/credential_form_component.ex
  - lib/lightning_web/live/credential_live/oauth_error_formatter.ex
  - lib/lightning_web/live/credential_live/index.ex
  - lib/lightning_web/live/project_live/settings.ex
  - lib/lightning_web/live/workflow_live/collaborate.ex
  - lib/lightning_web/live/components/oauth.ex
  - lib/lightning/auth_providers/oauth_http_client.ex
  - lib/lightning/credentials/oauth_validation.ex
  - lib/lightning/credentials.ex
  - lib/lightning/oauth_clients.ex
  - assets/js/hooks/index.ts
  - test/lightning_web/controllers/oidc_controller_test.exs
  - test/lightning_web/live/credential_live_test.exs
  - test/lightning_web/live/workflow_live/collaborate_test.exs
flows: []
---

## 1. Purpose

People connecting a workflow to Google Sheets, Salesforce or any other OAuth-protected system sign in
with their own provider account instead of pasting tokens. The page they started from must get back
a token that works, carries the permissions they chose, and can renew itself, or the workflow fails
later at run time with nobody watching.

## 2. What it does

1. In the credential form (on the credentials list, a project's credential settings, or the workflow editor), the user picks an OAuth client and ticks any optional permissions on top of the required ones.
2. They click "Sign in with <client>" and the provider opens in a second window, where they consent or refuse.
3. The provider sends the second window back to OpenFn, which passes the result to the original page and closes the window.
4. The original page swaps the result for a token, checks it can renew itself and has every permission asked for, and fetches the account's profile.
   - Success shows the connected account and enables Save; nothing is stored until the user saves
   - A refusal, a failed exchange, missing permissions or a missing renewal token each show their own message with a button to try again
   - If only the profile lookup fails, the token is still accepted with a note to reauthenticate
5. The user saves the form as usual to keep the credential.

**Straightforwardness: 2 of 5.** The happy path is familiar, but it depends on the original page staying exactly as it was while the second window is open, and several failure paths leave the user stuck or with a Save button that shouldn't be there.

### Most surprising behaviours

- **(2)** If the user closes the provider window, switches environment tab, or reloads the original page while signing in, the result seems to go nowhere: the page sits on "Authenticating..." forever with no cancel, or quietly shows "Sign in" again. (6.1, 6.2)
- **(2)** A token that failed the checks (missing permissions, no renewal token, no expiry) still leaves Save enabled, and saving appears to crash the form. The no-expiry case even tells the user their credential "should still work". (6.1)
- **(2)** Ticking an extra permission after signing in doesn't disable Save, so the user can save a token that lacks the permission they just asked for. (6.1)
- **(3)** The buttons on error messages all just start sign-in again, whatever they say: "Revoke and Reauthorize" revokes nothing and "Contact Support" contacts no one. (6.1)
- **(3)** The provider grants access as soon as the user consents, even if they never save, and in the workflow editor a viewer may be able to get that far, since only the save is refused. (4, 6.2)

## 3. Who can do what

No hop checks a role. The callback runs in the `:browser` pipeline with no authentication
(`router.ex:67-79`); the encrypted `state` is the only binding to a page (`oidc_controller.ex:269-280`).
Who reaches the form is decided by the entry view.

| Action | Credential owner (/credentials) | Project viewer | Project editor, admin, owner | Superuser (no row) | Support (no row) |
|--------|-------------------------------|----------------|------------------------------|--------------------|------------------|
| Start sign-in from /credentials | yes | yes (any signed-in user) | yes | yes | yes |
| Start sign-in from project settings | n/a | no, "Add new" is hidden | yes | no (cannot reach the page) | yes, when support access is on |
| Start sign-in from the workflow editor | n/a | not gated on the server (see 6.2) | yes | no (cannot reach the page) | yes, when support access is on |
| Receive the code in a page | only the page whose socket id is in `state` | same | same | same | same |

Sources: `credential_index_component.ex:91-96`, `project_users.ex:39-49`, `:162-168`; `collaborate.ex:180-187`, `:316-321`.

**Preconditions beyond role**
- The OAuth client must be offered to this user in this context (`oauth_clients.ex:60-89`).
- The originating page must still be open with the same LiveView socket and the same environment tab showing; otherwise the code reaches no component (6.1, 6.2).
- The provider must accept `RouteHelpers.oidc_callback_url()` as a redirect URI (`route_helpers.ex:15-17`, `oauth_http_client.ex:79`, `:187`).

## 4. What it touches

**Hop 1, originating page (credential form, GenericOauthComponent)**
- Reads: `oauth_clients` (already loaded with the form)
- Writes: none
- On mount, subscribes the LiveView process to `oauth_credential:<socket id>` (`generic_oauth_component.ex:14-15`, `oauth_credential_helper.ex:51-53`)
- Builds the authorize URL with encrypted state and the selected scopes (`generic_oauth_component.ex:95-121`, `oauth_http_client.ex:182-196`); click sets "Authenticating with <client>..." and pushes `open_authorize_url` (`:302-308`)

**Hop 2, external:oauth-provider**
- The user consents or refuses in the second window; the provider redirects with `code` and `state`, or `error` and `state`

**Hop 3, controller:oidc-callback**
- Reads: none (decrypts `state` with `Lightning.Vault`, `safety_string.ex:19-33`)
- Writes: none
- Broadcasts `{:forward, GenericOauthComponent, %{code | error, id, current_tab}}` on `oauth_credential:<socket id>` (`oidc_controller.ex:269-280`, `oauth_credential_helper.ex:72-78`)
- Responds 200 with a page that calls `window.close()` (`oidc_controller.ex:282-294`)

**Hop 4, pubsub to the originating page**
- `handle_info({:forward, mod, opts})` calls `send_update(mod, opts)` (`index.ex:32-36`, `settings.ex:682-686`, `collaborate.ex:388-391`)
- The component exchanges the code at the client's token endpoint, optionally introspects, normalises expiry, validates the token and granted scopes, then fetches userinfo (`generic_oauth_component.ex:123-145`, `:164-299`; `oauth_http_client.ex:73-91`, `:153-170`, `:229-245`; `credentials.ex:1383-1405`; `oauth_validation.ex:104-114`, `:138-150`)
- Hands the token to the form's `credential_bodies` for that environment and renders it in a hidden input (`generic_oauth_component.ex:172-180`, `:446-452`)

**Immediate side effects**
- Logger lines at info, warning and error for each outcome (`generic_oauth_component.ex:153-155`, `:190-192`, `:209-211`, `:239-241`, `:250-252`, `:263-265`, `:282-284`, `:295-297`, `:376-384`)
- No database write and no audit event; nothing persists until the user saves the form (credentials-index)

**Deferred side effects**
- none

**External, non-transactional effects**
- The provider records consent and issues tokens for this client; abandoning the form does not revoke them
- POST to the token endpoint, optional POST to the introspection endpoint, GET to the userinfo endpoint (`oauth_http_client.ex:73-91`, `:247-263`, `:153-170`)

**Depends on config**
- `LightningWeb.Endpoint` URL config, which forms the redirect URI every provider must allow (`route_helpers.ex:15-17`)
- `Lightning.Vault` key, which encrypts `state` (`safety_string.ex:15`)

**Product limits**
- none

## 5. Scenarios

```gherkin
Feature: Authorize an OAuth credential with a provider
  In order to connect a workflow to an OAuth-protected system without handling tokens
  As someone creating or editing an OAuth credential
  I want to sign in with the provider and come back to a working credential

  @S01 @pending
  Scenario Outline: Signing in with the provider brings the account back to the originating page
    # Value: people authorize with their own provider account and see which account they connected before saving.
    Given OAuth client "Google Sheets app" has a userinfo endpoint and is offered to me on <page>
    And I have the credential form open on <page> with "Google Sheets app" selected
    When I click "Sign in with Google Sheets app"
    Then a second window opens on the provider's authorize page
    When I consent in the second window
    Then the second window closes
    And the original page shows "Test User" and "Successfully authenticated with Google Sheets app"
    And "Save credential" is enabled
    # generic_oauth_component.ex:302-308, :123-145, :164-206, :249-258; hooks/index.ts:378-384
    # oidc_controller.ex:75-78, :269-294; index.ex:32-36; components/oauth.ex:196-207, :333-361
    # credential_live_test.exs:2871-2933 (asserts view.id == subscription id, h3 "Test User", save enabled)
    # oidc_controller_test.exs:716-729, :746-765 (asserts the broadcast and window.close)
    # collaborate_test.exs:822-923 (editor: asserts progress reaches :fetching_userinfo or :complete)

    Examples:
      | page                                   |
      | /credentials                           |
      | project settings, credentials          |
      | the workflow editor's credential modal |

  @S02 @pending
  Scenario: Optional scopes I tick are the ones requested from the provider
    # Value: people grant the provider only the permissions they chose, and can add more without editing the client.
    Given OAuth client "Google Sheets app" has mandatory scope "read" and optional scope "write"
    And I have the credential form open with "Google Sheets app" selected
    Then "read" is ticked and cannot be unticked
    When I tick "write"
    And I click "Sign in with Google Sheets app"
    Then the provider is asked for scopes "write read"
    # generic_oauth_component.ex:95-121, :310-334; components/oauth.ex:80-92; oauth_http_client.ex:182-196

  @S03 @pending
  Scenario: The provider grants fewer scopes than I chose
    # Value: a credential is never accepted without permissions its workflow will need.
    Given I chose scopes "read" and "write"
    When I consent in the second window and the provider grants only "read"
    Then the original page shows "Missing Required Permissions"
    And I see "Missing permissions: 'write'"
    And I see "Reauthorize"
    # generic_oauth_component.ex:164-168, :188, :208-216; oauth_validation.ex:138-150, :560-588
    # oauth_error_formatter.ex:146-162; credential_live_test.exs:2208-2288

  @S04 @pending
  Scenario: offline_access is not required in the granted scopes
    # Value: providers that grant offline access without echoing it in the scope list can still be connected.
    Given I chose scopes "offline_access" and "read"
    When I consent and the provider grants "read" only
    Then the original page shows the connected account
    # generic_oauth_component.ex:165-168; credential_live_test.exs:2119-2206, :2290-2372

  @S05 @pending
  Scenario: The provider returns no refresh token
    # Value: the user learns before relying on it that the credential could not renew itself.
    Given the provider does not issue a refresh token because this account already authorized the client
    When I consent in the second window
    Then the original page shows "Account Already Connected"
    And I do not see the account's name
    # oauth_validation.ex:104-114, :340-346; oauth_error_formatter.ex:74-90
    # credential_live_test.exs:1740-1858 (asserts "Account Already Connected", no "Test User", no credential)

  @S06 @pending
  Scenario: I refuse consent at the provider
    # Value: the user is told the sign-in did not complete and can start again from the same form.
    When I click "Sign in with Google Sheets app"
    And I refuse consent in the second window
    Then the second window closes
    And the original page shows "The authentication process with Google Sheets app was interrupted"
    And I see "Start Over"
    # oidc_controller.ex:80-83; generic_oauth_component.ex:147-161; oauth_error_formatter.ex:219-229
    # credential_live_test.exs:1861-1914 (broadcasts error, asserts "The authentication process with")

  @S07 @pending
  Scenario: The code exchange fails
    # Value: a failed exchange is reported as a sign-in problem, never as a revoked credential the user must go fix at the provider.
    Given the provider's token endpoint rejects the code with "invalid_grant"
    When I consent in the second window
    Then the original page shows "An error occurred during authentication with"
    And I do not see "Refresh Token Revoked"
    # generic_oauth_component.ex:220-236, :387-389; oauth_error_formatter.ex:350-358
    # credential_live_test.exs:1668-1737; and :1916-1992 for a 401 ("Your authorization with")

  @S08 @pending
  Scenario: The provider's profile endpoint fails but the token is good
    # Value: an outage on the provider's profile endpoint does not block connecting a working credential.
    Given the client's userinfo endpoint returns 500
    When I consent in the second window
    Then the original page shows "Successfully authenticated with Google Sheets app"
    And I see "reauthenticate with Google Sheets app"
    # generic_oauth_component.ex:281-290; components/oauth.ex:203-207, :223-232; credential_live_test.exs:1994-2079

  @S09 @pending
  Scenario: The new access token is rejected by the profile endpoint
    # Value: the user learns that authorizing another credential for the same account revoked this token, before saving it.
    Given the client's userinfo endpoint returns 401 for the new token
    When I consent in the second window
    Then the original page shows "Invalid Access Token"
    # generic_oauth_component.ex:261-279; oauth_error_formatter.ex:63-72

  @S10 @pending
  Scenario: A callback with a state Lightning did not issue reaches no page
    # Value: nobody can push their own provider account's code into someone else's open credential form.
    Given I have the credential form open and have clicked "Sign in with Google Sheets app"
    When "/authenticate/callback?code=abc&state=<tampered>" is requested
    Then my form still shows "Authenticating with Google Sheets app..."
    # oidc_controller.ex:75-78, :269-272; oauth_credential_helper.ex:32-42; safety_string.ex:19-33
    # Read, not run. What the requester sees is a crash, listed in 6.1.
```

## 6. Unclear value

### 6.1 Possible bugs

| What | Where | What a user sees | Disposition |
|------|-------|------------------|-------------|
| Closing the provider window, or the provider never redirecting, leaves the form on "Authenticating with <client>..." with no cancel and no retry; the error copy for this case ("This can happen if you closed the authorization window") is only shown when the provider redirects with `error` | `generic_oauth_component.ex:302-308`; `components/oauth.ex:188-191`; `oauth_error_formatter.ex:219-229` | a spinner that never ends; the user must close the modal and start over | fix |
| A token that fails validation is still sent to the form's bodies and rendered in the hidden input, and "Save credential" stays enabled; saving runs the same validation in `Credentials` and hits the unmatched `{:error, %OauthValidation.Error{}}` (credentials-index 6.1) | `generic_oauth_component.ex:172-186`, `:446-452`; `credential_form_component.ex:648-651`, `:1072-1075`; `credentials.ex:211`, `:416-436` | after S03, S05 or a missing expiry, Save is clickable and appears to crash the modal | fix |
| Changing scopes after signing in does not disable Save: the form's own `scopes_changed` is initialised false and never updated; only the OAuth component's copy changes. credentials-index S28's last step ("Save credential is disabled until I do") does not hold; its cited test asserts only the banner | `credential_form_component.ex:31`, `:1073`; `generic_oauth_component.ex:367-371`; `credential_live_test.exs:3109-3151` | Save remains enabled with a token that lacks the newly ticked scope | fix |
| Error actions all re-run sign-in regardless of their label: "Revoke and Reauthorize" revokes nothing, "Contact Support", "Continue Anyway", "Try Again Later" and "Try Again in 30 Seconds" all open the provider again | `components/oauth.ex:240-245`; `oauth_error_formatter.ex:87`, `:129`, `:185`, `:258`, `:270` | a button that does something other than what it says | fix |
| A token with no expiry is shown as a warning saying "your credential should still work", but the same check refuses it on save | `oauth_validation.ex:440-446`; `oauth_error_formatter.ex:178-188`; `credentials.ex:432-436` | told to continue, then a crash on save (row 2) | fix |
| A callback whose `state` is malformed, encrypted with another key or otherwise undecryptable raises (`url_decode64!`, `Vault.decrypt!`, or a match on `{:error, _}`) instead of answering | `oidc_controller.ex:269-272`; `oauth_credential_helper.ex:32-34`; `safety_string.ex:19-25` | a 500 error page in the second window, which stays open | fix |
| Switching to another environment tab while the provider window is open unmounts that tab's OAuth component; the callback's `send_update` targets an id that no longer exists and the code is dropped. Read, not run | `credential_form_component.ex:922-966`; `generic_oauth_component.ex:123-145` | the window closes and nothing happens; going back to the tab shows "Sign in" again | fix |

### 6.2 Quirks and implementation details

| What | Where | Disposition |
|------|-------|-------------|
| The redirect URI is the SSO login callback `/authenticate/callback`; credential callbacks are told apart from login callbacks only by having no `provider` param | `route_helpers.ex:15-17`; `router.ex:75-77`; `oidc_controller.ex:46-87` | decide |
| The callback is unauthenticated and not tied to the browser session; any client presenting a valid `state` delivers the code to that page | `router.ex:67-79`; `oidc_controller.ex:75-83` | preserve |
| Every authorize URL carries Google's `access_type=offline` and `prompt=consent`, whatever the provider | `oauth_http_client.ex:182-196` | decide |
| The PubSub topic is the LiveView socket id; reloading or navigating the originating page orphans an in-flight sign-in (noted in the helper) | `oauth_credential_helper.ex:44-53` | decide |
| A second code arriving while one is held is ignored until the user clicks sign-in again | `generic_oauth_component.ex:123-125`, `:305` | preserve |
| A callback with neither `code` nor `error`, or with `error` but no `state`, redirects the second window to the login page instead of closing it | `oidc_controller.ex:85-87` | decide |
| An introspection endpoint, when configured, overwrites `expires_at` from its `exp`; an introspection failure is logged and ignored | `oauth_http_client.ex:229-245` | preserve |
| `expires_in` is turned into an absolute `expires_at` when the token arrives | `credentials.ex:1383-1405`; `generic_oauth_component.ex:170` | preserve |
| Scope matching is case-insensitive and a superset grant is accepted | `oauth_validation.ex:560-588` | preserve |
| The provider window is always named `oauth_authorization`, so a second sign-in reuses the same window | `hooks/index.ts:381` | preserve |
| In the workflow editor the "new credential" modal opens without a server-side role check, so a project viewer could complete the provider sign-in; only save is refused. Whether the React side hides the control for viewers was not checked | `collaborate.ex:180-187`; `credential_form_component.ex:526-541` | decide |
| /credentials offers the user's own and global clients; project contexts offer project-shared and global clients, so a user's own unshared client cannot start this flow from a project | `oauth_clients.ex:60-89`; `credential_form_component.ex:1359-1362` | decide |

### 6.3 Unreachable or dead code

| What | Where | Why unreachable |
|------|-------|-----------------|
| `send_update(CredentialFormComponent, current_tab: tab)` on code and error | `generic_oauth_component.ex:127-130`, `:148-151` | the component only exists while its tab is current, so the form's tab already equals `tab` |
| `userinfo_fetch_failed` assign | `generic_oauth_component.ex:289` | never read by the template or `oauth_status` |
| `format_error({:userinfo_failed, _})`, `format_error({:invalid_credential, _})` | `oauth_error_formatter.ex:308-327` | no code produces these error shapes |

### 6.4 Performance and operational limits

| What | Where | User-visible? | Disposition |
|------|-------|---------------|-------------|
| Token and userinfo fetches run as `start_async` with no timeout of their own (also credentials-index 6.4) | `generic_oauth_component.ex:141-143`, `:198-203` | yes, a hanging provider leaves "Authenticating with ..." or "Fetching user information from ..." showing | decide |

### 6.5 Things seen but not understood

- The lead's scope and the credentials-index proposal name `/oauth/:provider/callback` (`router.ex:79`) as the callback. That route is `OauthController.new`, which only matches `provider: "github"` and handles the GitHub version-control connect (`oauth_controller.ex:7-29`). The credential flow's redirect URI is `/authenticate/callback` (`route_helpers.ex:15-17`, `oauth_http_client.ex:79`, `:187`), and this file catalogues that route instead.
- `window.open` runs from a server push after the click's round trip, not inside the click handler (`generic_oauth_component.ex:307`, `hooks/index.ts:380-382`). Whether popup blockers treat it as user-initiated was not checked.

## 7. Not migrating

| Item | Reason | Decided by | Date |
|------|--------|------------|------|

## 8. Open questions

- Should credential callbacks keep sharing `/authenticate/callback` with SSO login, or get their own route (6.2)?
- Should the subscription follow the user or session rather than the LiveView socket id, so a reload does not lose an in-flight sign-in (6.2)?
- Should provider-specific authorize parameters (`access_type`, `prompt`) move onto the OAuth client (6.2)?
- Should starting a sign-in require permission to create a credential in that context, given the provider issues tokens before save (6.2)?
- credentials-index S28 asserts Save is disabled after a scope change; fix the form (6.1) or amend that scenario?

## Proposed flows

none

## Proposed shared

none
