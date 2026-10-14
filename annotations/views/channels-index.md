---
id: channels-index
type: view
title: Channels
status: not-started
owner:

trigger:
  old_route: /projects/:project_id/channels (also /channels/new and /channels/:id/edit, which open the form modal over the list)
  new_route:
  old_route_disposition: unchanged
  reachable_when:
    - the project scope gate admits the viewer (shared-project-scope; index.ex:13)
    - the route sits in live_session :default with InitAssigns (router.ex:288, :313-315)
    - nothing on the page checks experimental features; only the side menu link is gated on them (menu.ex:54-62). See 6.2
    - /new needs `:create_channel` and /:id/edit needs `:update_channel`, otherwise the page navigates back to the list with an error flash (index.ex:139-155, :157-182)

inherits:
  - shared-authenticated-session    # live_session :default with InitAssigns (router.ex:288)
  - shared-project-scope            # index.ex:13
  - shared-usage-limits-banner      # index.ex:14, :20-26
  - shared-project-header           # index.ex:27-40; side menu marked Channels via active_menu_item :channels (index.ex:113)
  - shared-local-datetime           # Last activity column (index.ex:382)

url_params:
  - name: project_id
    set_by: every project link
    effect: owned by shared-project-scope
  - name: id (path segment of /channels/:id/edit)
    set_by: this view's Edit button (index.ex:410-415)
    effect: opens the edit modal for that channel; a channel in another project, or an unknown id, navigates back to the list with "Channel not found" (S20); a non-UUID raises (6.1)

config_variants:
  default: {}                                                                  # verified against this; the page mounts and works without experimental features
  experimental-features: { user.preferences.experimental_features: true }      # accounts.ex:1446-1448; only adds the side menu link (menu.ex:54-62)

inventory:
  routes:
    - live /projects/:project_id/channels  ChannelLive.Index :index           # router.ex:313
    - live /projects/:project_id/channels/new  ChannelLive.Index :new         # router.ex:314
    - live /projects/:project_id/channels/:id/edit  ChannelLive.Index :edit   # router.ex:315
  events:
    - ChannelLive.Index#toggle_channel_state          # index.ex:184-207
    - ChannelLive.Index#delete_channel                # index.ex:209-230
    - ChannelLive.FormComponent#validate              # form_component.ex:47-72
    - ChannelLive.FormComponent#save                  # form_component.ex:74-76, :233-275
  js_hooks:
    - Copy                          # proxy_url_copy (helpers.ex:52-72; assets/js/hooks/index.ts:738-817); also Common.datetime via shared-local-datetime
    - Tooltip                       # Common.wrapper_tooltip around the row proxy URL (index.ex:339-342); edit modal proxy URL wrapper (form_component.ex:106-112); disabled New Channel button tooltip (index.ex:58-66); disabled-channel toggle tooltip (index.ex:395; new_inputs.ex:877)
    - LocalTimeConverter            # via shared-local-datetime
    - "data-confirm browser confirm on Delete (index.ex:422)"
    - "JS.push toggle_channel_state from the toggle input (new_inputs.ex:882-888)"
    - "JS.patch on_close for the modal and Cancel (index.ex:89; form_component.ex:90, :95, :223)"
  policies:
    - Lightning.Policies.ProjectUsers :create_channel   # index.ex:98-100
    - Lightning.Policies.ProjectUsers :update_channel   # index.ex:102-104
    - Lightning.Policies.ProjectUsers :delete_channel   # index.ex:106-108
    - Lightning.Policies.ProjectUsers :access_project   # via shared-project-scope
  workers: []                       # nothing enqueued; channel delete clears request history inline (channels.ex:343-348)
  api_endpoints: []
  emails: []
  config:
    - user.preferences.experimental_features (menu link only, menu.ex:54)
    - LightningWeb.Endpoint url (proxy URL host, helpers.ex:7-9)
    - Lightning.Config.activity_cleanup_chunk_size and default_ecto_database_timeout (channel delete batches, channels.ex:460-487)
  not_reachable_here:
    - LightningWeb.ChannelProxyPlug (channel_proxy_plug.ex); the proxy that uses this config is owned by the proposed flows below
    - Lightning.Channels.list_channel_requests, get_channel_with_auth, get_or_create_current_snapshot, delete_expired_requests, delete_channel_requests_for_project (channels.ex:99-118, :161-177, :369-411, :421-458); other surfaces
    - Lightning.Channels.list_channels_for_project/1 (channels.ex:28-34); this view uses the _with_stats variant, the form tests call the plain one

