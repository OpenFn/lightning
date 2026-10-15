---
id: shared-webhook-auth-method-form
type: shared
title: Webhook auth method form
status: not-started
owner:

trigger:
  old_route: rendered by /projects/:project_id/settings#webhook_security and /projects/:project_id/w/:id (and /w/new)
  new_route:
  old_route_disposition: unchanged
  reachable_when:
    - the host decides who opens it; neither component does any authorization of its own (webhook_auth_method_form_component.ex:11-56; webhook_auth_method_delete_modal.ex:10-73)
    - project-settings-webhook-security opens create, edit and delete for a viewer with :write_webhook_auth_method on a non-sandbox project (settings.ex:526-582; settings.html.heex:379-403, :417-460)
    - workflow-editor-inspectors opens create only, from "Create a new authentication method" in the trigger's Authentication section, shown when the session context grants can_write_webhook_auth_method (WebhookConfigureStep.tsx:107, :370-377; WebhookAuthMethodSelect.tsx:109-118, :229-238; collaborate.ex:211-223, :326-352)

inherits: []                                  # the hosts carry shared-project-scope; the form adds nothing to it

url_params: []                                # the components read none

config_variants:
  default: { purge_deleted_after_days: 7 }    # read under this variant (bootstrap.ex:273-277)
  purge-disabled: { purge_deleted_after_days: 0 }   # a deleted method's scheduled_deletion is "now" and no purge cron runs (webhook_auth_methods.ex:771-774; bootstrap.ex:306-316); read from code only

inventory:
  routes: []                                  # host routes are owned by project-settings-setup and the workflow editor views
  events:
    - WorkflowLive.WebhookAuthMethodFormComponent#choose_auth_type      # webhook_auth_method_form_component.ex:71-86
    - WorkflowLive.WebhookAuthMethodFormComponent#validate_auth_type    # :58-69
    - WorkflowLive.WebhookAuthMethodFormComponent#validate              # :88-115
    - WorkflowLive.WebhookAuthMethodFormComponent#save                  # :38-40, :125-190
    - WorkflowLive.WebhookAuthMethodFormComponent#toggle-2fa            # :42-45
    - WorkflowLive.WebhookAuthMethodFormComponent#reauthenticate-user   # :47-56
    - WorkflowLive.WebhookAuthMethodDeleteModal#validate_deletion       # webhook_auth_method_delete_modal.ex:32-42
    - WorkflowLive.WebhookAuthMethodDeleteModal#perform_deletion        # :44-73
  js_hooks:
    - Copy (API key and revealed password buttons; webhook_auth_method_form_component.ex:545, :591; assets/js/hooks/index.ts:738-800)
  policies: []                                # none in either component; see section 3
  workers: []                                 # the daily purge belongs to capability:webhook-auth-method-purge (webhook_auth_methods.ex:64-92)
  api_endpoints: []
  emails: []
  config:
    - :lightning, :purge_deleted_after_days (webhook_auth_methods.ex:771-774)
  not_reachable_here:
    - WebhookAuthMethodFormComponent create-for-trigger branch and WebhookAuthMethods.create_auth_method/3 (form_component.ex:146-169; webhook_auth_methods.ex:189-218); settings passes trigger={nil} (settings.html.heex:436, :447), the editor passes no trigger (collaborate.ex:335-351)
    - WebhookAuthMethodFormComponent :view action and the subtitle / action_buttons slots (form_component.ex:214-215, :246-248, :251, :418-423, :450, :505); no host passes them

related:
  - project-settings-webhook-security        # hosts create, edit (rename, reveal) and delete
  - workflow-editor-inspectors               # hosts create only, from the trigger inspector via collaborate.ex:326-352
  - lib/lightning_web/live/workflow_live/webhook_auth_method_form_component.ex
  - lib/lightning_web/live/workflow_live/webhook_auth_method_delete_modal.ex
  - lib/lightning/webhook_auth_methods.ex
  - lib/lightning/workflows/webhook_auth_method.ex
  - lib/lightning/workflows/webhook_auth_method_audit.ex
