---
id: project-settings-webhook-security
type: view
title: Project settings › Webhook security
status: not-started
owner:

trigger:
  old_route: /projects/:project_id/settings#webhook_security
  new_route: /projects/:project_id/settings/webhook-security
  old_route_disposition: redirect
  reachable_when:
    - the project scope gate admits the viewer (shared-project-scope; settings.ex:51)
    - the client-side tab hash is "webhook_security" (settings.html.heex:378; TabbedContainer, see shared-project-settings-tab-chrome)
    - the management UI (table, "New auth method", modals) renders only when the project is not a sandbox; a sandbox shows a notice instead (settings.html.heex:379-403)

inherits:
  - shared-authenticated-session
  - shared-project-scope                  # on_mount :project_scope (settings.ex:51); login, MFA, membership remount
  - shared-usage-limits-banner            # on_mount :check_limits (settings.ex:52)
  - shared-project-header
  - shared-project-settings-tab-chrome    # tab navigation, role notice (S06 row "editor | Webhook Security"), sandbox banner rules
  - shared-webhook-auth-method-form
  - shared-flash-messages   # added by lead (final pass)

url_params:
  - name: "#webhook_security (URL fragment)"
    set_by: channel form "manage auth methods" link (channel_live/form_component.ex:187); sandbox notice link in a child sandbox (settings.html.heex:394-402)
    effect: opens this tab client-side; the server never sees it (settings.ex:233)

config_variants:
  default: { purge_deleted_after_days: 7 }     # bootstrap.ex:273-277 default; purge cron on (bootstrap.ex:306-316)
  purge-disabled: { purge_deleted_after_days: 0 }   # no purge cron; deleted methods are hidden but never removed (bootstrap.ex:306-316, webhook_auth_methods.ex:771-774)
  sandbox: { project.parent_id: <parent project id> }   # data state, named so the sandbox scenario can be tagged
  # Read under default; purge-disabled read from code only

inventory:
  routes:
    - live /projects/:project_id/settings  ProjectLive.Settings :index   # config-injected (config/config.exs:52-57); catalogued by project-settings-setup
  events:
    - ProjectLive.Settings#show_modal (target new_webhook_auth_method)                      # settings.ex:526-547
    - ProjectLive.Settings#show_modal (target edit_webhook_auth_method | delete_webhook_auth_method)   # settings.ex:549-582
    - ProjectLive.Settings#show_modal (target linked_usage_for_webhook_auth_method)         # settings.ex:584-611
    - ProjectLive.Settings#close_active_modal                                              # settings.ex:451-455
    - WorkflowLive.WebhookAuthMethodFormComponent#choose_auth_type        # webhook_auth_method_form_component.ex:71-86
    - WorkflowLive.WebhookAuthMethodFormComponent#validate_auth_type      # :58-69
    - WorkflowLive.WebhookAuthMethodFormComponent#validate                # :88-115
    - WorkflowLive.WebhookAuthMethodFormComponent#save                    # :38-40, :125-190
    - WorkflowLive.WebhookAuthMethodFormComponent#toggle-2fa              # :42-45
    - WorkflowLive.WebhookAuthMethodFormComponent#reauthenticate-user     # :47-56
    - WorkflowLive.WebhookAuthMethodDeleteModal#validate_deletion         # webhook_auth_method_delete_modal.ex:32-42
    - WorkflowLive.WebhookAuthMethodDeleteModal#perform_deletion          # :44-73
  js_hooks:
    - Copy (API key and revealed password copy buttons; webhook_auth_method_form_component.ex:545, :591; assets/js/hooks/index.ts:738)
  policies:
    - Lightning.Policies.ProjectUsers (:write_webhook_auth_method; project_users.ex:29-37, :160-161; flag computed settings.ex:145-150)
  workers:
    - Lightning.WebhookAuthMethods (Oban cron "purge_deleted", 03:00 UTC daily when purge_deleted_after_days > 0; webhook_auth_methods.ex:19-21, :64-92; bootstrap.ex:313-314)
  api_endpoints: []
  emails: []
  config:
    - :lightning, :purge_deleted_after_days (config.ex:80-81, :534-535; bootstrap.ex:273-277)
  not_reachable_here:
    - WebhookAuthMethodFormComponent create-for-trigger path (save :new with a %Trigger{}, create_auth_method/3; form_component.ex:146-169, webhook_auth_methods.ex:189-218); this view passes trigger={nil}
    - WebhookAuthMethodFormComponent on_save callback (form_component.ex:34, :132-134, :157-159, :178-180); used by workflow_live/collaborate.ex:345-350
    - WebhookAuthMethodFormComponent :view action branches and the action_buttons / subtitle slots (form_component.ex:214-215, :246-248, :251, :418-423, :450, :505)
    - webhook_auth_methods_table on_row_select / row_selected? checkbox column (components.ex:17-18, :49-51, :68-77)
    - WebhookAuthMethods.update_trigger_auth_methods/3, find_by_api_key/2, find_by_username_and_password/3, list_for_trigger/1 (webhook_auth_methods.ex:329-392, :504-595); trigger and inbound webhook paths