related:
  - history-channel-logs            # Requests, Last activity and "View all" links land there
  - channel-request-show
  - project-settings-credentials    # destination credential "Add New" link (#credentials)
  - project-settings-webhook-security   # client credentials "Add New" link (#webhook_security)
  - shared-project-settings-tab-chrome  # owns the #fragment behaviour of both "Add New" links
flows:
  - flow-zero-persistence-channel-requests
  - flow-channel-proxy-request
---

## 1. Purpose

Project editors use Channels to set up an HTTP proxy that lets a client system reach a destination
API through OpenFn: they name the channel, point it at a destination URL, choose the credential
OpenFn adds on the way out and the credentials a client must present on the way in, then hand the
proxy URL to the client system. This page is where channels are created, changed, switched off and
removed, and where people see at a glance whether each one is carrying traffic. Getting it wrong
either breaks a live integration, or leaves a proxy that forwards anyone's requests to a
destination with the project's secret attached.

## 2. What it does

- Anyone on the project sees the project's channels with destination, request count, last activity and enabled state
- Anyone sees total channels and total requests for the project
- Anyone copies a channel's proxy URL
- Anyone follows a channel's request count or "View all" to the channel logs
- Editors create a channel with a name, destination URL, destination credential and client credentials
- Editors change a channel's settings and credentials
- Editors switch a channel off and on
- Editors delete a channel
- Viewers see the list read-only
- Credentials and auth methods from another project can never be attached

## 3. Who can do what

Source: `lib/lightning/policies/project_users.ex:39-49` (`:create_channel`, `:update_channel`,
`:delete_channel` are editor actions), `:167-172` (support access fills in for a missing row), `:134`
(MFA guard). Superusers without a row are not admitted at all (shared-project-scope).

| Action | Viewer | Editor | Admin | Owner | Superuser (no row) | Support (no row, access on) |
|--------|--------|--------|-------|-------|--------------------|-----------------------------|
| See the page, totals and list | yes | yes | yes | yes | no | yes |
| Copy a proxy URL | yes | yes | yes | yes | no | yes |
| Create a channel | no | yes | yes | yes | no | yes |
| Edit a channel | no | yes | yes | yes | no | yes |
| Switch a channel off or on | no | yes | yes | yes | no | yes |
| Delete a channel | no | yes | yes | yes | no | yes |

**Preconditions beyond role**
- Permissions are computed once at mount (`index.ex:98-108`) and re-checked on every event and on `/new` and `/:id/edit` (`index.ex:140`, `:158`, `:190`, `:211`, `:237-246`). A role change remounts the page (shared-project-scope S08).
- Toggle, delete and edit only act on a channel in the current project (`index.ex:159-165`, `:248-253`; `channels.ex:183-187`).
- Destination credentials and client auth methods must belong to the channel's project, checked at save regardless of what the form offered (`channels.ex:198-200`, `:228-230`, `:249-331`).
- An MFA-required project blocks all of this until the user enrols (shared-project-scope S05).

## 4. What it touches

**Reads**
- `channels` with a LEFT JOIN count and max(`started_at`) over `channel_requests`, ordered by name (`channels.ex:44-58`)
- `channels` and `channel_requests` totals in one query (`channels.ex:70-81`)
- `channels` with `client_auth_methods` and `destination_auth_method` for edit (`index.ex:159-165`)
- `webhook_auth_methods` for the project, excluding those scheduled for deletion, by name (`webhook_auth_methods.ex:466-472`)
- `project_credentials` with `credentials`, their `user` and `oauth_client` (`projects.ex:1121-1125`)
- `project_credentials`, `keychain_credentials`, `webhook_auth_methods` for the scope check on save (`scoping.ex:82-114`)