flows:
  - flow-webhook-auth-method-enforcement
---

## 1. Purpose

Project owners and admins use this form to create the credentials callers must present to a
project's webhook triggers and channels, either from project settings or without leaving the
trigger they are configuring in the workflow editor. In settings the same component also renames
a method and reveals its stored secret, and a companion modal deletes it. Without it an admin
could not protect an endpoint, could not hand a caller the key it needs, and could remove a
credential without knowing which endpoints it leaves open.

## 2. What it does

- **Create a method** (admins, from project settings or a trigger in the workflow editor)
  - Admins choose basic auth or API key, then fill in a name and either a username and password or a server-generated key they can copy before saving
  - Admins cancel the form without creating anything
  - Saving from the editor closes the form and tells every open editor of that workflow about the new method
- **Manage an existing method** (admins, project settings only)
  - Admins rename a method; its username, password and key cannot change
  - Admins reveal a stored password or API key after re-entering their password or a 2FA code
- **Delete a method** (admins, project settings only)
  - Admins delete a method after typing DELETE, seeing first which triggers and channels lose it

**Straightforwardness: 3 of 5.** The form itself is ordinary; the surprises are a permission gap in the editor and a delete warning and reveal step that don't do what they say.

### Most surprising behaviours

- **(2)** In the workflow editor, only the "create" link is hidden from non-admins. Nothing checks again when the form opens or saves, so an editor or viewer who sends the request directly can create a project auth method. (6.1)
- **(2)** The delete warning says each trigger "will stop requiring authentication" and each channel "will accept unauthenticated requests", even when another method still protects them. (6.1)
- **(3)** "Show" on a basic auth password asks you to re-authenticate, then still doesn't show the password; it only turns the button into "Copy". (6.1)
- **(3)** A deleted method's name stays taken until it's purged, so admins get "must be unique" for a name they can't see anywhere, and renaming to a name already in use may crash the form with no message. (6.1)
- **(3)** In a sandbox, creating a method from the editor makes one that belongs to the sandbox, while the sandbox's settings say webhook auth is managed in the parent project. (6.2)

## 3. Who can do what

Neither component checks a policy. Every gate is the host's: settings checks
`:write_webhook_auth_method` when opening a modal (`settings.ex:531`, `:558`; flag from
`settings.ex:145-150`); the editor hides the create link unless the session context grants it
(`workflow_channel.ex:1522-1523`; `WebhookConfigureStep.tsx:107`) and checks nothing on the server
(`collaborate.ex:211-223`, see 6.1). Policy: `lib/lightning/policies/project_users.ex:29-37`,
`:134`, `:160-161`.

| Action | Viewer | Editor | Admin | Owner | Superuser (no row) | Support (no row, access on) |
|--------|--------|--------|-------|-------|--------------------|-----------------------------|
| See the form | no | no | yes | yes | no | no |
| Create a method | no | no | yes | yes | no | no |
| Rename a method | no | no | yes | yes | no | no |
| Reveal a stored secret | no | no | yes | yes | no | no |
| Delete a method | no | no | yes | yes | no | no |

**Preconditions beyond role**
- Revealing a stored secret needs the viewer's current account password or a valid, unused 2FA code, entered in the same open modal (`form_component.ex:47-56`, `:208-211`; `user_totp.ex:58-64`).
- Deleting needs `DELETE` typed exactly (`delete_modal.ex:215-227`).
- A member who has not met the project's MFA requirement is denied every action (`project_users.ex:134`).
- The settings host only opens methods that belong to the current project (`settings.ex:559-563`; `webhook_auth_methods.ex:604-618`); a new method always takes the host project's id (`settings.ex:536-538`; `collaborate.ex:214-216`; `form_component.ex:200-206`).