related:
  - project-settings-setup                # owns the host route and mount
  - workflow-editor (lib/lightning_web/live/workflow_live/collaborate.ex:326-352)   # second home of the auth method form; no annotation id yet
  - channel form (lib/lightning_web/live/channel_live/form_component.ex:187)          # links here
  - lib/lightning/webhook_auth_methods.ex
  - lib/lightning/workflows/webhook_auth_method.ex
  - lib/lightning/workflows/webhook_auth_method_audit.ex
  - lib/lightning_web/plugs/webhook_auth.ex             # enforces methods on inbound webhooks
  - lib/lightning_web/plugs/channel_proxy_plug.ex       # enforces client methods on channels
flows:
  - flow-webhook-auth-method-enforcement
  - flow-channel-proxy-request
---

## 1. Purpose

Project owners and admins use this tab to manage the credentials that callers must present when
they post to the project's webhook triggers and channels: basic auth username and password pairs
and generated API keys. Every member can see which methods exist and what uses them. Without it a
project's inbound endpoints would be open to anyone who learns the URL, and an admin removing a
method would not know which workflows and channels it leaves unprotected.

## 2. What it does

- **See methods and what they protect** (every member)
  - The project's auth methods, with their type and what uses them
  - The list of workflow triggers and channels a method is attached to
- **Create methods** (admins and owners)
  - A basic auth method (name, username, password)
  - An API key method, with the key generated and shown for copying
- **Look after existing methods** (admins and owners)
  - Rename a method
  - Reveal a stored password or API key after re-entering their password or a 2FA code
  - Delete a method after typing DELETE, seeing first which triggers and channels lose it
- Editors, viewers and support users cannot create, change or delete methods
- In a sandbox, the tab points to the parent project instead of offering management

**Straightforwardness: 3 of 5.** The basics are clear, but deleting a method reaches further than the page suggests, and a few messages don't match what actually happens.

### Most surprising behaviours

- **(3)** The delete warning says every listed trigger and channel will become unprotected, even when another method is still attached and keeps them protected, so admins get a false alarm. (6.1, S13)
- **(3)** A deleted method disappears from the list but keeps its name reserved, so creating a new one with that name is refused for a name nobody can see. (6.1)
- **(3)** There's no way to change a password or regenerate a key: only the name can be edited, so rotating a secret means creating a new method, attaching it everywhere and deleting the old one. (8, S09)
- **(3)** Sandboxes share their parent's methods, so deleting one here also removes it from the sandboxes' webhooks, not just this project's. The delete dialog does list those sandbox workflows. (6.2)
- **(3)** Renaming a method to a name another method already has may crash the page and close the dialog with no message, instead of showing an error. (6.1)

## 3. Who can do what

Source: `lib/lightning/policies/project_users.ex:29-37` (`:write_webhook_auth_method` is an admin
action), `:134` (MFA unsatisfied denies), `:160-161` (admin actions need an owner or admin row;
support standing never fills them). Flag computed once at mount, `settings.ex:145-150`. The linked
usage list has no policy gate (`settings.ex:584-611`).

| Action | Viewer | Editor | Admin | Owner | Superuser (no row) | Support (no row, access on) |
|--------|--------|--------|-------|-------|--------------------|-----------------------------|
| See the tab and the method list | yes | yes | yes | yes | no (cannot open the project) | yes |
| Open the linked triggers and channels list | yes | yes | yes | yes | no | yes |
| Create a method | no | no | yes | yes | no | no |
| Rename a method | no | no | yes | yes | no | no |
| Reveal a stored password or API key | no | no | yes | yes | no | no |
| Delete a method | no | no | yes | yes | no | no |
| Any write action in a sandbox | no | no | no | no | no | no |