**Writes**
- `channels` insert (`channels.ex:194-217`), update bumping `lock_version` (`channels.ex:224-247`; `channel.ex:92`), delete (`channels.ex:343-358`)
- `channel_auth_methods` insert and delete through `cast_assoc` (`channel.ex:62-71`; `form_component.ex:277-334`); a destination swap deletes the old row (`channel.ex:39-41`, `on_replace: :delete`)
- `channel_requests` deleted in batches before a channel is deleted (`channels.ex:344-348`, `:460-488`); `channel_events` cascade from them and `channel_snapshots` cascade from the channel (migrations 20260210120112, 20260305110335)
- `audit_events` for item type `channel`: `created`, `updated`, `deleted`, `auth_method_added`, `auth_method_removed`, `auth_method_changed` (`audit.ex:213-223`, `:238-357`; `channels.ex:202-210`, `:232-240`, `:351`)

**Immediate side effects**
- Flash and `push_patch` back to the list, which reloads it (`index.ex:197-198`, `:216-217`; `form_component.ex:242-244`, `:268-270`)
- No PubSub broadcast, no Oban job, no email

**Deferred side effects** (later, elsewhere)
- The proxy reads `enabled`, the destination URL and the auth methods per request (`channel_proxy_plug.ex:318-323`, `:337-360`, `:176-197`); owned by flow-channel-proxy-request and flow-channel-proxy-request
- A save or toggle bumps `lock_version`, so the next proxied request creates a new channel snapshot (`channels.ex:369-391`)

**External, non-transactional effects**
- Channel request history is deleted in its own statements before the delete transaction starts (`channels.ex:343-353`); if the transaction then fails, the history is already gone (6.1)

**Depends on config**
- Proxy URL host and scheme come from `LightningWeb.Endpoint.url()` (`helpers.ex:7-9`)
- Side menu link needs `experimental-features` (`menu.ex:54-62`)

**Product limits**
- none enforced. Name and destination URL are `varchar(255)` with no length validation (6.1).

## 5. Scenarios