## 4. What it touches

**Reads**: `webhook_auth_methods` for the project, excluding ones scheduled for deletion (`form_component.ex:25-30`; `webhook_auth_methods.ex:465-472`); `trigger_webhook_auth_methods`, `triggers`, `workflows`, `channel_auth_methods` (role client), `channels` for the delete warning (`delete_modal.ex:24-27`; `webhook_auth_method.ex:43-49`); `users`, `user_totps` for re-authentication (`form_component.ex:208-211`; `accounts.ex:463-467`)

**Writes**:
- `webhook_auth_methods` insert (`webhook_auth_methods.ex:171-187`); update of `name` only (`:258-288`; `webhook_auth_method.ex:74-78`); `scheduled_deletion` set on delete (`webhook_auth_methods.ex:687-695`)
- `trigger_webhook_auth_methods` and `channel_auth_methods` rows for a deleted method, removed in the same transaction (`webhook_auth_methods.ex:696-703`)
- `user_totps.last_totp_at` when a 2FA code re-authenticates (`user_totp.ex:45-56`)

**Immediate side effects** (in the same request)
- Audit `webhook_auth_method` events `created` (`webhook_auth_methods.ex:176-178`), `updated` (`:269-279`), `deleted` (`:704-714`) and one `removed_from_trigger` per detached trigger (`:735-748`); secrets in audit changes are stored encrypted (`webhook_auth_method_audit.ex:16-26`)
- Channel audit `auth_method_removed` per detached channel (`webhook_auth_methods.ex:750-769`)
- Flash "Webhook auth method created successfully", "Webhook auth method updated successfully" or "Your Webhook Authentication method has been deleted." (`form_component.ex:137`, `:162`, `:183`; `delete_modal.ex:61-64`)
- Editor host only: the `on_save` callback makes Collaborate broadcast `webhook_auth_methods_updated` on `workflow:collaborate:<workflow_id>` (`collaborate.ex:344-349`, `:432-442`, `:534-561`), which WorkflowChannel pushes to each client (`workflow_channel.ex:960-968`)

**Deferred side effects** (later, elsewhere)
- A deleted method is hard-deleted by the daily purge once `scheduled_deletion` passes (`webhook_auth_methods.ex:64-92`); owned by capability:webhook-auth-method-purge
- Inbound requests stop requiring a deleted method at once; owned by flow-webhook-auth-method-enforcement

**External, non-transactional effects**
- Copy to clipboard (Copy hook, `assets/js/hooks/index.ts:738-800`)

**Depends on config**
- `purge_deleted_after_days` sets the `scheduled_deletion` date (`webhook_auth_methods.ex:771-774`)

**Product limits**
- Basic auth passwords are 8 to 72 characters (`webhook_auth_method.ex:85`)
- Method names are unique within a project (`webhook_auth_method.ex:67-71`; migration `20230926155218_create_webhook_auth_methods_table.exs:17`)
- API keys are 64 lowercase hex characters, generated by the server (`webhook_auth_method.ex:106-108`; `webhook_auth_methods.ex:806-819`)

## 5. Scenarios

Steps say "the auth method form" for either host. Steps that only the settings host reaches say so.

