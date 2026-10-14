---
id: admin-auth-providers
type: view
title: Admin › Authentication (SSO provider)
status: not-started
owner:

trigger:
  old_route: /settings/authentication (live_action :edit) and /settings/authentication/new (live_action :new)   # router.ex:282-283
  new_route:
  old_route_disposition: unchanged
  reachable_when:
    - shared-admin-space admits the viewer (superuser only; `on_mount {LightningWeb.Hooks, :ensure_admin}` at `auth_providers/index.ex:7`)
    - /settings/authentication renders only when an `auth_providers` row exists; otherwise it replaces itself with /settings/authentication/new (`index.ex:24-40`)
    - the admin menu item "Authentication" links straight to /new (shared-admin-space 6.2)

inherits:
  - shared-admin-space              # gate (its S02 row /settings/authentication, S03), settings layout and side menu with "Authentication" current (its S01; `index.ex:15-16`)
  - shared-authenticated-session    # session gates before the admin gate
  - shared-flash-messages           # admin toasts that stay until clicked (its S07); this view also renders its own toast pair (`form_component.ex:295-296`), owned here

url_params: []

config_variants:
  default: {}                                                                   # production: discovery, JWKS and userinfo must be https (tls.ex:29-49). Read under this one.
  insecure-loopback: { lightning.auth_providers_allow_insecure_loopback: true }  # config/dev.exs:128, config/test.exs:197; http to localhost/127.0.0.1/::1 is accepted. The live tests run under this one.

inventory:
  routes:
    - live /settings/authentication  AuthProvidersLive.Index :edit       # router.ex:282
    - live /settings/authentication/new  AuthProvidersLive.Index :new    # router.ex:283
  events:
    - AuthProvidersLive.FormComponent#validate     # form_component.ex:47-62
    - AuthProvidersLive.FormComponent#save         # form_component.ex:65-101
    - AuthProvidersLive.FormComponent#test         # form_component.ex:104-121
    - AuthProvidersLive.FormComponent#disable      # form_component.ex:124-132
    - lv:clear-flash (component-targeted toasts)   # form_component.ex:295-296; live_helpers.ex:18-44
  js_hooks: []
  policies:
    - Lightning.Policies.Users :access_admin_space via LightningWeb.Hooks :ensure_admin (owned by shared-admin-space)
  workers: []
  api_endpoints: []
  emails: []
  config:
    - :lightning, :auth_providers_allow_insecure_loopback (tls.ex:43-49)
    - :lightning, :auth_providers_store (auth_providers.ex:96-103), test seam only
    - Cachex :auth_providers with Lightning.AuthProviders.CacheWarmer (application.ex:51-57; cache_warmer.ex:16-30)
  not_reachable_here:
    - Lightning.AuthProviders.build_handler/2 and WellKnown.fetch!/1 (auth_providers.ex:81-89; well_known.ex:39-47); no caller in lib, see 6.3
    - Lightning.AuthProviders.get_handler/1, Handler.authorize_url/3, get_token/2, get_userinfo/2, verify_id_token/3 (handler.ex:115-163, :174-184); used by flow-sso-login, not by this view
    - Lightning.AuthProviders.OauthHTTPClient (auth_providers/oauth_http_client.ex); credential OAuth, not SSO

related:
  - auth-login                      # "via external provider" appears only when a handler is cached (user_session_controller.ex:75-86); its S17, S18
  - shared-admin-space
flows:
  - flow-sso-login                  # every sign-in through the provider configured here; its 6.1 row 2 (single-node cache clear) is carried here as 6.1 row 1
---

## 1. Purpose

Superusers configure the one external OpenID Connect provider that lets people with existing
Lightning accounts sign in with their organisation's identity instead of a Lightning password. They
enter the provider's discovery URL and client credentials, copy the callback URL into the provider,
check that the discovery document works, and later edit or remove the configuration. A wrong setting
here either locks every SSO user out at once, or, through the "trust unverified emails" switch or a
plaintext endpoint, lets someone who is not the account holder sign in as them.

## 2. What it does

