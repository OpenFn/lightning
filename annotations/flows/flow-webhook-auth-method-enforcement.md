---
id: flow-webhook-auth-method-enforcement
type: flow
title: Webhook auth methods enforced on inbound requests
status: not-started
owner:

trigger:
  entry: project-settings-webhook-security
  exit: history-work-orders
  surfaces:
    - project-settings-webhook-security        # create (or delete) the method; owns the form and the delete modal
    - workflow-editor-inspectors               # trigger inspector, Configure step, "Authentication" picker; commits on Finish
    - controller:webhooks                      # Plugs.WebhookAuth in the endpoint (endpoint.ex:91), then WebhooksController (router.ex:333-338)
    - history-work-orders                      # the work order an accepted request created
  reachable_when:
    - project-settings-webhook-security: the viewer may :write_webhook_auth_method and the project is not a sandbox (see that view, section 3)
    - workflow-editor-inspectors: the trigger is a webhook trigger already saved to the database (workflow_channel.ex:2136-2143), and the viewer may both :edit_workflow and :write_webhook_auth_method (workflow_channel.ex:697-698)
    - controller:webhooks: any HTTP client holding the URL; no Lightning session (router.ex:333-338)

inherits:
  - shared-project-scope            # who can open the settings tab, the editor and history; not repeated here

url_params: []                      # the inbound URL contract (/i/<trigger-id>, /i/<project-id>/<custom-path>, legacy /i/<path>) is owned by the webhook capability; this flow only uses it

config_variants:
  default: {}                                                              # read under this variant
  experimental-features: { user.preferences.experimental_features: true }  # a live workflow locks content edits, including attaching methods (workflow_channel.ex:1507-1510, :1922-1937)
  sandbox: { project.parent_id: <parent project id> }                      # data state; triggers carry the parent's methods (sandboxes.ex:1278-1287)