```gherkin
Feature: Webhook auth method form
  In order to keep a project's webhook endpoints closed to strangers
  As a project admin
  I want to create, inspect and remove the credentials callers must present

  @S01 @pending
  Scenario: Admin creates a basic auth method
    # Value: an admin can require a username and password on the project's webhooks without a deploy or a superuser.
    Given I am an admin on project "Malawi HIV"
    And I have opened the auth method form
    Then I see "Basic HTTP Authentication (username & password)" and "API Key Authentication (‘x-api-key’ header)"
    And "Next" is disabled
    When I choose "Basic HTTP Authentication" and click "Next"
    Then I see "Create a \"basic auth\" method"
    When I fill "Auth method name" with "Kobo basic", "Username" with "kobo", "Password" with "testpassword123"
    And I click "Create auth method"
    Then I see "Webhook auth method created successfully"
    And project "Malawi HIV" has a basic auth method "Kobo basic"
    And an audit event "created" is recorded for "Kobo basic"
    # form_component.ex:71-86, :171-190, :223-231, :324-395, :443-494
    # webhook_auth_methods.ex:171-187; project_live_test.exs:2442-2501

  @S02 @pending
  Scenario: Admin creates an API key method and can copy the key before saving
    # Value: the admin gets a strong key the server generated and can hand it to the calling system straight away.
    Given I am an admin on project "Malawi HIV" with the auth method form open
    When I choose "API Key Authentication" and click "Next"
    Then I see "Create an \"API token\" method"
    And the "API Key" field shows a 64-character key in full with a "Copy" button
    When I fill "Auth method name" with "DHIS2 key" and click "Create auth method"
    Then I see "Webhook auth method created successfully"
    And the stored key of "DHIS2 key" equals the key that was shown
    # webhook_auth_methods.ex:806-819; webhook_auth_method.ex:98-108
    # form_component.ex:200-206, :498-520, :569-602

  @S03 @pending
  Scenario: A basic auth password must be 8 to 72 characters
    # Value: webhooks can't be protected by a trivially guessable password.
    Given I am creating a basic auth method on project "Malawi HIV"
    When I fill "Password" with "short"
    Then I see a length error on "Password"
    And "Create auth method" is disabled
    # webhook_auth_method.ex:80-85; form_component.ex:88-115, :421-425

  @S04 @pending
  Scenario: Two auth methods in a project cannot share a name
    # Value: members can tell methods apart in the settings list, the trigger's picker and the delete warning.
    Given project "Malawi HIV" has an auth method "Kobo basic"
    And I am creating a basic auth method on project "Malawi HIV"
    When I submit the name "Kobo basic" with a valid username and password
    Then I see "must be unique within the project"
    And the project still has one method named "Kobo basic"
    # webhook_auth_method.ex:67-71; migration 20230926155218_create_webhook_auth_methods_table.exs:17; form_component.ex:187-188

  @S05 @pending
  Scenario: Cancelling the form creates nothing
    # Value: an admin who opened the form by mistake can back out without leaving a stray credential behind.
    Given I am creating a basic auth method on project "Malawi HIV" with name "Draft"
    When I click "Cancel"
    Then the auth method form closes
    And project "Malawi HIV" has no method named "Draft"
    # form_component.ex:432-434; settings host settings.ex:451-455; editor host collaborate.ex:225-233, WebhookConfigureStep.tsx:116-134

  @S06 @pending
  Scenario: Admin renames an auth method without changing its secret
    # Value: an admin can correct a name without breaking callers that already use the credential.
    Given basic auth method "Kobo basic" with username "kobo"
    And I am an admin with "Kobo basic" open in the auth method form from project settings
    Then the "Username" field is disabled
    And the password field shows "Show"
    When I change "Auth method name" to "Kobo intake" and click "Save changes"
    Then I see "Webhook auth method updated successfully"
    And the method's username and password are unchanged
    And an audit event "updated" is recorded
    # form_component.ex:125-144, :445-479; webhook_auth_method.ex:74-78
    # webhook_auth_methods.ex:258-288; project_live_test.exs:2564-2621

  @S07 @pending
  Scenario Outline: A stored secret stays out of the page until the admin re-authenticates
    # Value: someone at an unattended, signed-in admin session can't read off a webhook credential.
    Given <type> auth method "<name>" exists on project "Malawi HIV"
    And I am an admin with "<name>" open in the auth method form from project settings
    Then the page does not contain the stored <secret>
    And the <secret> button reads "Show"
    When I click "Show"
    Then I see "You're required to reauthenticate yourself before viewing the webhook <label>"
    When I submit the password "wrongpass"
    Then I see "Invalid! Please try again"
    When I submit my account password
    Then the page contains the stored <secret>
    And the <secret> button reads "Copy"
    # form_component.ex:42-56, :208-211, :264-322, :526-614
    # project_live_test.exs:2728-2800 (API key), :2802-2884 (password)

    Examples:
      | type  | name       | secret   | label    |
      | API   | DHIS2 key  | API key  | API Key  |
      | basic | Kobo basic | password | Password |

  @S08 @pending
  Scenario: A 2FA code also unlocks a stored secret
    # Value: an admin who signs in with an authenticator can reveal a secret without typing their password.
    Given I am an admin on project "Malawi HIV" with an authenticator app enrolled
    And I have API key method "DHIS2 key" open from project settings and clicked "Show"
    When I submit a valid 6-digit code in "2FA Code" and leave "Password" empty
    Then the API key button reads "Copy"
    # form_component.ex:208-211, :305; accounts.ex:463-467; user_totp.ex:45-65

  @S09 @pending
  Scenario: Admin deletes an auth method after confirming
    # Value: an admin can retire a leaked or unused credential, and a slip of the mouse can't do it.
    Given auth method "Old key" exists on project "Malawi HIV"
    And I am an owner with the delete modal open for "Old key"
    Then I see "Delete Authentication Method"
    When I type "diel" in the confirmation field
    Then I see "Please type DELETE to confirm"
    And "Delete authentication method" is disabled
    When I type "DELETE" and submit
    Then I see "Your Webhook Authentication method has been deleted."
    And "Old key" is scheduled for deletion and attached to no trigger or channel
    And audit events "deleted" and "removed_from_trigger" are recorded
    # delete_modal.ex:44-73, :182-201, :215-227; webhook_auth_methods.ex:672-769
    # project_live_test.exs:2951-3021

  @S10 @pending
  Scenario: The delete modal names the triggers and channels that lose the method
    # Value: an admin sees which endpoints change before they delete, and can add another method first.
    Given auth method "Kobo basic" is attached to the trigger of workflow "My Workflow" and to channel "My Channel"
    When I open the delete modal for "Kobo basic" as an owner
    Then I see "1 workflow trigger will stop requiring authentication" listing "My Workflow"
    And I see "1 channel will accept unauthenticated requests" listing "My Channel"
    And "My Workflow" links to the workflow editor with that trigger selected
    And "My Channel" links to "/projects/<project_id>/channels/<channel_id>/edit"
    # delete_modal.ex:113-180, :208-213; project_live_test.exs:2886-2930

  @S11 @pending
  Scenario: The delete modal says when nothing depends on the method
    # Value: an admin can delete an unused credential knowing nothing breaks.
    Given auth method "Old key" is attached to nothing
    When I open the delete modal for "Old key" as an owner
    Then I see "which is used by no workflows or channels"
    And I do not see "will accept unauthenticated requests"
    # delete_modal.ex:105-112; project_live_test.exs:2932-2949

  @S12 @pending
  Scenario: Creating a method from the workflow editor hands off to every open editor
    # Value: the method an admin just created is offered on the trigger without reloading, for them and for collaborators.
    Given I am an owner editing workflow "Intake" on project "Malawi HIV"
    And I have opened the auth method form from the trigger's "Create a new authentication method" link
    When I create basic auth method "Kobo basic"
    Then the auth method form closes
    And "webhook_auth_methods_updated" is broadcast on "workflow:collaborate:<workflow_id>" including "Kobo basic"
    # handoff only; collaborate.ex:344-349, :432-442, :534-561; collaborate_test.exs:2563-2614
```