- Superusers with no provider configured land on an empty provider form
- Superusers create a provider with name, discovery URL, client ID, client secret and redirect host
- Superusers see the redirect URI to register with the provider, built from the host and name
- Superusers can't save a provider with a missing field or a malformed name
- Superusers test that the discovery document is reachable and usable before relying on it
- Superusers can't get a passing test from a plaintext discovery URL
- Superusers edit the existing provider, and sign-ins use the new settings
- Superusers choose whether to trust unverified emails from the provider (off by default)
- Superusers remove the provider, which turns off SSO

## 3. Who can do what

Sources: gate from shared-admin-space (`policies/users.ex:19-21`, `hooks.ex:40-53`); actions from `form_component.ex:47-132`, `:196-208`, `:272-290`. No project role applies.

| Action | Signed out | Regular user | Support user | Superuser |
|--------|-----------|--------------|--------------|-----------|
| See the page (either route) | no | no | no | yes |
| Create a provider | no | no | no | yes |
| Test the discovery URL | no | no | no | yes |
| Edit the provider | no | no | no | yes |
| Toggle "Trust unverified emails from this provider" | no | no | no | yes |
| Remove the provider | no | no | no | yes |

**Preconditions beyond role**
- Edit and Remove need an existing `auth_providers` row; without one /settings/authentication replaces itself with /new (`index.ex:24-40`), and Remove renders only when the provider has an id (`form_component.ex:272`).
- Save is enabled only while the form is valid (`form_component.ex:198`).
- The Test button renders only while the form is valid and its state is unknown (`form_component.ex:42`, `:60`, `:318-330`).
- Under `default`, a passing Test needs an https discovery URL (`well_known.ex:31-37`, `:52-56`; `tls.ex:29-41`).

## 4. What it touches

**Reads**: `auth_providers` (the single row, `auth_providers.ex:14-16`); the endpoint URL for the default redirect host (`index.ex:42-48`).

**Writes**
- `auth_providers` insert (`auth_providers.ex:27-31`), update (`:33-41`), delete (`:43-45`)
- the `:auth_providers` Cachex entry on the node that served the request: replaced on update (`auth_providers.ex:37`, `:61-65`; `store.ex:49-52`), deleted on remove (`form_component.ex:125`; `store.ex:56-58`); not written on create (`auth_providers.ex:27-31`)

**Immediate side effects** (in the same request)
- Flash "Authentication Provider created." then navigate to /settings/authentication (`form_component.ex:75-82`)
- Flash "Authentication Provider updated." (`form_component.ex:91-95`)
- Flash "Authentication Provider removed" then navigate to /settings/authentication/new (`form_component.ex:128-131`)
- Error flash with the discovery error on a failed Test (`form_component.ex:113-120`)
- Audit: none; no audit event is written for create, update or remove (`auth_providers.ex:27-45`)
- Email: none. PubSub: none.

**Where a write here shows up elsewhere**
- Login page: "via external provider" shows only when a handler is in the node's cache (`user_session_controller.ex:75-86`; auth-login S17, S18)
- Every SSO sign-in reads the cached handler or rebuilds it from the row (flow-sso-login; `store.ex:23-42`)
- `allow_unverified_email` decides whether a provider email without `email_verified` can claim an account (`oidc_controller.ex:156-157`, `:212`; flow-sso-login S11)
- The name is part of the callback path `/authenticate/<name>/callback` that the provider must have registered (`form_component.ex:28-30`; `router.ex:77`)
- Existing sessions of SSO users are not touched by any action here

**Deferred side effects** (later, elsewhere)
- Each node's cached handler expires after 30 minutes and the warmer reloads the single row every 30 minutes (`store.ex:50`; `cache_warmer.ex:16-30`); until then other nodes keep the previous configuration (6.1)

**External, non-transactional effects**
- GET of the discovery document on Test (`auth_config_form.ex:99-114`; `well_known.ex:31-37`) and on every successful update, when the new handler is built (`auth_providers.ex:37`; `handler.ex:94-113`); the update is committed whether or not that fetch succeeds

**Depends on config**
- `:auth_providers_allow_insecure_loopback` (`tls.ex:43-49`; set in `config/dev.exs:128`, `config/test.exs:197`)

**Product limits**
- One provider per instance; the page, warmer and login page handle a single row (`auth_providers.ex:14-16`; `cache_warmer.ex:22-30`; `user_session_controller.ex:80-85`)