inventory:
  routes:
    - post /i/*path  WebhooksController :create        # entry of the enforcement hop; owned by the webhook capability
    - get /i/*path  WebhooksController :check
  events:
    - WorkflowChannel "update_trigger_auth_methods"     # workflow_channel.ex:684-743; the attach hop
    - WorkflowChannel "request_trigger_auth_methods"    # workflow_channel.ex:652-682; what the inspector shows as attached
  js_hooks: []
  policies:
    - Lightning.Policies.ProjectUsers (:edit_workflow, :write_webhook_auth_method; project_users.ex:29-49, :160-172)
  workers: []
  api_endpoints:
    - plug LightningWeb.Plugs.WebhookAuth (webhook_auth.ex:42-125)
    - module LightningWeb.Auth (auth.ex:21-79)
  emails: []
  config: []
  not_reachable_here:
    - WebhookAuthMethods.find_by_api_key/2, find_by_username_and_password/3, list_for_trigger/1 (webhook_auth_methods.ex:504-595); enforcement reads the trigger's preloaded methods instead
    - WebhooksController synchronous reply, rate limit, usage limit and 413/415 branches (webhooks_controller.ex:13-27, :42-48, :130-231); owned by the webhook capability and flow-history-live-updates
    - ChannelProxyPlug client auth (channel_proxy_plug.ex:176-186); same LightningWeb.Auth checks for channels, outside this flow's scope

related:
  - lib/lightning/webhook_auth_methods.ex
  - lib/lightning/workflows/webhook_auth_method.ex
  - lib/lightning/workflows.ex
  - lib/lightning/invocation/request_headers.ex
  - lib/lightning/work_orders.ex
  - lib/lightning_web/plugs/webhook_auth.ex
  - lib/lightning_web/auth.ex
  - lib/lightning_web/controllers/webhooks_controller.ex
  - lib/lightning_web/channels/workflow_channel.ex
  - lib/lightning_web/live/workflow_live/collaborate.ex
  - assets/js/collaborative-editor/components/inspector/trigger/WebhookConfigureStep.tsx
  - assets/js/collaborative-editor/components/inspector/trigger/WebhookAuthMethodSelect.tsx
  - assets/js/collaborative-editor/components/inspector/trigger/WebhookShowPanel.tsx
  - assets/js/collaborative-editor/components/inspector/trigger/useWebhookTrigger.ts
  - assets/js/collaborative-editor/components/inspector/trigger/useTriggerDraft.ts
  - test/lightning_web/plugs/webhook_auth_test.exs
  - test/lightning_web/controllers/webhooks_controller_test.exs
  - test/lightning_web/channels/workflow_channel_test.exs
  - shared-webhook-auth-method-form       # the create form, also opened from the inspector (collaborate.ex:326-352); lead-created, file not yet in annotations/shared
flows:
  - flow-history-live-updates             # owns the work order appearing on an already open history page
---

## 1. Purpose

Project admins protect a workflow's webhook so only the systems they hand a credential to can push
data into it. The credential is made on the webhook security tab, attached to the trigger in the
editor, and checked on every request to the webhook URL. If any hop fails, health data from
anyone who learns the URL starts runs in the project, or a legitimate partner is locked out with no
work order to show what was refused.

## 2. What it does

1. An admin or owner creates a basic auth (username and password) or API key method on the project's Webhook Security settings tab.
2. In the workflow editor they open a webhook trigger, choose one or more methods under "Authentication" and click Finish; editors and viewers can see the methods but not change them.
3. From then on, every request to any of that trigger's URLs, including a custom one, is checked.
   - No credentials: refused as unauthorized, and nothing is created
   - Wrong credentials: answered as if the webhook didn't exist, and nothing is created
   - Credentials matching any one of the attached methods: a work order is created and shows in History, with the secret blanked out of the stored request
4. Deleting a method on the settings tab revokes it at once everywhere, and removing a trigger's last method makes the webhook public again.

**Straightforwardness: 3 of 5.** The core rule is simple, but what the editor shows doesn't always match what the webhook actually enforces, which is risky on a feature that decides who can push data in.

### Most surprising behaviours

- **(2)** An editor left open while someone deletes a method on the settings tab still offers it. Picking it and clicking Finish says "Authentication updated", but the trigger is saved without it, possibly leaving the webhook with no protection at all. (6.1)
- **(2)** In a sandbox, a trigger protected by the parent project's methods shows "none configured" and those methods can't be picked, yet callers are still refused. (6.1)
- **(3)** Protection changes apply the moment you click Finish, separately from saving the workflow, so discarding your changes or restoring an older version doesn't undo them and they're not in the version history. (6.2)
- **(3)** A webhook trigger that hasn't been saved yet can't take a method; Finish seems to fail with "trigger not found" and nothing says to save first. (6.1)
- **(4)** Because a request with no credentials gets "unauthorized" while a wrong one gets "not found", a stranger can tell a protected URL exists. (6.2)

## 3. Who can do what

Sources: `lib/lightning/policies/project_users.ex:29-49`, `:160-172`; attach gate
`workflow_channel.ex:697-698`, `:1915-1937`, `:1958-1964`; enforcement `webhook_auth.ex:86-111`.

| Action | Viewer | Editor | Admin | Owner | Superuser (no row) | Support (no row) | Anonymous caller |
|--------|--------|--------|-------|-------|--------------------|------------------|------------------|
| See which methods a trigger has in the inspector | yes | yes | yes | yes | no | yes | n/a |
| Create a method (settings tab or inspector link) | no | no | yes | yes | no | no | n/a |
| Attach or detach methods on a trigger | no | no | yes | yes | no | no | n/a |
| Delete a method, detaching it everywhere | no | no | yes | yes | no | no | n/a |
| Create a work order through a protected trigger | n/a | n/a | n/a | n/a | n/a | n/a | only with a matching credential |
| Create a work order through an unprotected trigger | n/a | n/a | n/a | n/a | n/a | n/a | yes, with the URL |

**Preconditions beyond role**
- Attaching needs both `:edit_workflow` and `:write_webhook_auth_method`; editors pass the first and fail the second (`workflow_channel.ex:697-698`; `project_users.ex:29-37`, `:160-161`). The picker is disabled for them (`WebhookConfigureStep.tsx:107`, `:376`).
- Under `experimental-features`, a live workflow outside a sandbox refuses attach (`workflow_channel.ex:1922-1937`; `workflow_channel_test.exs:530-551`).
- The trigger must be in the workflow open in the editor and already persisted (`workflow_channel.ex:2136-2143`, `:723-727`).
- Only methods of the project open in the editor, not scheduled for deletion, can be attached; other ids are dropped silently (`workflow_channel.ex:2145-2148`; `webhook_auth_methods.ex:465-472`).
- A caller matches if any attached method matches: an `x-api-key` equal to an API method's key, or Basic credentials equal to a basic method's username and password, compared in constant time (`auth.ex:21-31`, `:42-79`).

## 4. What it touches

**Reads**
- Settings tab: owned by project-settings-webhook-security
- Inspector: the project's live methods (`workflow_channel.ex:1358`), the trigger's attached live methods of this project (`:666-680`)
- Attach: `triggers` (`:2136-2143`), `webhook_auth_methods` (`:2145-2148`), `trigger_webhook_auth_methods` (`webhook_auth_methods.ex:331`)
- Webhook: `triggers` with `workflow`, `edges`, `webhook_auth_methods` (`webhook_auth.ex:50-53`; `workflows.ex:1175-1248`), wrapped in the webhook retry (`webhook_auth.ex:48-61`)

**Writes, by hop**
- Settings tab: `webhook_auth_methods` insert; on delete `scheduled_deletion` set and every `trigger_webhook_auth_methods` and `channel_auth_methods` row for it removed (`webhook_auth_methods.ex:171-187`, `:674-703`)
- Inspector Finish: `trigger_webhook_auth_methods` replaced for the trigger (`webhook_auth_methods.ex:329-336`); the trigger's other edits go to the Y.Doc and are saved with the workflow (`useTriggerDraft.ts:196-227`)
- Webhook accepted: `dataclips` (with `request.headers` redacted), `work_orders`, `runs` in one transaction (`webhooks_controller.ex:49-64`, `:233-241`; `work_orders.ex:102-125`)
- Webhook refused: none

**Immediate side effects**
- Settings tab: audit `created`, `deleted`, `removed_from_trigger` (owned by project-settings-webhook-security)
- Attach: audit `added_to_trigger` and `removed_from_trigger` per changed method (`webhook_auth_methods.ex:337-370`); channel broadcast `trigger_auth_methods_updated` to everyone in the workflow room (`workflow_channel.ex:709-716`); toast "Authentication updated" (`useWebhookTrigger.ts:194-197`)
- Method created from the inspector link: PubSub `webhook_auth_methods_updated` on `workflow:collaborate:<workflow_id>` (`collaborate.ex:432-442`, `:534-561`)
- Webhook accepted: `RunCreated` and `WorkOrderCreated` on `project:<project_id>` (`work_orders.ex:151-157`), consumed by flow-history-live-updates; response headers `x-meta-work-order-id`, `x-meta-run-id` (`webhooks_controller.ex:119-128`)

**Deferred side effects**
- The run's job receives the stored request as `state.request`, so redaction is what keeps the secret out of job code (`runs.ex:138-170`; `request_headers.ex:1-9`)
- The purge cron later hard-deletes deleted methods; enforcement already ignores them (`auth.ex:47`, `:62`); owned by capability:webhook-auth-method-purge

**External, non-transactional effects**
- none

**Depends on config**
- `experimental-features`: attach refused on a live workflow (see section 3)
- `sandbox`: enforcement uses the parent's methods copied onto the sandbox trigger, which the inspector does not show (see 6.1)

**Product limits**
- none beyond the method limits owned by project-settings-webhook-security

## 5. Scenarios

```gherkin
Feature: Webhook auth methods protect inbound requests
  In order to accept data only from systems I gave a credential to
  As a project admin
  I want a method I create and attach to be checked on every webhook request

  Background:
    Given I am an admin on project "Malawi HIV"
    And workflow "Intake" has a saved, enabled webhook trigger

  @S01 @pending
  Scenario: A request without credentials is refused once a method is attached
    # Value: a stranger who learns the webhook URL cannot push data into the project.
    Given I created basic auth method "Kobo basic" on the "Webhook Security" tab
    When I open the trigger of "Intake" in the editor, choose "Kobo basic" under "Authentication" and click "Finish"
    Then I see "Authentication updated"
    And the trigger shows "Authentication (1 configured)"
    When a request with no credentials is posted to the trigger's URL
    Then the response is 401 with body {"error": "Unauthorized"}
    And no work order is created for "Intake"
    # WebhookConfigureStep.tsx:345-380; useTriggerDraft.ts:196-212; useWebhookTrigger.ts:180-197
    # workflow_channel.ex:684-716; webhook_auth_methods.ex:325-379
    # webhook_auth.ex:45-61, :86-118; webhook_auth_test.exs:156-164

  @S02 @pending
  Scenario: Wrong credentials look like a missing webhook
    # Value: someone guessing passwords learns nothing and creates nothing.
    Given "Kobo basic" is attached to the trigger of "Intake"
    When a request with Basic credentials "kobo:wrongpassword" is posted to the trigger's URL
    Then the response is 404 with body {"error": "Webhook not found"}
    And no work order is created for "Intake"
    # auth.ex:37-40, :58-77; webhook_auth.ex:99-111, :120-125; webhook_auth_test.exs:166-177

  @S03 @pending
  Scenario Outline: A matching credential creates a work order that shows in History
    # Value: the partner holding the credential gets their data processed, and the team can see it arrived.
    Given <method> is attached to the trigger of "Intake"
    When a request with <credential> is posted to the trigger's URL with body {"patient": "123"}
    Then the response is 200 with a "work_order_id"
    And the response has an "x-meta-work-order-id" header
    When I open the history page of "Malawi HIV"
    Then I see that work order for "Intake"
    # auth.ex:42-79; webhook_auth.ex:95-103; webhooks_controller.ex:39-69, :119-148
    # work_orders.ex:102-125, :151-157; webhook_auth_test.exs:179-198; webhooks_controller_test.exs:722-752
    # exit: history-work-orders S01 (list on load); the live arrival on an open page is flow-history-live-updates S01

    Examples:
      | method                                                   | credential                          |
      | basic method "Kobo basic" (username "kobo")              | Basic credentials for "kobo"        |
      | API key method "DHIS2 key"                               | header "x-api-key" with its key     |

  @S04 @pending
  Scenario: Any one of several attached methods is enough
    # Value: an admin can give each partner its own credential on one webhook, and rotate one without cutting off the others.
    Given "Kobo basic" and "DHIS2 key" are both attached to the trigger of "Intake"
    When a request with only the "DHIS2 key" API key is posted to the trigger's URL
    Then a work order is created for "Intake"
    # WebhookAuthMethodSelect.tsx:93-101, :214-227; auth.ex:21-31; webhook_auth.ex:99-103
    # webhook_auth_test.exs:251-262

  @S05 @pending
  Scenario: A trigger's custom URL is protected by the same methods
    # Value: naming a webhook never opens a second, unprotected way in.
    Given the trigger of "Intake" has custom path "kobo-intake"
    And "Kobo basic" is attached to it
    When a request with no credentials is posted to "/i/<project_id>/kobo-intake"
    Then the response is 401
    When the same request carries Basic credentials for "kobo"
    Then a work order is created for "Intake"
    # WebhookConfigureStep.tsx:366-369 ("applies to every URL above"); workflows.ex:1175-1187; webhook_auth.ex:50-57
    # webhook_auth_test.exs:109-153

  @S06 @pending
  Scenario: The credential that authenticated a request is not kept with its data
    # Value: job code, run inputs and anyone reading them never see the webhook secret.
    Given API key method "DHIS2 key" is attached to the trigger of "Intake"
    When a request with header "x-api-key" set to its key is posted to the trigger's URL
    Then the work order's stored request shows "x-api-key" as "[REDACTED]"
    And the stored request does not contain the key
    # webhooks_controller.ex:233-241; request_headers.ex:28-66; runs.ex:141-170
    # webhooks_controller_test.exs:722-790 (API key and Basic)

  @S07 @pending
  Scenario: Deleting a method on the settings tab revokes it at once
    # Value: an admin can stop a leaked credential working without editing every workflow.
    Given "Kobo basic" and "DHIS2 key" are attached to the trigger of "Intake"
    When I delete "Kobo basic" on the "Webhook Security" tab
    Then a request with Basic credentials for "kobo" gets 404
    And a request with the "DHIS2 key" API key still creates a work order
    # webhook_auth_methods.ex:674-703; auth.ex:47, :62; webhook_auth.ex:55
    # webhook_auth_test.exs:200-262

  @S08 @pending
  Scenario: Removing a trigger's last method opens the webhook again
    # Value: what the delete warning and the inspector say is what the endpoint does; a trigger with no methods is deliberately public.
    Given only "Kobo basic" is attached to the trigger of "Intake"
    When I remove "Kobo basic" under "Authentication" and click "Finish"
    Then the trigger shows "Authentication (none configured)"
    And a request with no credentials creates a work order for "Intake"
    # WebhookAuthMethodSelect.tsx:87-91; workflow_channel_test.exs:5727-5763
    # webhook_auth.ex:88-93; WebhookShowPanel.tsx:68-73; webhook_auth_test.exs:267-292 (same via deletion)

  @S09 @pending
  Scenario: An editor cannot change which methods protect a webhook
    # Value: only people trusted with access decisions can open or close the project's endpoints.
    Given I am an editor on project "Malawi HIV"
    When I open the trigger of "Intake" in the editor and expand "Authentication"
    Then the credential picker is disabled
    And I do not see "Create a new authentication method"
    When the "update_trigger_auth_methods" request is sent directly
    Then it is refused with "You don't have permission to manage webhook authentication"
    And the trigger's methods are unchanged
    # WebhookConfigureStep.tsx:98-107, :370-377; WebhookAuthMethodSelect.tsx:109, :229
    # workflow_channel.ex:697-698, :1958-1964; workflow_channel_test.exs:5765-5799 (viewer), :5801-5830 (editor)

  @S10 @pending @variant:experimental-features
  Scenario: A live workflow's webhook protection cannot be changed until it is back in draft
    # Value: the protection of a webhook in production only changes through the same draft step as its other content.
    Given workflow "Intake" is live and I have experimental features on
    When I attach "Kobo basic" to its trigger
    Then I see "This workflow is live. Switch it to draft or edit it in a sandbox to make changes."
    And requests without credentials still create work orders
    When I switch "Intake" to draft and attach "Kobo basic"
    Then requests without credentials get 401
    # workflow_channel.ex:1507-1510, :1915-1937; useWebhookTrigger.ts:198-205
    # workflow_channel_test.exs:530-577
```

## 6. Unclear value

### 6.1 Possible bugs

| What | Where | What a user sees | Disposition |
|------|-------|------------------|-------------|
| Creating or deleting a method on the settings tab sends nothing to open editors (only the inspector's own create link broadcasts), and attach drops any id that is no longer a live project method without saying so | `collaborate.ex:432-442`, `:534-561` (the only broadcaster); `workflow_channel.ex:2145-2148`; `useWebhookTrigger.ts:194-197` | an open inspector keeps offering a deleted method; choosing it and clicking Finish shows "Authentication updated" while the trigger is saved without it, possibly with no protection at all | fix |
| In a sandbox, the inspector lists and shows only methods owned by the sandbox, but sandbox triggers carry the parent's methods and the plug enforces them | `workflow_channel.ex:666-674`, `:1358`; `sandboxes.ex:1278-1287`; `webhook_auth.ex:50-55` | a protected sandbox trigger shows "Authentication (none configured)", and the parent's methods cannot be picked; callers still get 401 | decide |
| A webhook trigger added in the editor but not yet saved cannot take methods: Finish sends the attach first and the server cannot find the trigger (not run) | `useTriggerDraft.ts:201-212`; `workflow_channel.ex:723-727`, `:2136-2143` | "Failed to update" with "trigger not found", the wizard stays open, and nothing says to save the workflow first | fix |

### 6.2 Quirks and implementation details

| What | Where | Disposition |
|------|-------|-------------|
| Attaching takes effect on Finish, outside the workflow's save, versions and snapshots; discarding or resetting the workflow does not undo it | `useTriggerDraft.ts:196-212`; `workflow_channel.ex:684-716` | decide |
| Missing credentials get 401 but wrong ones get 404, so a request with no credentials confirms a protected URL exists; matters most for guessable legacy bare paths | `webhook_auth.ex:99-111`; `workflows.ex:1237-1241` | decide |
| Any `authorization` or `x-api-key` header counts as "credentials", so a Bearer token or the wrong method type gets 404, not 401 | `auth.ex:37-40` | preserve |
| Auth runs before the trigger's enabled check: a disabled protected trigger gives 401 to strangers and 403 `trigger_disabled` only to authenticated callers | `endpoint.ex:91`; `webhooks_controller.ex:40-41`, `:109-115` | preserve |
| The plug also guards `GET /i/...`, so the "webhook trigger found" check needs credentials on a protected trigger | `webhook_auth.ex:45-47`; `router.ex:336-337`; `webhooks_controller.ex:29-36` | preserve |
| Redaction scrubs only this trigger's own secrets from `authorization` and `x-api-key`; a caller's unrelated token in those headers is kept, and `cookie` and `proxy-authorization` are always redacted | `request_headers.ex:15-66`; `webhooks_controller_test.exs:792-918` | preserve |
| The moduledoc says unknown triggers return `{"error":"webhook_not_found"}`; the body is `{"error": "Webhook not found"}` | `webhook_auth.ex:32`, `:120-125` | fix |
| The "methods updated" broadcast from the inspector's create link includes each basic method's username to every collaborator in the room, viewers included, while the initial session context omits it | `collaborate.ex:538-550`; `workflow_channel.ex:1483-1491` | decide |
| The plug uses every method joined to the trigger, whatever project owns it; scoping is only enforced when attaching | `webhook_auth.ex:50-55`; `workflow_channel.ex:2145-2148` | preserve |
| Creating a method from the inspector link and seeing it offered to every open collaborator is owned by workflow-editor-inspectors and shared-webhook-auth-method-form | `WebhookConfigureStep.tsx:116-131`, `:374`; `collaborate.ex:209-235`, `:326-352` | preserve |

### 6.3 Unreachable or dead code

| What | Where | Why unreachable |
|------|-------|-----------------|
| `create_auth_method/3` (create and attach in one step, audit `added_to_trigger`) | `webhook_auth_methods.ex:189-218`; `webhook_auth_method_form_component.ex:146-169` | neither the settings tab nor the inspector modal passes a trigger (`collaborate.ex:335-351`) |
| `scheduled_deletion: nil` guards in `LightningWeb.Auth` | `auth.ex:47`, `:62` | deletion already removes every join row in the same transaction (`webhook_auth_methods.ex:696-699`); only reachable with rows inserted outside the UI |

### 6.4 Performance and operational limits

| What | Where | User-visible? | Disposition |
|------|-------|---------------|-------------|
| Every `/i/` request, authenticated or not, costs a trigger lookup with three preloads before any rate limit applies; the rate limiter runs only after auth | `webhook_auth.ex:48-61`; `webhooks_controller.ex:43-48` | no | decide |
| The auth lookup retries on DB connection errors and then answers 503 with `Retry-After` | `webhook_auth.ex:48-74`; `webhook_auth_test.exs:65-87` | yes, to callers | preserve |

### 6.5 Things seen but not understood

- The lead's surface id is `controller:webhooks`; flow-history-live-updates names the same hop `controller:webhook`. One should be renamed so the flow lint matches them.
- `useTriggerDraft.ts:113-135` guards against committing `[]` before the trigger's methods load; not verified whether a fast Finish on a slow connection can still detach methods, since the picker is seeded from the same async value.

## 7. Not migrating

| Item | Reason | Decided by | Date |
|------|--------|------------|------|

## 8. Open questions

- Should a sandbox's inspector show and edit the parent's methods it is actually protected by?
- Should attaching auth be part of the workflow save (and its version history) instead of taking effect on Finish?
- Should missing and wrong credentials get the same response, so a 401 cannot confirm a protected URL exists?

## Proposed flows

- `flow-channel-client-auth-enforcement`: the same methods attached to a channel as client methods are checked by `ChannelProxyPlug` before a request is forwarded (`channel_proxy_plug.ex:176-186`; `auth.ex:1-12`). Out of this flow's scope as decided by the lead; listed so the channel catalogue picks it up. Surfaces: project-settings-webhook-security, channel form, controller:channel-proxy.

## Proposed shared

- none (shared-webhook-auth-method-form is already decided by the lead; referenced in `related` until its file lands)