**Preconditions beyond role**
- Revealing a stored secret requires the viewer's current account password or a valid 2FA code in the same modal session (`webhook_auth_method_form_component.ex:47-56`, `:208-211`).
- Deleting requires typing `DELETE` exactly (`webhook_auth_method_delete_modal.ex:215-227`).
- Edit, delete and linked usage only find methods belonging to the current project (`webhook_auth_methods.ex:604-618`; `settings.ex:559-563`, `:592-596`).
- In a sandbox the management UI is not rendered at all, whatever the role (`settings.html.heex:379-403`).
- A member who has not met the project's MFA requirement never reaches the page (shared-project-scope S05).

## 4. What it touches

**Reads**: `webhook_auth_methods` for the project, excluding ones scheduled for deletion, ordered by name (`webhook_auth_methods.ex:465-472`; `settings.ex:238`); `trigger_webhook_auth_methods`, `triggers`, `workflows`, `channel_auth_methods` (role client), `channels` for usage (`components.ex:35-39`, `:140-143`; `delete_modal.ex:26`); `projects` (parent, for the sandbox link, `settings.ex:108-110`); `users` and `user_totps` for re-authentication (`form_component.ex:208-211`; `accounts.ex:463-467`)

**Writes**:
- `webhook_auth_methods` insert (`webhook_auth_methods.ex:171-187`), update of `name` only (`:258-288`; `webhook_auth_method.ex:74-78`), update of `scheduled_deletion` on delete (`webhook_auth_methods.ex:689-695`)
- `trigger_webhook_auth_methods` and `channel_auth_methods` rows for the method deleted on delete (`webhook_auth_methods.ex:696-703`)
- `user_totps.last_totp_at` when a 2FA code is used to re-authenticate (`user_totp.ex:45-55`)

**Immediate side effects** (in the same request)
- Audit `webhook_auth_method` events: `created` (`webhook_auth_methods.ex:176-178`), `updated` (`:269-279`), `deleted` (`:704-714`), and `removed_from_trigger` per detached trigger (`:735-748`); secrets in audit changes are stored encrypted (`webhook_auth_method_audit.ex:16-26`)
- Channel audit `auth_method_removed` per detached channel (`webhook_auth_methods.ex:750-769`)

**Deferred side effects** (later, elsewhere)
- Oban cron purges methods whose `scheduled_deletion` has passed, daily at 03:00 UTC, only when `purge_deleted_after_days > 0` (`webhook_auth_methods.ex:64-92`; `bootstrap.ex:306-316`)
- Inbound webhooks and channel requests stop accepting or requiring the method as soon as it is detached (`plugs/webhook_auth.ex:55`, `:87-92`; `channel_proxy_plug.ex:176-186`); see proposed flow

**External, non-transactional effects**
- Copying a key or password to the clipboard (Copy hook, `assets/js/hooks/index.ts:738-800`)

**Depends on config**
- `purge_deleted_after_days` (default 7) sets when a deleted method is purged, and whether it ever is (`webhook_auth_methods.ex:771-774`; `bootstrap.ex:273-277`, `:306-316`)

**Product limits**
- Basic auth passwords must be 8 to 72 characters (`webhook_auth_method.ex:85`)
- Method names must be unique within the project (`webhook_auth_method.ex:67-71`; migration `20230926155218_create_webhook_auth_methods_table.exs:17`)
- API keys are 64 lowercase hex characters, generated by the server (`webhook_auth_method.ex:106-108`)

## 5. Scenarios