```gherkin
Feature: Channels
  In order to let a client system reach a destination API through OpenFn
  As a project editor
  I want to create, change, switch off and remove channels, and see whether they carry traffic

  @S01 @pending
  Scenario: Member sees the project's channels
    # Value: people can tell which proxies exist, where they send traffic and whether they are in use.
    Given project "Malawi HIV" has channel "lab-results" to "https://destination.example.com/data"
    And "lab-results" has received 2 requests, the latest on 5 March 2025
    And project "Malawi HIV" has channel "idle" with no requests
    When I open the channels page
    Then I see a row for "lab-results" with destination "https://destination.example.com/data", requests "2" and a last activity time
    And I see a row for "idle" with requests "0" and last activity "Never"
    And each row shows whether the channel is enabled
    # index.ex:301-433; channels.ex:44-58; index_test.exs:81-136

  @S02 @pending
  Scenario: Totals show channels and requests for the project
    # Value: someone checking an integration sees at a glance whether any traffic has gone through.
    Given project "Malawi HIV" has 2 channels with 3 requests between them
    When I open the channels page
    Then "Total channels" shows 2
    And "Total requests" shows 3
    # index.ex:260-285; channels.ex:70-81; index_test.exs:60-68 asserts the labels only

  @S03 @pending
  Scenario: Channels from other projects are not listed
    # Value: one project's proxy configuration and traffic stay private to that project.
    Given project "Malawi HIV" has channel "mine"
    And another project has channel "theirs"
    When I open the channels page on "Malawi HIV"
    Then I see "mine"
    And I do not see "theirs"
    # channels.ex:44-46, :70-72; index_test.exs:138-150

  @S04 @pending
  Scenario: Copy a channel's proxy URL
    # Value: the client system is configured with the exact URL, without retyping a UUID.
    Given project "Malawi HIV" has channel "lab-results"
    When I click the proxy URL under "lab-results"
    Then my clipboard holds "<endpoint url>/channels/<lab-results id>"
    And the tooltip says "Copied!"
    # index.ex:339-362; helpers.ex:7-9, :52-72; assets/js/hooks/index.ts:738-817; helpers_test.exs:6-12

  @S05 @pending
  Scenario: Request count opens the channel logs for that channel
    # Value: from a channel with unexpected traffic, one click shows its requests.
    Given project "Malawi HIV" has channel "lab-results" with requests
    When I click the request count for "lab-results"
    Then I am on the channel logs with filters[channel_id] set to "lab-results"
    # Handoff only; the filtered list is owned by history-channel-logs. The Last activity cell links to the same URL.
    # index.ex:365-386

  @S06 @pending
  Scenario: View all opens the channel logs for every channel
    # Value: people can review all proxied traffic for the project from the totals.
    When I click "View all" on the total requests card
    Then I am on the channel logs for project "Malawi HIV" with no channel filter
    # Handoff only, owned by history-channel-logs. index.ex:272-277

  @S07 @pending
  Scenario: Requests stored without payloads still count
    # Value: on a project that keeps no request data, people can still see that a channel is carrying traffic.
    Given flow "flow-zero-persistence-channel-requests" has stored 2 requests on channel "lab-results" without their payloads
    When I open the channels page
    Then "lab-results" shows requests "2" and a last activity time
    # Counts and max(started_at) ignore is_wiped (channels.ex:44-81); the wiping itself is owned by the flow

  @S08 @pending
  Scenario: Editor creates a channel
    # Value: an editor can stand up a new proxy for a partner system without an admin.
    Given I am an editor on project "Malawi HIV"
    When I click "New channel"
    And I enter name "new-channel" and destination URL "https://example.com/destination"
    And I save
    Then I am back on the channels list with "Channel created successfully."
    And "new-channel" is listed and enabled
    And an audit event "created" is recorded for the channel with me as actor
    # index.ex:50-57, :139-149; form_component.ex:233-249; channels.ex:194-217; form_test.exs:27-52

  @S09 @pending
  Scenario: Name and destination URL are required
    # Value: no channel exists that cannot be identified or has nowhere to forward to.
    Given I am on the new channel form
    When I save with an empty name and an empty destination URL
    Then the form stays open with "can't be blank"
    And no channel is created
    # channel.ex:60; form_component.ex:246-247; form_test.exs:92-107

  @S10 @pending
  Scenario: Destination URL must be an http or https URL with a host
    # Value: requests are only forwarded to a web address, never to another scheme or a malformed target.
    Given I am on the new channel form
    When I save with destination URL "ftp://example.com"
    Then the form stays open with "must be either a http or https URL"
    # validators.ex:320-344; channel.ex:86. Not covered by a test.

  @S11 @pending
  Scenario: Channel names are unique within a project
    # Value: channel names identify channels in logs and the project spec, so two can't be confused.
    Given project "Malawi HIV" has channel "existing"
    When I create another channel named "existing"
    Then the form stays open with "A channel with this name already exists in this project"
    # channel.ex:83-91; form_test.exs:110-138

  @S12 @pending
  Scenario: Editor chooses the destination credential from the project's credentials
    # Value: OpenFn authenticates to the destination with a credential the project already holds, so clients never need it.
    Given project "Malawi HIV" has credentials "My API Key" and "OAuth Token"
    When I open the new channel form
    Then "Destination credential" offers "None", "My API Key" and "OAuth Token"
    When I create a channel with "My API Key"
    Then the channel has one destination auth method for "My API Key"
    And an audit event "auth_method_added" is recorded
    When I create a channel with "None"
    Then that channel has no destination auth method
    # form_component.ex:150-179, :321-334; audit.ex:297-307; form_test.exs:193-233, :547-641

  @S13 @pending
  Scenario: Editor attaches client credentials
    # Value: only client systems holding one of the chosen credentials can use the channel.
    Given project "Malawi HIV" has webhook auth methods "API Key Auth" and "Basic Auth"
    When I create a channel with "API Key Auth" checked
    Then the channel has one client auth method for "API Key Auth"
    And the flow "flow-channel-proxy-request" applies "API Key Auth" to requests on that channel
    # form_component.ex:181-216, :305-319; form_test.exs:56-89, :236-265

  @S14 @pending
  Scenario: Edit form opens with the channel's current settings and its proxy URL
    # Value: an editor changes a live channel knowing exactly what it does now.
    Given channel "edit-me" to "https://old.example.com" with client method "API Key Auth" and destination credential "My API Key"
    When I click "Edit" on "edit-me"
    Then the form shows name "edit-me" and destination URL "https://old.example.com"
    And "API Key Auth" is checked and "My API Key" is selected
    And the form shows the channel's proxy URL, which copies on click
    # index.ex:157-171, :410-415; form_component.ex:13-45, :106-122; form_test.exs:284-303, :372-418

  @S15 @pending
  Scenario: Editor saves changes to a channel
    # Value: a moved destination or a renamed channel can be fixed in place without recreating it and changing its proxy URL.
    Given I am editing channel "edit-me"
    When I change the name to "updated-name" and save
    Then I am back on the list with "Channel updated successfully."
    And "updated-name" is listed
    And an audit event "updated" is recorded
    # form_component.ex:251-275; channels.ex:224-247; form_test.exs:306-340

  @S16 @pending
  Scenario: Editor swaps or clears the destination credential
    # Value: a rotated or revoked destination secret can be replaced, and the change is traceable.
    Given channel "c" uses destination credential "Key A"
    When I select "Key B" and save
    Then "c" has exactly one destination auth method, for "Key B"
    And an audit event "auth_method_changed" is recorded
    When I select "None" and save
    Then "c" has no destination auth method
    And an audit event "auth_method_removed" is recorded
    # form_component.ex:321-334; audit.ex:266-330; form_test.exs:644-768

  @S17 @pending
  Scenario: Editor adds and removes client credentials in one save
    # Value: client access can be rotated in a single step without a window where the channel is open.
    Given channel "c" has client method "Old" and destination credential "Key A"
    When I uncheck "Old", check "New" and save
    Then "c" has only client method "New"
    And "c" still uses destination credential "Key A"
    And audit events "auth_method_removed" and "auth_method_added" are recorded
    # form_component.ex:305-319; audit.ex:246-256; form_test.exs:420-495

  @S18 @pending
  Scenario: Another project's credential cannot be attached as the destination credential
    # Value: one tenant cannot route another tenant's secret to a URL they control.
    Given another project has credential "victim"
    When I submit a channel whose destination credential id is "victim", bypassing the dropdown
    Then the form stays open
    And no channel is created, or the existing destination credential is unchanged
    # channels.ex:249-331; form_test.exs:772-853. The form shows no message (6.1).

  @S19 @pending
  Scenario: Another project's webhook auth method cannot be attached as a client credential
    # Value: one tenant's auth objects cannot gate or be probed through another tenant's channel.
    Given another project has webhook auth method "victim"
    When I submit a channel with "victim" checked, bypassing the checkbox list
    Then "victim" is attached to no channel
    And the channel's existing client methods are unchanged
    # channels.ex:278-292; channel_auth_method.ex:151-153; form_test.exs:857-941

  @S20 @pending
  Scenario: Another project's channel cannot be opened for editing
    # Value: an editor in one project cannot read or change another project's channel config by guessing its URL.
    Given a channel belongs to another project
    When I open /projects/<my project>/channels/<that channel id>/edit, directly or by a client-side patch
    Then I am sent to my project's channels list with "Channel not found"
    # index.ex:159-176; channels.ex:183-187; form_test.exs:498-542

  @S21 @pending
  Scenario: Editor switches a channel off and on
    # Value: a misbehaving integration can be stopped at once without losing its configuration.
    Given channel "toggle-me" is enabled
    When I switch its toggle off
    Then I see "Channel updated"
    And "toggle-me" is disabled and its name is greyed
    And an audit event "updated" is recorded with me as actor
    And the flow "flow-channel-proxy-request" no longer forwards requests on "toggle-me"
    When I switch it back on
    Then "toggle-me" is enabled
    # index.ex:184-207, :319-325, :388-398; channel_proxy_plug.ex:318-323; index_test.exs:153-210

  @S22 @pending
  Scenario: Editor deletes a channel after confirming
    # Value: channels no longer needed can be removed so they stop being a way in, with a record of who removed them.
    Given channel "delete-me" exists
    When I click "Delete" on "delete-me"
    Then the browser asks 'Delete "delete-me"? This cannot be undone.'
    When I confirm
    Then I see "Channel deleted."
    And "delete-me" is no longer listed
    And an audit event "deleted" is recorded with me as actor
    # index.ex:209-230, :416-425; channels.ex:343-358; index_test.exs:212-231, :253-294. History deletion: see 6.1.

  @S23 @pending
  Scenario: Viewer sees channels read-only
    # Value: read-only members can check channel status without being able to break an integration.
    Given I am a viewer on project "Malawi HIV" with channel "viewer-channel"
    When I open the channels page
    Then "New channel" is disabled with tooltip "You are not authorized to perform this action."
    And there is no "Edit" or "Delete" on "viewer-channel"
    And the enabled column shows "Enabled" or "Disabled" as text, not a toggle
    # index.ex:50-66, :389-425; index_test.exs:37-56, :233-251

  @S24 @pending
  Scenario: Viewer opening the new or edit URL is sent back to the list
    # Value: write forms are not reachable by URL for people who cannot save them.
    Given I am a viewer on project "Malawi HIV"
    When I open /projects/<id>/channels/new
    Then I am on the channels list with "You are not authorized to create channels."
    When I open /projects/<id>/channels/<channel id>/edit
    Then I am on the channels list with "You are not authorized to edit channels."
    # index.ex:150-154, :177-181; form_test.exs:141-149 (new only)

  @S25 @pending
  Scenario: A crafted toggle or delete from a viewer is refused
    # Value: read-only members cannot change channels even by sending events the page didn't offer them.
    Given I am a viewer on project "Malawi HIV" with channel "c"
    When my browser sends "toggle_channel_state" or "delete_channel" for "c"
    Then I see "You are not authorized to perform this action."
    And "c" is unchanged
    # index.ex:190, :211, :232-246. Not covered by a test.

  @S26 @pending
  Scenario: A crafted toggle or delete for another project's channel is refused
    # Value: an editor in one project cannot switch off or delete another project's proxy.
    Given I am an editor on project "Malawi HIV"
    And channel "theirs" belongs to another project
    When my browser sends "toggle_channel_state" or "delete_channel" for "theirs"
    Then I see "Channel not found"
    And "theirs" is unchanged
    # index.ex:191, :212, :248-253; channels.ex:183-187. Not covered by a test.

  @S27 @pending
  Scenario: Destination and client "Add new" links open the right settings tab
    # Value: someone setting up a channel can find where the missing credential or auth method is created without losing the form.
    Given I am on the new channel form
    Then the destination credential "Add new" link opens project settings at #credentials in a new tab
    And the client credentials "Add new" link opens project settings at #webhook_security in a new tab
    # Handoff only; tab selection is owned by shared-project-settings-tab-chrome. form_component.ex:155-161, :186-192; form_test.exs:268-279

  @S28 @pending @variant:experimental-features
  Scenario: Channels appear in the project menu for people with experimental features on
    # Value: people who opted into preview features can find channels from any project page.
    Given I have experimental features on
    When I open any page in project "Malawi HIV"
    Then the side menu shows "Channels", marked active on this page
    # menu.ex:54-62; index.ex:113. Under default the link is absent but the page still mounts (6.2).
```