## 5. Scenarios

```gherkin
Feature: SSO provider configuration
  In order to let staff sign in with their organisation's identity
  As a superuser
  I want to create, test, edit and remove the external OpenID Connect provider

  @S01 @pending
  Scenario: With no provider, the page opens an empty provider form
    # Value: an admin following any link to the authentication settings lands on a form they can fill, not an error.
    Given I am a superuser
    And no authentication provider is configured
    When I visit "/settings/authentication"
    Then I am on "/settings/authentication/new"
    And I see empty "Name", "Discovery URL", "Client ID" and "Client Secret" fields
    And I do not see a "Remove" button
    # index.ex:24-40 (push_navigate replace to :new), :42-48; form_component.ex:272
    # auth_providers_live_test.exs:12-21 (asserts the redirect and the admin menu)

  @S02 @pending
  Scenario: A superuser creates a provider
    # Value: an instance can offer SSO without a deploy or a config change.
    Given I am a superuser on "/settings/authentication/new"
    When I fill in name "acme-idp", a discovery URL, client ID "client-id" and client secret "client-secret"
    And I click "Save"
    Then I see "Authentication Provider created."
    And I am on "/settings/authentication"
    And the form shows provider "acme-idp"
    And a "Remove" button is shown
    # form_component.ex:65-86; auth_providers.ex:27-31; index.ex:24-33
    # auth_providers_live_test.exs:83-92, :108-117

  @S03 @pending
  Scenario: The redirect URI to register is shown as the form is filled
    # Value: the admin registers exactly the callback URL Lightning will use, so the provider doesn't reject the first sign-in.
    Given I am a superuser on "/settings/authentication/new"
    While the form is incomplete
    Then the "Redirect URI" box shows the redirect host followed by "…" and is greyed out
    When I fill in every required field with name "acme-idp" and redirect host "https://lightning.example.org"
    Then the "Redirect URI" box shows "https://lightning.example.org/authenticate/acme-idp/callback"
    # form_component.ex:240-270, :28-30; auth_config_form.ex:47-66; router.ex:77
    # auth_providers_live_test.exs:185-193 (asserts the preview after an edit)

  @S04 @pending
  Scenario Outline: An incomplete or malformed provider can't be saved
    # Value: a provider that could never sign anyone in, or whose callback path can't be routed, is not stored.
    Given I am a superuser on "/settings/authentication/new"
    When I enter <input>
    Then I see "<error>" under the <field> field
    And the "Save" button is disabled
    Examples:
      | input                         | field         | error                                                                                     |
      | an empty name                 | Name          | can't be blank                                                                            |
      | name "Acme IdP"               | Name          | must be lower-case and only contain alphanumeric, dash and underscore characters          |
      | discovery URL "acme"          | Discovery URL | must be a valid HTTP/s URL                                                                |
      | an empty client secret        | Client Secret | can't be blank                                                                            |
    # auth_config_form.ex:21, :29-45; form_component.ex:47-62, :198
    # auth_providers_live_test.exs:76-81 (blank name only)

  @S05 @pending
  Scenario: Testing a working discovery URL passes
    # Value: the admin knows the provider's discovery document is reachable and usable before users depend on it.
    Given I am a superuser with a valid provider form
    And the discovery URL serves a document with authorization and token endpoints
    When I click "Test"
    Then the button shows "Success"
    When I change any field
    Then the button shows "Test" again
    # form_component.ex:104-112, :47-62, :301-333; auth_config_form.ex:68-114; handler.ex:343-358
    # auth_providers_live_test.exs:97-106, :169-170 (run under insecure-loopback)

  @S06 @pending
  Scenario Outline: Testing a broken discovery URL says why it failed
    # Value: the admin can fix the configuration instead of learning from users that SSO is broken.
    Given I am a superuser with a valid provider form
    And the discovery URL <problem>
    When I click "Test"
    Then I see the error "<message>"
    And the button shows "Failed"
    And I see "<message>" under the Discovery URL field
    Examples:
      | problem                                         | message                                                              |
      | returns a body that is not JSON                 | error parsing .well-known                                            |
      | refuses the connection                          | could not connect to discovery endpoint                              |
      | returns JSON with no authorization endpoint     | Provider expects a WellKnown struct with a 'authorization_endpoint' key. |
    # form_component.ex:113-120; auth_config_form.ex:68-97; handler.ex:343-358
    # auth_providers_live_test.exs:47-53, :94-95 (first row only, run under insecure-loopback)

  @S07 @pending
  Scenario: A plaintext discovery URL never passes the test
    # Value: the provider's signing keys and issuer can't be swapped by someone on the network path, which would let them forge a sign-in.
    Given I am a superuser with a valid provider form
    And the discovery URL is "http://idp.example.org/.well-known/openid-configuration"
    When I click "Test"
    Then I see the error "discovery endpoint must use https"
    And no request is made to that URL
    # well_known.ex:31-37, :52-56; tls.ex:29-41; auth_config_form.ex:86-88
    # under insecure-loopback an http URL on localhost passes (tls.ex:35-36)

  @S08 @pending
  Scenario: Editing the provider takes effect for sign-ins
    # Value: admins can rotate the client credentials or move the host without removing SSO and setting it up again.
    Given provider "acme-idp" is configured with client ID "id"
    And I am a superuser on "/settings/authentication"
    Then the form shows the stored values and a redirect host taken from the stored redirect URI
    When I change the client ID to "new-client-id" and the redirect host to "http://localhost:3030"
    And I click "Save"
    Then I see "Authentication Provider updated."
    And the "Redirect URI" box shows "http://localhost:3030/authenticate/acme-idp/callback"
    And sign-ins handled by this node in flow "flow-sso-login" use client ID "new-client-id" and that redirect URI
    # index.ex:24-33; form_component.ex:88-95; auth_providers.ex:33-41, :61-65
    # auth_providers_live_test.exs:149-198

  @S09 @pending
  Scenario: Unverified provider emails are not trusted unless an admin turns it on
    # Value: an email the provider has not verified can't claim a Lightning account unless an admin has decided this provider is trustworthy.
    Given I am a superuser on "/settings/authentication/new"
    Then "Trust unverified emails from this provider" is unchecked
    And I see "Only enable for a provider you trust that doesn't assert email_verified. Off by default."
    When I check it and save the provider
    Then the stored provider trusts unverified emails
    And flow "flow-sso-login" applies its trusted-provider rule (its S11) to sign-ins through it
    # form_component.ex:179-188; auth_config.ex:25-29, :42; auth_config_form.ex:16, :20-21; handler.ex:76-82
    # no live test covers the checkbox

  @S10 @pending
  Scenario: Removing the provider turns off SSO
    # Value: an admin can switch off sign-in through a provider that is retired or compromised.
    Given provider "acme-idp" is configured
    And I am a superuser on "/settings/authentication"
    When I click "Remove"
    Then I see "Authentication Provider removed"
    And I am on "/settings/authentication/new"
    And no provider is stored
    And flow "flow-sso-login" can no longer start through "acme-idp" on this node
    # form_component.ex:124-132, :272-290; auth_providers.ex:43-45, :77-79
    # auth_providers_live_test.exs:121-124, :200-209 (row gone; get_handler returns :not_found)
```