## 6. Unclear value

### 6.1 Possible bugs

| What | Where | What a user sees | Disposition |
|------|-------|------------------|-------------|
| The editor host opens the form for anyone who sends `open_webhook_auth_modal`, and `save` re-checks nothing; only the React link is gated | `collaborate.ex:211-223`; `form_component.ex:38-40`, `:171-190`; gate is client-side only, `WebhookConfigureStep.tsx:107`, `:374-375` | an editor or viewer who pushes the event can create a project auth method | fix |
| Renaming to a name another method has: `update_changeset` declares no `unique_constraint`, so the unique index raises instead of returning an error | `webhook_auth_method.ex:74-78`; `webhook_auth_methods.ex:265-280`; migration `20230926155218_create_webhook_auth_methods_table.exs:17` | the LiveView likely crashes and reconnects, closing the modal with no message (not run) | fix |
| The live uniqueness check compares the typed name to a list of structs, so it never matches | `form_component.ex:25-30`, `:103-111` | no "must be unique" hint while typing; it appears only after submit on create, and not at all on rename (row above) | fix |
| A revealed basic auth password stays in a `type="password"` input | `form_component.ex:530-535` | clicking "Show" and re-authenticating never shows the password; it only turns the button into "Copy" | fix |
| The delete warning says each trigger "will stop requiring authentication" and each channel "will accept unauthenticated requests" even when another method still protects it | `delete_modal.ex:123-180`; enforcement accepts any attached method, `plugs/webhook_auth.ex:87-92`, `channel_proxy_plug.ex:180-186` | an alarming, wrong warning | fix |
| A failed delete (for example already deleted from another tab) assigns `:changeset`, which the modal never renders | `delete_modal.ex:67-68`; `webhook_auth_methods.ex:677-685` | clicking "Delete authentication method" appears to do nothing | fix |
| Usernames are slugified (lowercased, spaces to hyphens) during validation but not on save | `form_component.ex:93-95`, `:117-123` vs `:171-176` | the stored username can differ from what the validated form implied | decide |
| A deleted method keeps its name reserved until purged (forever under `purge-disabled` if the row is never purged), but no list shows it | `webhook_auth_methods.ex:465-472`, `:687-695`; unique index above | "must be unique within the project" for a name nobody can see | decide |