## 6. Unclear value

### 6.1 Possible bugs

| What | Where | What a user sees | Disposition |
|------|-------|------------------|-------------|
| Loading `/channels/new` or `/channels/:id/edit` directly leaves the list and totals at their mount defaults; only `:index` loads them | `index.ex:117-118`, `:139-182` (no load in `:new`/`:edit`) | behind the modal, "Channels (0)", zero totals and "No channels found." on a project that has channels, until the modal closes | fix |
| Errors on nested auth methods are never shown: the destination select and client checkboxes are raw inputs, not bound to the changeset | `form_component.ex:166-215`; `channels.ex:294-331`; `channel_auth_method.ex:140-166`; `form_test.exs:799`, `:840` assert only that the form stays open | Save does nothing visible when a credential is out of scope, was deleted meanwhile, or hits a uniqueness constraint | fix |
| A stale `lock_version` (the channel was saved or toggled elsewhere after the form opened) returns an error on `:lock_version`, which the form doesn't render | `channels.ex:231`; `channel.ex:92`; `form_component.ex:272-273` | Save does nothing visible; reopening the form works | fix |
| Name and destination URL are `varchar(255)` with no length validation | migration `20260210120112_create_channels_tables.exs:12-13`; `channel.ex:81-93` (no `validate_name_fits_column`) | a 256-character name or URL crashes the LiveView on save | fix |
| Deleting a channel deletes all its request history, though `channel_requests` was made RESTRICT "so that deleting a channel cannot silently destroy its request history"; the confirm says only "This cannot be undone." | `channels.ex:333-358`; migration `20260330131728_change_channel_requests_cascade_to_restrict.exs:8-11`; `index.ex:422` | every logged request for the channel disappears from channel logs and totals without warning | decide |
| Request history is deleted outside the delete transaction, and a request inserted between the batch delete and the channel delete hits the RESTRICT FK with no declared constraint | `channels.ex:344-353`; `channel.ex:47` (no `foreign_key_constraint`) | on a busy channel, delete can crash the page after the history is already gone, leaving the channel in place | fix |
| A non-UUID id in the edit URL is cast in the query and raises | `index.ex:160`; `channels.ex:146-151`, `:183-186` | an error page instead of "Channel not found" | fix |
| A channel with no client credentials forwards any request and attaches the destination credential; the form gives no warning | `channel_proxy_plug.ex:176-178`, `:337-360`; `form_component.ex:194-216` | an editor can publish an open proxy to a secret-bearing destination without being told | decide |