## 6. Unclear value

### 6.1 Possible bugs

| What | Where | What a user sees | Disposition |
|------|-------|------------------|-------------|
| Removing the provider clears only the handler cache of the node that served the request; other nodes keep the old handler for up to 30 minutes, and their login page and callback use it (moved from flow-sso-login 6.1 row 2) | `form_component.ex:124-126`; `auth_providers.ex:77-79`; `store.ex:13-19`, `:23-42`, `:49-52`; `cache_warmer.ex:16-30` | on a multi-node install, SSO keeps working and "via external provider" keeps showing on some nodes after the admin removed it | fix |
| Renaming the provider caches the handler under the new name but never removes the old name's entry, so on this node too the old name keeps working for up to 30 minutes and the login page may link to it (it takes the first cached handler) | `auth_providers.ex:33-41`, `:61-65`; `store.ex:13-19`; `user_session_controller.ex:80-85` | after a rename the login button may still send people through the old callback URL, which the provider no longer accepts | fix |
| Creating a provider does not put a handler in the cache, and the login page reads only the cache, so "via external provider" doesn't appear until the warmer runs (up to 30 minutes) or someone opens /authenticate/<name> | `auth_providers.ex:27-31`; `user_session_controller.ex:75-86`; `store.ex:13-19`; `cache_warmer.ex:16-17` | the admin creates the provider, signs out to try it, and finds no SSO button | fix |
| An update whose new settings can't build a handler (discovery fetch fails) still saves and says "updated", but the previous handler stays cached on this node, so this node keeps signing people in with the old settings while other nodes rebuild from the row and fail | `auth_providers.ex:33-41` (result of `create_handler` discarded); `handler.ex:94-113`; `form_component.ex:88-95` | "Authentication Provider updated." with SSO behaving differently per node | fix |
| /settings/authentication/new saves a second row while one exists (no unique constraint); `get_existing/0` then raises on `Repo.one`, so /settings/authentication crashes and the warmer can't load a provider | `index.ex:42-48`; `auth_providers.ex:14-16`, `:27-31`; `priv/repo/migrations/20220819100204_create_auth_providers.exs`; `cache_warmer.ex:22-30` | the menu link (which goes to /new) lets an admin create a second provider; afterwards the edit page errors | fix |
| The stored client secret is written into the page HTML as the `value` of the password input on the edit page | `form_component.ex:168-174`; `live/components/form.ex:101-105` | the secret is in the page source and devtools of any superuser who opens the page | fix |
| A redirect host with characters `URI.new!` rejects (for example a space) raises during validate instead of showing a field error | `auth_config_form.ex:56-61` | the form crashes and reloads while typing a host | fix |
| Fields are `varchar(255)` with no length validation; a longer value (for example a long discovery URL) raises on insert or update instead of returning a changeset error | migration `20220819100204_create_auth_providers.exs:6-12`; `auth_config.ex:45-49`; `form_component.ex:73`, `:89` | the page crashes on Save | fix |