### 6.2 Quirks and implementation details

| What | Where | Disposition |
|------|-------|-------------|
| A masked password is one asterisk per character, so its length is in the page before re-authentication | `form_component.ex:533-535`, `:558-562` | decide |
| A masked API key shows its last five characters behind up to 15 asterisks | `form_component.ex:604-613` | preserve |
| Re-authentication accepts a password or a TOTP code, not a backup code; "2FA Code" shows even for users with no authenticator, and a user with no password (SSO) can only use a code | `form_component.ex:208-211`, `:305`; `user.ex:394-405` | decide |
| A TOTP code already used (at or before `last_totp_at`) is refused, and a good one advances `last_totp_at` | `user_totp.ex:45-64` | preserve |
| Re-authentication lasts only while that modal is open; reopening asks again | `form_component.ex:32` | preserve |
| Delete is a soft delete with `scheduled_deletion`, though the flash says "has been deleted"; no restore exists | `webhook_auth_methods.ex:672-733`; `delete_modal.ex:61-64` | preserve |
| Save and delete events trust the host's gate and re-check no policy (settings relies on its mount-time flag and the scope remount) | `form_component.ex:38-40`; `delete_modal.ex:44-73`; `settings.ex:145-150` | decide |
| In a sandbox the editor host creates a method owned by the sandbox, while sandbox settings says webhook auth is managed in the parent | `collaborate.ex:214-216`; `settings.html.heex:379-403`; sandbox triggers carry the parent's methods, `sandboxes.ex:1278-1287` | decide |
| Edit form posts every field but `update_changeset` casts only `name`; the extras are dropped silently | `form_component.ex:125-130`; `webhook_auth_method.ex:74-78` | preserve |
| Delete modal links to workflows and channels use `navigate` with `target="_blank"`, so they open a new tab | `delete_modal.ex:134-142`, `:162-170` | preserve |
| Channels in the delete warning are sorted by name; triggers are in load order | `delete_modal.ex:133`, `:158-161` | decide |
| Modal titles are title case ("Webhook Authentication Method", "Delete Authentication Method") and the delete flash capitalises "Webhook Authentication" | `form_component.ex:233`; `delete_modal.ex:63`, `:83` | decide |