### 6.2 Quirks and implementation details

| What | Where | Disposition |
|------|-------|-------------|
| Only the side menu link checks experimental features; the routes mount for everyone on the project | `menu.ex:54-62`; `router.ex:313-315`; `index.ex:13-14` | decide |
| Channels sorted by name ascending; webhook auth methods by name; project credentials in no particular order | `channels.ex:50`; `webhook_auth_methods.ex:470`; `projects.ex:1121-1125` | decide |
| Webhook auth methods scheduled for deletion are not offered, and one already attached is neither shown nor removed by a save | `webhook_auth_methods.ex:469`; `form_component.ex:22-27`, `:305-319` | decide |
| Heading count "Channels (n)" repeats the Total channels card | `index.ex:46-49`, `:264-267` | decide |
| The toggle tooltip "<name> (disabled)" appears only on disabled channels | `index.ex:395`; `new_inputs.ex:877` | decide |
| The toggle sends the state it was rendered with negated, so a stale page sets that state rather than flipping the stored one | `new_inputs.ex:882-888`; `index.ex:192` | preserve |
| Viewers see a disabled "New Channel" button with a tooltip, but Edit and Delete are hidden | `index.ex:58-66`, `:410-425` | decide |
| Copy is in title case ("New Channel", "Total Channels", "Destination Credential", "Client Credentials", "Edit Channel") | `index.ex:55`, `:264`, `:271`; `form_component.ex:83-84`, `:153`, `:184` | decide |
| "Client Credentials" lists webhook auth methods and its empty state says "No webhook auth methods available." | `form_component.ex:183-202` | decide |
| The client credentials "Add New" link goes to a tab only admins can change, while editors create channels | `form_component.ex:186-192`; `project_users.ex:30` | decide |
| "Add New" opens a new tab, and the open form's lists are loaded only in `update/2`, so a newly made credential appears only after reopening the form | `form_component.ex:13-21`, `:155-161`, `:186-192` | decide |
| Unauthorized `/new` and `/edit` use `push_navigate` (a remount) rather than a patch | `index.ex:153`, `:175`, `:180` | preserve |
| Delete uses a browser `data-confirm`, and a test pins that it is not `phx-confirm` | `index.ex:422`; `index_test.exs:214-231` | preserve |
| Empty state "No channels found." | `index.ex:293-299`; `index_test.exs:72-79` | preserve |
| Proxy URL text is truncated from the left with `direction:rtl`, keeping the channel id end visible | `helpers.ex:64-68` | preserve |
| Every successful save, toggle or delete patches back to the list, which re-queries list and totals | `index.ex:198`, `:217`; `form_component.ex:244`, `:270`; `index.ex:127-137` | preserve |