### 6.2 Quirks and implementation details

| What | Where | Disposition |
|------|-------|-------------|
| Save does not require a passing Test; the form's URL check accepts `http://`, so a plaintext discovery URL can be saved and then fails every sign-in under `default` | `form_component.ex:196-203`; `auth_config_form.ex:40-44`; `well_known.ex:52-56` | decide |
| Test checks only that the discovery document fetches, parses and names authorization and token endpoints; the client ID and secret are never checked against the provider | `auth_config_form.ex:68-114`; `handler.ex:343-358` | decide |
| The discovery fetch ignores the HTTP status, so a 404 or 500 with a JSON body passes Test | `well_known.ex:31-37` | decide |
| The Test button is absent while the form is invalid, and "Success" and "Failed" are not clickable; only editing a field brings back "Test" | `form_component.ex:42`, `:56-61`, `:301-333` | preserve |
| Remove has no confirmation, although its copy says it "disables external authentication for Lightning" | `form_component.ex:272-289`, `:124-132` | decide |
| The remove event is named `disable` but deletes the row | `form_component.ex:124`, `:283` | preserve |
| /settings/authentication/new renders an empty form even when a provider exists (also shared-admin-space 6.2) | `index.ex:42-48`; `settings.html.heex:55-61` | decide |
| Changing the name silently changes the redirect URI the provider must accept; only the preview shows it | `auth_config_form.ex:47-66`; `form_component.ex:240-259` | decide |
| The redirect host defaults to the endpoint URL on /new and to the scheme and host of the stored redirect URI on edit; it is free text with no format check beyond required | `index.ex:26-29`, `:46`; `auth_config_form.ex:47-49` | preserve |
| The client secret is stored in plaintext in `auth_providers.client_secret`, unlike project credentials | `auth_config.ex:22`; migration `20220819100204_create_auth_providers.exs:10` | decide |
| No audit event for creating, editing, removing the provider or turning on "trust unverified emails" | `auth_providers.ex:27-45` | decide |
| Save failures from the changeset show "Something went wrong." with no detail (but see 6.3) | `form_component.ex:84-85`, `:97-98` | preserve |
| Flash copy is title case ("Authentication Provider created.", "Authentication Provider removed" without a full stop) | `form_component.ex:79`, `:95`, `:130` | preserve |
| Help copy names Google and links to Google's docs only | `form_component.ex:214-234`, `:260-270` | preserve |
| The discovery URL pattern is loose (unescaped `.`, any 1 to 6 character suffix) | `auth_config_form.ex:40-44` | preserve |
| /settings/authentication with no provider replaces history with /new (`replace: true`) | `index.ex:35-38` | preserve |