### 6.3 Unreachable or dead code

| What | Where | Why unreachable |
|------|-------|-----------------|
| `:view` action branches, `subtitle` and `action_buttons` slots | `form_component.ex:214-215`, `:246-248`, `:251`, `:418-423`, `:450`, `:505` | no host passes `action={:view}` or the slots |
| Create-for-trigger branch | `form_component.ex:146-169`; `webhook_auth_methods.ex:189-218` | settings passes `trigger={nil}`, the editor passes no `trigger` |
| `on_save` in the settings host | `form_component.ex:34`, `:132-134`, `:157-159`, `:178-180` | settings never passes it; only the editor does (`collaborate.ex:344-349`) |
| `push_event("webhook_auth_method_saved")` | `collaborate.ex:441` | nothing in `assets/js` handles it; the picker updates from the channel broadcast instead |
| `error_msg` is assigned only by `toggle-2fa` and `reauthenticate-user` | `form_component.ex:44`, `:52-54`, `:285` | not dead; the re-auth form cannot render before `toggle-2fa` sets it |

### 6.4 Performance and operational limits

| What | Where | User-visible? | Disposition |
|------|-------|---------------|-------------|
| Re-authentication attempts are not rate limited; each costs a bcrypt check | `form_component.ex:47-56`, `:208-211` | no | decide |
| Every `update/2` reloads the project's full method list for a uniqueness check that never matches | `form_component.ex:25-30` | no | fix |

### 6.5 Things seen but not understood

- The Copy button gains `phx-hook="Copy"` on an existing element when re-authentication succeeds (`form_component.ex:545`, `:591`); not verified that LiveView mounts the hook on that patch.
- Whether a host re-render while the modal is open calls `update/2` again, resetting `sudo_mode?` and re-masking a revealed secret (`form_component.ex:12-35`).
- Whether the editor shows the "created successfully" flash at all; Collaborate is rendered inside the React shell (`collaborate.ex:236-352`) and no flash handling was traced.
- In the editor, closing relies on `WebhookConfigureStep` relaying `close_webhook_auth_modal` (`WebhookConfigureStep.tsx:120-134`); if that step unmounts while the modal is open, Cancel and the close button may reach no listener and leave the modal up.

## 7. Not migrating

| Item | Reason | Decided by | Date |
|------|--------|------------|------|

## 8. Open questions

- Should the editor host check `:write_webhook_auth_method` on the server before opening the form and on save, as settings does?
- Should renaming be the only edit, or should admins rotate a password or regenerate an API key in place?
- Should revealing a stored secret be audited?
- Should a deleted method's name be freed immediately?
- Should the editor in a sandbox create methods at all, given sandbox settings defers to the parent?

## Proposed flows

- Reference `flow-webhook-auth-method-enforcement`: a method created, renamed or deleted here is what inbound requests are checked against. Handoff asserted by the hosts (project-settings-webhook-security S18).
- Proposed `flow-editor-auth-method-created`: create from the trigger inspector, Collaborate broadcasts `webhook_auth_methods_updated` on `workflow:collaborate:<workflow_id>`, WorkflowChannel pushes it, and every open editor's picker offers the new method. Surfaces: workflow-editor-inspectors, pubsub:workflow:collaborate:<workflow_id>, workflow-editor-inspectors (second tab). Handoff asserted in S12. The enforcement flow's 6.2 row assigns this to workflow-editor-inspectors and this file; the lead may prefer to fold it into that view instead.

## Proposed shared

none