### 6.3 Unreachable or dead code

| What | Where | Why unreachable |
|------|-------|-----------------|
| Delete error "Cannot delete \"<name>\", it has request history that must be retained" (source copy uses an em dash) | `index.ex:220-225` | no constraint on `channel_snapshots` is declared on the schema and snapshots cascade (migration `20260305110335`); requests are deleted first |
| `channel_proxy_url_parts/1` fallback `{"", url}` | `helpers.ex:16-18` | `Endpoint.url()` always has a scheme |
| "Failed to update channel. Please try again." on toggle | `index.ex:201-204` | only an `enabled` change on a freshly fetched channel; reachable only by a concurrent stale update |

### 6.4 Performance and operational limits

| What | Where | User-visible? | Disposition |
|------|-------|---------------|-------------|
| No pagination of the channel list | `channels.ex:44-58` | no at current volumes | preserve |
| Per-channel counts and totals are aggregated over all `channel_requests` on every list load | `channels.ex:44-81` | yes, slower page as traffic grows | preserve |
| Channel delete removes requests in batches of `activity_cleanup_chunk_size`, each with 3x the default DB timeout, synchronously in the LiveView process | `channels.ex:460-488` | yes, Delete can hang on a busy channel | decide |
| Name and destination URL inputs debounce 300ms | `form_component.ex:133`, `:143` | no | preserve |
| No live updates: counts, last activity and enabled state change only on reload or patch | `index.ex` (no `handle_info`, no subscription) | yes | decide |