### 6.3 Unreachable or dead code

| What | Where | Why unreachable |
|------|-------|-----------------|
| `{:error, %Ecto.Changeset{}}` branches of save | `form_component.ex:84-85`, `:97-98` | the form validates a superset of `AuthConfig.changeset/2` (`auth_config_form.ex:21`, `:29-45` vs `auth_config.ex:34-49`) and Save is disabled while invalid; DB errors raise instead (6.1) |
| `parent={self()}` passed to the component | `index.ex:65`; `form_component.ex:21-24` | `update/2` never reads it |
| `AuthProviders.build_handler/2` and `WellKnown.fetch!/1` | `auth_providers.ex:81-89`; `well_known.ex:39-47` | no caller in lib or test |
| Test failure branch when `discovery_url` has no error | `form_component.ex:114` | `validate_provider/1` only ever adds errors to `discovery_url` (`auth_config_form.ex:68-97`) and Test renders only for a valid form, so the match always succeeds |

### 6.4 Performance and operational limits

| What | Where | User-visible? | Disposition |
|------|-------|---------------|-------------|
| Test fetches the discovery document inside the LiveView process with HTTPoison default timeouts and no loading state on the button (no `phx-disable-with`) | `form_component.ex:104-121`, `:318-329`; `well_known.ex:31-37` | yes, the page seems to do nothing until the fetch returns or times out | decide |
| Save on edit also fetches the discovery document synchronously (handler rebuild); "Saving" shows meanwhile | `auth_providers.ex:37`; `handler.ex:94-113`; `form_component.ex:197` | yes, a slow provider slows Save | preserve |
| Handler cache TTL 30 minutes and warmer interval 30 minutes (moduledoc says 30 seconds) | `store.ex:50`; `cache_warmer.ex:2-3`, `:16-17` | yes, through 6.1 rows 1 to 4 | preserve |

### 6.5 Things seen but not understood

- The component renders its own `live_info_block` and `live_error_block` with `phx-target={@myself}` (`form_component.ex:295-296`) while the settings layout renders the same pair for the parent's flash (`settings.html.heex:99-100`). If LiveView 1.0.19 copies a component's flash to the parent and also keeps it in the component's `@flash`, "Authentication Provider updated." and the Test error render twice at the same fixed position, and clicking clears only one. Not confirmed: the LiveView source is not in this checkout.
- The moduledocs describe the wrong things: the form component as "a single Job" with adaptor dropdowns, the index as "listing and managing Projects" (`form_component.ex:2-12`; `index.ex:2-4`).
- The page renders `LayoutComponents.header` (`index.ex:55-57`), so it answers shared-admin-space 6.5: the confirmation banner from shared-project-header S13 and S14 can show here.

## 7. Not migrating

| Item | Reason | Decided by | Date |
|------|--------|------------|------|

## 8. Open questions

- Should cache changes (create, update, rename, remove) reach every node at once, for example through PubSub or by reading the row on each login (6.1 rows 1 to 4)? (owner: security)
- Should the edit page stop sending the client secret to the browser, and should the secret be encrypted at rest like credentials (6.1, 6.2)? (owner: security)
- Should create, edit, remove and turning on "trust unverified emails" be audited (6.2)? (owner: security)
- Should Save require a passing Test, and should Test also check the client credentials and HTTP status (6.2)? (owner: product)
- Should Remove ask for confirmation (6.2)? (owner: product)
- Is one provider per instance the intended product limit, and if so should /new refuse when one exists (6.1 row 5; flow-sso-login 8)? (owner: product)

## Proposed flows

none. Referenced: flow-sso-login (S08 edit handoff, S09 trusted-provider rule via its S11, S10 removal handoff; its 6.1 row 2 now lives here as 6.1 row 1).

## Proposed shared

none. Inherits shared-admin-space (S01, S02, S03), shared-authenticated-session, shared-flash-messages (S07).

## Lead resolution (batch 10)

- No proposals.