```gherkin
Feature: Project webhook security
  In order to keep the project's webhook endpoints closed to strangers
  As a project admin
  I want to create, inspect and remove the credentials callers must present

  @S01 @pending
  Scenario: Every member sees the project's auth methods
    # Value: anyone wiring up or debugging an integration can see which credentials the project's endpoints accept, without asking an admin.
    Given project "Malawi HIV" has auth methods "Kobo basic" (basic) and "DHIS2 key" (API)
    And I am a viewer on project "Malawi HIV"
    When I open the project's settings on the "Webhook Security" tab
    Then I see "Kobo basic" with type "Basic"
    And I see "DHIS2 key" with type "API"
    # settings.html.heex:467-472; components.ex:7-13, :78-83; webhook_auth_methods.ex:465-472
    # project_live_test.exs:2366-2379 (all four roles)

  @S02 @pending
  Scenario: Members can see what an auth method protects
    # Value: before changing an integration, a member knows which workflows and channels rely on a credential.
    Given auth method "Kobo basic" is attached to the trigger of workflow "Intake" and to channel "Lab results"
    And I am a viewer on project "Malawi HIV"
    When I open the "Webhook Security" tab
    Then the row for "Kobo basic" shows "1 trigger, 1 channel"
    When I click "1 trigger, 1 channel"
    Then I see "Workflow triggers (1)" listing "Intake"
    And I see "Channels (1)" listing "Lab results"
    And "Intake" links to the workflow editor with the trigger selected
    And "Lab results" links to "/projects/<project_id>/channels/<channel_id>/edit"
    # settings.html.heex:487-512; settings.ex:584-611; components.ex:106-128, :136-217
    # project_live_test.exs:2381-2427

  @S03 @pending
  Scenario: An unused auth method says so
    # Value: admins can spot credentials nothing uses and clean them up.
    Given auth method "Old key" is attached to nothing
    When I open the "Webhook Security" tab as an owner
    Then the row for "Old key" shows "No associated triggers or channels..."
    And there is no usage link for "Old key"
    # settings.html.heex:505-510; project_live_test.exs:2429-2440

  @S04 @pending
  Scenario: A project with no auth methods offers to create one
    # Value: an admin setting up the first protected webhook finds the starting point.
    Given project "Malawi HIV" has no auth methods
    And I am an admin on project "Malawi HIV"
    When I open the "Webhook Security" tab
    Then I see "No auth methods found."
    And I see an enabled "Create a new auth method" button
    # settings.html.heex:473-486; components.ex:43-44

  @S05 @pending
  Scenario: Admin creates a basic auth method
    # Value: an admin can require a username and password on the project's webhooks without a deploy or a superuser.
    Given I am an admin on project "Malawi HIV"
    When I click "New auth method"
    Then I see "Basic HTTP Authentication (username & password)" and "API Key Authentication (‘x-api-key’ header)"
    When I choose "Basic HTTP Authentication" and click "Next"
    Then I see "Create a \"basic auth\" method"
    When I fill "Auth method name" with "Kobo basic", "Username" with "kobo", "Password" with "testpassword123"
    And I click "Create auth method"
    Then I see "Webhook auth method created successfully"
    And the modal closes
    And "Kobo basic" appears in the list with type "Basic"
    And an audit event "created" is recorded for "Kobo basic"
    # settings.ex:526-547; form_component.ex:71-86, :171-190, :223-231, :324-395, :443-494
    # webhook_auth_methods.ex:171-187; project_live_test.exs:2442-2501

  @S06 @pending
  Scenario: Admin creates an API key method and can copy the key before saving
    # Value: the admin gets a strong key the server generated and can hand it to the calling system straight away.
    Given I am an admin on project "Malawi HIV"
    When I click "New auth method", choose "API Key Authentication" and click "Next"
    Then I see "Create an \"API token\" method"
    And the "API Key" field shows a 64-character key in full with a "Copy" button
    When I fill "Auth method name" with "DHIS2 key" and click "Create auth method"
    Then I see "Webhook auth method created successfully"
    And "DHIS2 key" appears in the list with type "API"
    And its stored key equals the key that was shown
    # webhook_auth_methods.ex:806-819; webhook_auth_method.ex:98-108; form_component.ex:200-206, :498-520, :569-602

  @S07 @pending
  Scenario: A basic auth password must be 8 to 72 characters
    # Value: webhooks can't be protected by a trivially guessable password.
    Given I am creating a basic auth method on project "Malawi HIV"
    When I fill "Password" with "short"
    Then I see a length error on "Password"
    And "Create auth method" is disabled
    # webhook_auth_method.ex:80-85; form_component.ex:88-115, :421-425

  @S08 @pending
  Scenario: Two auth methods in a project cannot share a name
    # Value: members can tell methods apart in the list, the workflow editor and the delete warning.
    Given project "Malawi HIV" has an auth method "Kobo basic"
    And I am creating a basic auth method on project "Malawi HIV"
    When I submit the name "Kobo basic" with a valid username and password
    Then I see "must be unique within the project"
    And the project still has one method named "Kobo basic"
    # webhook_auth_method.ex:67-71; migration 20230926155218_create_webhook_auth_methods_table.exs:17; form_component.ex:187-188

  @S09 @pending
  Scenario: Admin renames an auth method without changing its secret
    # Value: an admin can correct a name without breaking callers that already use the credential.
    Given basic auth method "Kobo basic" with username "kobo"
    And I am an admin on project "Malawi HIV"
    When I click "View" on "Kobo basic"
    Then the "Username" field is disabled
    And the password is masked behind a "Show" button
    When I change "Auth method name" to "Kobo intake" and click "Save changes"
    Then I see "Webhook auth method updated successfully"
    And "Kobo intake" appears in the list
    And the method's username and password are unchanged
    And an audit event "updated" is recorded
    # settings.html.heex:514-529, :440-450; form_component.ex:125-144, :445-479; webhook_auth_method.ex:74-78
    # webhook_auth_methods.ex:258-288; project_live_test.exs:2564-2621

  @S10 @pending
  Scenario Outline: A stored secret is hidden until the admin re-enters their password
    # Value: someone at an unattended, signed-in admin session can't read off a webhook credential.
    Given <type> auth method "<name>" exists on project "Malawi HIV"
    And I am an admin on project "Malawi HIV"
    When I open "<name>" with "View"
    Then the page does not contain the stored <secret>
    And the <secret> field shows "Show"
    When I click "Show"
    Then I see "You're required to reauthenticate yourself before viewing the webhook <label>"
    When I submit the password "wrongpass"
    Then I see "Invalid! Please try again"
    When I submit my account password
    Then the <secret> is displayed with a "Copy" button
    # form_component.ex:42-56, :208-211, :264-322, :526-614
    # project_live_test.exs:2728-2800 (API key), :2802-2884 (password)

    Examples:
      | type  | name       | secret   | label    |
      | API   | DHIS2 key  | API key  | API Key  |
      | basic | Kobo basic | password | Password |

  @S11 @pending
  Scenario: A 2FA code also unlocks a stored secret
    # Value: an admin who signs in with an authenticator can reveal a secret without their password.
    Given I am an admin on project "Malawi HIV" with an authenticator app enrolled
    And I am viewing API key method "DHIS2 key" and clicked "Show"
    When I submit a valid 6-digit code in "2FA Code" and leave "Password" empty
    Then the API key is displayed with a "Copy" button
    # form_component.ex:208-211, :305; accounts.ex:463-467; user_totp.ex:45-65

  @S12 @pending
  Scenario: Admin deletes an auth method after confirming
    # Value: an admin can retire a leaked or unused credential, and a slip of the mouse can't do it.
    Given auth method "Old key" exists on project "Malawi HIV"
    And I am an owner on project "Malawi HIV"
    When I click "Delete" on "Old key"
    Then I see "Delete Authentication Method"
    When I type "diel" in the confirmation field
    Then I see "Please type DELETE to confirm"
    And "Delete authentication method" is disabled
    When I type "DELETE" and submit
    Then I see "Your Webhook Authentication method has been deleted."
    And "Old key" is no longer listed
    And "Old key" is no longer attached to any trigger or channel
    And an audit event "deleted" is recorded
    # settings.html.heex:540-557, :452-460; settings.ex:549-582; delete_modal.ex:44-73, :182-201, :215-227
    # webhook_auth_methods.ex:672-733; project_live_test.exs:2951-3021

  @S13 @pending
  Scenario: The delete modal warns which triggers and channels lose the method
    # Value: an admin sees which endpoints become unprotected before they delete, and can add another method first.
    Given auth method "Kobo basic" is attached to the trigger of workflow "My Workflow" and to channel "My Channel"
    And I am an owner on project "Malawi HIV"
    When I click "Delete" on "Kobo basic"
    Then I see "1 workflow trigger will stop requiring authentication" listing "My Workflow"
    And I see "1 channel will accept unauthenticated requests" listing "My Channel"
    And "My Channel" links to "/projects/<project_id>/channels/<channel_id>/edit"
    And I see "These channels stay enabled and keep forwarding requests to their destination with the project credential attached."
    # delete_modal.ex:113-180, :208-213; project_live_test.exs:2886-2930

  @S14 @pending
  Scenario: The delete modal says when nothing depends on the method
    # Value: an admin can delete an unused credential knowing nothing breaks.
    Given auth method "Old key" is attached to nothing
    When I click "Delete" on "Old key" as an owner
    Then I see "which is used by no workflows or channels"
    And I do not see "will accept unauthenticated requests"
    # delete_modal.ex:105-112; project_live_test.exs:2932-2949

  @S15 @pending
  Scenario Outline: Members who aren't admins can't change auth methods
    # Value: only people trusted with access decisions can open or close the project's endpoints.
    Given auth method "Kobo basic" exists on project "Malawi HIV"
    And I am a <role> on project "Malawi HIV"
    When I open the "Webhook Security" tab
    Then the "New auth method" button is disabled
    And the "Edit" and "Delete" links on "Kobo basic" do nothing
    When I send the "show_modal" event for "<target>" directly
    Then I see "You are not authorized to perform this action"
    And no auth method modal opens
    # settings.html.heex:405-415, :530-538, :557-564; settings.ex:531, :544-546, :558, :578-581
    # project_live_test.exs:2503-2531, :2533-2562, :2623-2642, :2688-2726, :3023-3049

    Examples:
      | role   | target                     |
      | editor | new_webhook_auth_method    |
      | viewer | new_webhook_auth_method    |
      | editor | edit_webhook_auth_method   |
      | viewer | edit_webhook_auth_method   |
      | editor | delete_webhook_auth_method |
      | viewer | delete_webhook_auth_method |

  @S16 @pending
  Scenario: An admin can't reach another project's auth method by id
    # Value: admin rights in one project never expose or alter another project's webhook credentials.
    Given auth method "someone-elses-auth" belongs to a different project
    And I am an admin on project "Malawi HIV"
    When I send "show_modal" for edit, delete or linked usage with that method's id
    Then I see "Webhook auth method not found"
    And I do not see "someone-elses-auth"
    # settings.ex:559-569, :592-601; webhook_auth_methods.ex:604-618; project_live_test.exs:2645-2686

  @S17 @pending @variant:sandbox
  Scenario: A sandbox points to the parent for webhook security
    # Value: someone working in a sandbox learns its webhooks use the parent's credentials and where to change them.
    Given sandbox "dev" of project "Malawi HIV"
    And I am an owner of sandbox "dev"
    When I open the settings of sandbox "dev" on the "Webhook Security" tab
    Then I see "Webhook authentication is managed in the parent project"
    And I see "Manage them in the parent project (Malawi HIV)" linking to "/projects/<parent_id>/settings#webhook_security"
    And I do not see "New auth method" or an auth method table
    # settings.html.heex:379-403; sandbox_settings_test.exs:258-263; parent shows the table instead, :91-97

  @S18 @pending
  Scenario: Creating, renaming or deleting a method hands off to webhook enforcement
    # Value: the credential managed here is the one inbound requests are checked against.
    Given I am an admin on project "Malawi HIV"
    When I create, rename or delete an auth method
    Then the flow "flow-webhook-auth-method-enforcement" reflects that method's current state
    # handoff only; webhook_auth.ex:47-92, channel_proxy_plug.ex:176-186
```