### 6.5 Things seen but not understood

- `validate` passes `client_auth_methods` as a map of id to "true"/"false" strings into `Channel.changeset`, whose `cast_assoc` expects maps; whether the validate changeset carries an invisible error was not checked (`form_component.ex:48-52`; `channel.ex:62-66`).
- Whether a save with no real changes still bumps `lock_version` and records an "updated" audit through `optimistic_lock` was not checked (`channel.ex:92`; `channels.ex:231-237`).
- Whether a remount or parent re-render while the modal is open re-runs `update/2` and discards unsaved input was not checked (`form_component.ex:13-45`).
- `delete_channel/2` has no clause for a failed audit insert (`channels.ex:350-357`); a `CaseClauseError` would follow, but no path that fails it was found.

## 7. Not migrating

| Item | Reason | Decided by | Date |
|------|--------|------------|------|

## 8. Open questions

- Should deleting a channel keep its request history (as the RESTRICT migration intended), or should the confirm say the history goes with it (6.1)?
- Should a channel with no client credentials be allowed, warned about, or refused when a destination credential is set (6.1)?
- Should channels stay reachable by URL for people without experimental features (6.2)?
- Should the new app show live counts on this page (6.4)?

## Proposed flows

- **flow-channel-proxy-request** (proposed; already named by flow-webhook-auth-method-enforcement and channel-request-show): the client auth methods chosen in the channel form are checked by the proxy before forwarding; a request without a matching API key or basic auth gets 401, a channel with none accepts any request, and the matched method is recorded on the request. Surfaces: channels-index, project-settings-webhook-security, external:channel-client, controller:channel-proxy-plug, history-channel-logs, channel-request-show. Evidence: `channel_proxy_plug.ex:115-121`, `:176-197`; this view's S13, S17.
- **flow-channel-proxy-request** (new): a client request to the copied proxy URL is forwarded to the channel's destination URL with the destination credential attached; a disabled or deleted channel answers 404 "Not Found" like an unknown one. Surfaces: channels-index, external:channel-client, controller:channel-proxy-plug, external:channel-destination, history-channel-logs. Evidence: `channel_proxy_plug.ex:84-104`, `:133-148`, `:318-323`, `:337-360`; this view's S04, S12, S21.
- Referenced: **flow-zero-persistence-channel-requests** (S07 asserts only that wiped requests are counted). channels-index is not yet in that flow's `surfaces`.

## Proposed shared

- none. Referenced: shared-authenticated-session, shared-project-scope, shared-usage-limits-banner, shared-project-header, shared-local-datetime. `proxy_url_copy` (`helpers.ex:52-72`) is used only by this view's list and form, so it is not proposed as shared.

## Lead resolution (batch 4)

- `flow-channel-client-auth-enforcement` and `flow-channel-proxy-forwarding` merged into `flow-channel-proxy-request`. channels-index added to flow-zero-persistence-channel-requests surfaces.