## 6. Unclear value

### 6.1 Possible bugs

| What | Where | What a user sees | Disposition |
|------|-------|------------------|-------------|
| Renaming a method to a name another method already has: `update_changeset` declares no `unique_constraint`, so the unique index raises instead of returning an error | `webhook_auth_method.ex:74-78`; `webhook_auth_methods.ex:265-280`; migration `20230926155218_create_webhook_auth_methods_table.exs:17` | the LiveView likely crashes and reconnects, closing the modal with no message (not run) | fix |
| The live uniqueness check compares the typed name to a list of structs, so it never matches | `webhook_auth_method_form_component.ex:25-30`, `:103-111` | no "must be unique" hint while typing; on create it only appears after submit, on rename see the row above | fix |
| A deleted method keeps its name reserved until it is purged (forever under `purge-disabled`), but it is hidden from the list | `webhook_auth_methods.ex:465-472`, `:687-695`; unique index above | "must be unique within the project" for a name nobody can see | decide |
| Delete warning says each listed trigger "will stop requiring authentication" and each channel "will accept unauthenticated requests" even when the trigger or channel has another method attached | `webhook_auth_method_delete_modal.ex:123-180`; enforcement uses any attached method, `plugs/webhook_auth.ex:87-92`, `channel_proxy_plug.ex:180-186` | an alarming, wrong warning when other methods still protect the endpoint | fix |
| Admins open a method with a link labelled "View" that leads to an editable form with "Save changes"; non-admins see an "Edit" link that does nothing | `settings.html.heex:514-538`; `form_component.ex:426-430` | label doesn't match the control for either audience | fix |
| A failed delete (for example the method was already deleted from another tab) assigns `:changeset`, which the modal never renders | `webhook_auth_method_delete_modal.ex:67-68`; `webhook_auth_methods.ex:677-685` | clicking "Delete authentication method" appears to do nothing | fix |
| Usernames are slugified (lowercased, spaces to hyphens) during validation but not on save | `form_component.ex:93-95`, `:117-123` vs `:171-176` | the stored username can differ from what the validated form implied, depending on whether the browser kept the user's typed value | decide |

### 6.2 Quirks and implementation details

| What | Where | Disposition |
|------|-------|-------------|
| A masked password is one asterisk per character, so its length is visible before re-authentication | `form_component.ex:533-535`, `:558-562` | decide |
| A masked API key shows its last five characters behind up to 15 asterisks | `form_component.ex:604-613` | preserve |
| Re-authentication accepts a password or a TOTP code, not a backup code; the "2FA Code" field shows even for users with no authenticator | `form_component.ex:208-211`, `:305` | decide |
| Re-authentication lasts only while that modal is open; reopening asks again | `form_component.ex:32` | preserve |
| Delete is a soft delete with `scheduled_deletion` set, though the flash says "has been deleted"; there is no restore in the UI | `webhook_auth_methods.ex:672-733`; `delete_modal.ex:61-64` | preserve |
| Server-side save and delete events in the components don't re-check the policy; they rely on the mount-time flag that gated opening the modal, and on shared-project-scope S08 remounting on a role change | `form_component.ex:38-40`; `delete_modal.ex:44-73`; `settings.ex:145-150` | decide |
| `show_modal` for edit or delete without an `id` matches no clause and crashes the LiveView; only reachable by a crafted event | `settings.ex:526-611` | preserve |
| `find_for_project` doesn't exclude methods scheduled for deletion, so a crafted id can open a deleted method's edit form | `webhook_auth_methods.ex:604-618` | decide |
| The sandbox notice links to the direct parent; for a nested sandbox that parent shows the same notice again | `settings.html.heex:394-402`; `settings.ex:110` | decide |
| A sandbox member who isn't on the parent follows the notice link into the parent's not-found redirect (shared-project-scope S03) | `settings.html.heex:394-402` | preserve |
| Deleting a method in the parent also detaches it from sandbox triggers, which share the parent's methods, and the delete modal lists those sandbox workflows | `webhook_auth_methods.ex:107-112`, `:696-699`; `sandboxes.ex:1278-1287` | preserve |
| Workflow and channel links in the usage and delete modals use `navigate` with `target="_blank"`, so they open in a new tab | `components.ex:174-183`, `:196-205`; `delete_modal.ex:134-142`, `:162-170` | preserve |
| Modal titles and column headers are title case ("Webhook Authentication Method", "Delete Authentication Method", "Associated Triggers & Channels", "Linked Triggers & Channels") | `form_component.ex:233`; `delete_modal.ex:83`; `components.ex:59`, `:150` | decide |
| Sandbox mode drops the role notice for this tab | shared-project-settings-tab-chrome 6.2 row "In a sandbox, Security passes a nil message..."; `settings.html.heex:380-383` | preserve |
| List order is by name using the database collation | `webhook_auth_methods.ex:470` | preserve |

### 6.3 Unreachable or dead code

| What | Where | Why unreachable |
|------|-------|-----------------|
| `show_modal` handlers and the modal state in a sandbox | `settings.ex:526-611`; `settings.html.heex:417-466` | the modals sit in the non-sandbox branch, so a crafted event in a sandbox sets state nothing renders |
| Table `on_row_select` checkbox column | `components.ex:17-18`, `:49-51`, `:68-77` | the only caller (`settings.html.heex:467-472`) never passes it |
| Form component `:view` action, `action_buttons` and `subtitle` slots | `form_component.ex:214-215`, `:246-248`, `:418-423` | no caller passes `action={:view}` or these slots |
| Form component create-for-trigger branch | `form_component.ex:146-169` | this view passes `trigger={nil}`; collaborate.ex:335-351 passes no `trigger` |
| `error_msg` is only set after `toggle-2fa`; the re-auth form reads it | `form_component.ex:44`, `:285` | not dead, but the form is unreachable before `toggle-2fa` assigns it |
| Table preloads `:project` per method | `components.ex:35-39` | nothing in the table reads it |

### 6.4 Performance and operational limits

| What | Where | User-visible? | Disposition |
|------|-------|---------------|-------------|
| The table re-preloads triggers, project and channels on every render of the settings page | `components.ex:32-40` | no | fix |
| Method list is unpaginated | `webhook_auth_methods.ex:465-472` | no | preserve |
| Purge runs once a day at 03:00 UTC with `max_attempts: 1`; a failed run waits a day | `webhook_auth_methods.ex:19-21`; `bootstrap.ex:313-314` | no | preserve |
| Re-authentication attempts are not rate limited (each costs a bcrypt check) | `form_component.ex:47-56`, `:208-211` | no | decide |

### 6.5 Things seen but not understood

- The Copy button gains `phx-hook="Copy"` on an existing element when sudo mode turns on (`form_component.ex:545`, `:591`); not verified that LiveView mounts the hook on that patch, so Copy after reveal may not work in the browser.
- Whether a parent re-render while the edit modal is open calls the component's `update/2` again, which would reset `sudo_mode?` to false (`form_component.ex:12-35`) and re-mask a revealed secret; depends on LiveView change tracking.
- The edit form posts the full field set but `update_changeset` casts only `name` (`webhook_auth_method.ex:74-78`); the extra params are silently dropped. Intended, but the form doesn't say username and type are fixed beyond disabling the field.

## 7. Not migrating

| Item | Reason | Decided by | Date |
|------|--------|------------|------|

## 8. Open questions

- Should renaming be the only edit, or should admins be able to rotate a password or regenerate an API key in place? Today rotation means create, re-attach and delete.
- Should a deleted method's name be freed immediately, given it is hidden from the list?
- Should revealing a stored secret also be audited?
- Should the sandbox notice link to the root project that actually owns the methods?
- Where does the workflow editor's copy of the form get its annotation, and should the form component become a shared annotation (see below)?

## Proposed flows

- `flow-webhook-auth-method-enforcement`: a method created here is attached to a webhook trigger in the workflow editor (or a channel as a client method); inbound requests to `/i/...` or the channel proxy then need its credentials, and deleting it here detaches it so the endpoint stops requiring it. Surfaces: project-settings-webhook-security, workflow-editor (collaborate.ex:326-352), channel form, plug:WebhookAuth (`plugs/webhook_auth.ex`), plug:ChannelProxyPlug (`channel_proxy_plug.ex:176-186`).
- Not a flow, for the lead: `capability:webhook-auth-method-purge`, the daily Oban cron that hard-deletes methods past `scheduled_deletion` (`webhook_auth_methods.ex:64-92`; `bootstrap.ex:306-316`). Surfaces: worker:Lightning.WebhookAuthMethods(purge_deleted).

## Proposed shared

- `shared-webhook-auth-method-form`: `WebhookAuthMethodFormComponent` (type picker, basic and API fields, masked secrets, re-authentication, Copy hook) rendered by both project settings and the collaborative workflow editor. Surfaces: project-settings-webhook-security (`settings.html.heex:429-450`), workflow-editor (`collaborate.ex:335-351`).

## Lead resolution (batch 2)

- `flow-webhook-auth-method-enforcement` created as proposed.
- `shared-webhook-auth-method-form` created; the editor's trigger inspector inherits it too.
- The purge cron is deferred to the capabilities pass as `capability:webhook-auth-method-purge`.
