---
id: flow-credential-transfer
type: flow
title: Transfer a credential to another user
status: not-started
owner:

trigger:
  entry: credentials-index                   # also project-settings-credentials; both render the same list and modal
  exit: credentials-index                    # the recipient's, reached from the completion email
  surfaces:
    - credentials-index
    - email:credential-transfer-confirmation
    - controller:credential-transfer-confirm
    - email:credential-transfer-completed
    - credentials-index
    - project-settings-credentials            # second entry, added by lead
  reachable_when:
    - the actor owns the credential (credentials-index S20; shared-credential-index-component S01)
    - the credential has no pending transfer, so its menu item reads "Transfer" (credential_index_component.html.heex:87-94, transfer_credential_modal.ex:12)
    - the recipient passed the modal's checks at submit: exists, is not the owner, is a member of every project the credential is shared with (credentials.ex:1527-1540, :1810-1869)

inherits:
  - shared-credential-index-component    # the owner-only "Transfer" / "Revoke transfer" menu item that opens the modal (S01, S02)

url_params:
  - name: token
    set_by: email:credential-transfer-confirmation
    effect: path segment of /credentials/transfer/:token; a signed JWT naming owner, credential and recipient (credentials.ex:1760-1773, tokens.ex:38-85)

config_variants:
  default: { credential_transfer_token_validity_in_days: 2 }   # hard-coded, not env-driven (config.ex:263-265); read under this variant
  # Emails are sent synchronously through Swoosh in the request (user_notifier.ex:49-60); there is no Oban hop.

inventory:
  routes:
    - get /credentials/transfer/:token  CredentialTransferController :confirm   # router.ex:189-190, :238-240
    - live /credentials  CredentialLive.Index :index                             # exit; owned by credentials-index
  events:
    - TransferCredentialModal#transfer-credential   # entry handoff, owned by credentials-index (S20)
    - TransferCredentialModal#revoke-transfer       # owned by credentials-index (S22); this flow asserts its effect on the link (S05)
  js_hooks: []
  policies:
    - Credentials.initiate_credential_transfer/3 owner check (credentials.ex:1577-1581)
    - Credentials.confirm_transfer/2 token-owner and credential-owner checks (credentials.ex:1664, :1666)
    - require_authenticated_user plug on the confirm route (user_auth.ex:288-310)
  workers: []
  api_endpoints: []
  emails:
    - email:credential-transfer-confirmation   # UserNotifier.deliver_credential_transfer_confirmation_instructions/4, user_notifier.ex:469-497
    - email:credential-transfer-completed      # UserNotifier.deliver_credential_transfer_notification/3, user_notifier.ex:503-517
  config:
    - credential_transfer_token_validity_in_days (config.ex:263-265, :656-657)
    - Lightning.Config.token_signer, RS256 from the workers private key (config.ex:11-27)
    - email_sender_name and instance admin address (user_notifier.ex:53)
  not_reachable_here:
    - Lightning.Tokens.verify/1 rejects transfer tokens as API bearers (tokens.ex:49-51; tokens_test.exs:139-150); not a step in this flow

related:
  - lib/lightning_web/live/credential_live/transfer_credential_modal.ex
  - lib/lightning_web/controllers/credential_transfer_controller.ex
  - lib/lightning/credentials.ex
  - lib/lightning/credentials/credential.ex
  - lib/lightning/credentials/audit.ex
  - lib/lightning/tokens.ex
  - lib/lightning/accounts/user_notifier.ex
  - lib/lightning_web/controllers/user_auth.ex
  - test/lightning_web/controllers/credential_transfer_controller_test.exs
  - test/lightning/credentials_test.exs
  - test/lightning/tokens_test.exs
  - test/lightning_web/live/credential_live_test.exs
flows: []
---

## 1. Purpose

When someone who owns a credential leaves a team or hands over an integration, the secret has to
change hands without being re-entered or unshared from the projects that run on it. This flow lets
the owner name a new owner, makes the owner confirm from their own inbox, then moves ownership and
tells the new owner where to find it. Getting it wrong either strands a credential with someone who
has left, or hands a live secret to a person the owner never meant to give it to.

## 2. What it does

Owner submits a recipient from the credential list; owner is emailed "Transfer <credential> to <first name>" with a /credentials/transfer/:token link; opening it signed in as the owner moves ownership, records an audit event and lands on /projects; the recipient is emailed "A credential has been transferred to you." with a link to their /credentials list.

## 3. Who can do what

Ownership, not project role, decides every step (`credentials.ex:1577-1581`, `:1664-1666`;
`policies/users.ex:40-44` for the menu item).

| Action | Credential owner | Recipient | Any other signed-in user | Signed out |
|--------|------------------|-----------|--------------------------|------------|
| Start a transfer | yes | no | no | no |
| Receive the confirmation email | yes | no | no | no |
| Confirm by opening the link | yes | no, "No Access" | no, "No Access" | sent to log in first |
| Revoke while pending | yes | no | no | no |
| Receive the completion email | no | yes | no | no |
| See the credential in /credentials afterwards | no | yes | no | n/a |

**Preconditions beyond role**
- The link is valid for `credential_transfer_token_validity_in_days` (2) from when it was sent (`tokens.ex:69-84`, `config.ex:263-265`).
- At confirm, the credential must still be owned by the token's owner and still be `pending` (`credentials.ex:1665-1667`).
- At confirm, the recipient named in the token must still exist (`credentials.ex:1668`, `:1697`).
- Recipient project membership is checked only when the transfer is started, not at confirm (see 6.1).
- The confirm route sits behind `require_authenticated_user`, so MFA-pending and locked-out sessions are refused before the controller runs (`router.ex:189-190`, `user_auth.ex:302-306`).

## 4. What it touches

**Reads**
- Hop 1 (start, credentials-index): `users` by email, `projects`/`project_credentials`/`project_users` for the membership check (`credentials.ex:1833-1847`, `:1849-1869`; `transfer_credential_modal.ex:86-87`)
- Hop 3 (confirm): `users` (token owner, `credentials.ex:1794`; recipient, `:1668`), `credentials` (`:1665`)
- Hop 5 (recipient lands): `credentials` where `user_id` is the recipient (`credentials.ex:125-136`)

**Writes**
- Hop 1: `credentials.transfer_status = pending` (`credentials.ex:1592-1594`)
- Hop 3: in one transaction, `credentials.user_id = recipient` and `transfer_status = completed`, plus an `audit_events` row "transfered" with `before.user_id` and `after.user_id`, actor the previous owner (`credentials.ex:1669-1682`; `audit.ex:14`, `:30-36`)
- Hop 3 when signed out: `user_return_to` in the session (`user_auth.ex:296-299`, `:490-491`)
- Not written: `project_credentials`, `credential_bodies` and job assignments are untouched, so the credential stays shared exactly as before (`credentials.ex:1670-1675`; `credential.ex:64-69`)

**Immediate side effects**
- Hop 1: email `email:credential-transfer-confirmation` to the owner, subject "Transfer <credential> to <recipient first name>", body names the recipient's email, the link and the validity period, sent after the status update commits (`credentials.ex:1596-1604`; `user_notifier.ex:469-497`)
- Hop 1: flash "Credential transfer initiated. We've sent you a confirmation email." and `push_navigate` to the host's `return_to` (`transfer_credential_modal.ex:94-100`)
- Hop 3: email `email:credential-transfer-completed` to the recipient, subject "A credential has been transferred to you.", body names the previous owner's first name and links to `/credentials`, sent after the transaction commits (`credentials.ex:1684-1691`; `user_notifier.ex:503-517`)
- Hop 3: redirect to `/projects` with flash "Credential transfer confirmed successfully.", or "Credential transfer couldn't be confirmed.", or the "No Access" nav panel (`credential_transfer_controller.ex:9-23`; `live_helpers.ex:97-103`)

**Deferred side effects**
- none; there is no PubSub broadcast or Oban job, so an open credentials page in another tab is not refreshed

**External, non-transactional effects**
- Both emails, sent synchronously through `Mailer.deliver/1`; their results are ignored, so a failed send leaves the database change in place (`user_notifier.ex:57-59`; `credentials.ex:1597-1604`, `:1685-1691`)

**Depends on config**
- `credential_transfer_token_validity_in_days` (expiry and email copy)
- `token_signer` from the workers private key; without it no token can be signed or verified (`config.ex:11-27`)
- Link host from the endpoint URL config via `url/1` (`user_notifier.ex:479-480`, `:508`)

**Product limits**
- The confirmation link expires after 2 days (`tokens.ex:69-84`; copy at `user_notifier.ex:493`)

## 5. Scenarios

```gherkin
Feature: Credential transfer
  In order to hand a credential to a colleague without re-entering the secret
  As the credential's owner
  I want to name a new owner, confirm from my inbox, and have them told

  @S01 @pending
  Scenario: Owner confirms from the email and the recipient becomes the owner
    # Value: a credential changes hands without the secret being re-entered, and only after the owner confirms from their own inbox.
    Given I own credential "DHIS2 prod" shared with "Malawi HIV"
    And "amara@example.org" is "Amara", a member of "Malawi HIV"
    And I have started a transfer of "DHIS2 prod" to "amara@example.org" from my credential list
    Then I receive an email with subject "Transfer DHIS2 prod to Amara"
    When I open the link in that email while signed in
    Then I am on "/projects" and see "Credential transfer confirmed successfully."
    And "DHIS2 prod" is no longer on my "/credentials" list
    And an audit event "transfered" is recorded with the owner changing from me to Amara
    And Amara receives an email with subject "A credential has been transferred to you."
    When Amara opens the link in that email
    Then she is on "/credentials" and sees "DHIS2 prod"
    # transfer_credential_modal.ex:68-100; credentials.ex:1572-1609, :1656-1702, :125-136
    # user_notifier.ex:469-497, :503-517; credential_transfer_controller.ex:9-12
    # credential_live_test.exs:2524-2548 (owner email subject); credential_transfer_controller_test.exs:42-61; credentials_test.exs:1154-1182 (audit, recipient email)

  @S02 @pending
  Scenario: The credential stays shared with the same projects after the transfer
    # Value: workflows using the credential keep running through the handover.
    Given I own credential "DHIS2 prod" shared with "Malawi HIV" and used by job "Fetch" there
    When I complete a transfer of "DHIS2 prod" to "amara@example.org"
    Then "DHIS2 prod" is still shared with "Malawi HIV"
    And job "Fetch" still uses "DHIS2 prod"
    # credentials.ex:1670-1675 changes only user_id and transfer_status; credential.ex:64-69

  @S03 @pending
  Scenario: Only the owner can confirm the link
    # Value: a forwarded or intercepted link cannot move someone else's secret.
    Given I have started a transfer of "DHIS2 prod" to "amara@example.org"
    When another signed-in user opens the link from my confirmation email
    Then they are on "/projects" with the "No Access" panel
    And I still own "DHIS2 prod"
    # credentials.ex:1664, :1698; credential_transfer_controller.ex:14-17; credential_transfer_controller_test.exs:63-81

  @S04 @pending
  Scenario: A signed-out owner confirms after logging in
    # Value: the owner can confirm from an inbox on a device where they aren't logged in.
    Given I have started a transfer of "DHIS2 prod" to "amara@example.org"
    And I am signed out
    When I open the link in the confirmation email
    Then I am asked to log in
    When I log in
    Then I see "Credential transfer confirmed successfully."
    And Amara owns "DHIS2 prod"
    # router.ex:189-190, :238-240; user_auth.ex:288-299, :490-491, :63-69
    # credential_transfer_controller_test.exs:36-40 asserts only the login redirect

  @S05 @pending
  Scenario: A revoked transfer's link no longer works
    # Value: an owner who started a transfer by mistake can stop it even after the email has gone out.
    Given I have started a transfer of "DHIS2 prod" to "amara@example.org"
    And I have revoked it from my credential list
    When I open the link in the confirmation email
    Then I see "Credential transfer couldn't be confirmed."
    And I still own "DHIS2 prod"
    # credentials.ex:1667, :1699, :1740-1758; credential_transfer_controller.ex:19-22
    # credential_transfer_controller_test.exs:103-125; credentials_test.exs:1247-1269

  @S06 @pending
  Scenario: An expired link no longer works
    # Value: a confirmation email left in an inbox cannot hand over the secret days later (product limit).
    Given I started a transfer of "DHIS2 prod" to "amara@example.org" more than 2 days ago
    When I open the link in the confirmation email
    Then I see "Credential transfer couldn't be confirmed."
    And I still own "DHIS2 prod"
    # tokens.ex:69-84; credentials.ex:1783-1803; config.ex:263-265; tokens_test.exs:359-412

  @S07 @pending
  Scenario: An edited link is refused
    # Value: the link cannot be re-pointed at a different credential or recipient.
    Given I have started a transfer of "DHIS2 prod" to "amara@example.org"
    When I open "/credentials/transfer/" followed by any token other than the one emailed
    Then I see "Credential transfer couldn't be confirmed."
    And I still own "DHIS2 prod"
    # credentials.ex:1620-1622, :1783-1803; credential_transfer_controller_test.exs:83-101; credentials_test.exs:1197-1226, :1271-1290

  @S08 @pending
  Scenario: A confirmed link cannot be used again
    # Value: a spent link cannot move the credential a second time.
    Given I have confirmed a transfer of "DHIS2 prod" to "amara@example.org"
    When I open the same link again
    Then "DHIS2 prod" is still owned by Amara
    # credentials.ex:1666, :1698; credentials_test.exs:1456-1473 (returns :not_owner, so the user sees "No Access"; see 6.1)
```

The start of the flow (modal validation, the "Transfer" and "Revoke transfer" menu item, the
pending state) is owned by credentials-index S20 to S22 and shared-credential-index-component S01
and S02, and is not repeated here.

## 6. Unclear value

### 6.1 Possible bugs

| What | Where | What a user sees | Disposition |
|------|-------|------------------|-------------|
| Revoking does not invalidate the emailed token; it only clears `transfer_status`. If the owner revokes a transfer to A and starts one to B, the status is `pending` again and A's old link (within 2 days) passes every guard and transfers to A. The token moduledoc says revocation is enforced by `transfer_status`, which is only true until the next transfer starts | `tokens.ex:42-47`; `credentials.ex:1664-1668`, `:1746`, `:1593` | the owner clicks the older email and the credential goes to the person they revoked | fix |
| Recipient project membership is checked when the transfer starts but not at confirm. If the recipient is removed from a project, or the owner shares the credential with a new project, in the 2-day window, the transfer still completes | `credentials.ex:1527-1540`, `:1810-1847` vs `:1656-1668` | a credential owned by someone who cannot open the projects that use it, the case the modal's copy says is refused (`transfer_credential_modal.ex:133`) | fix |
| A name or external ID clash with a credential the recipient already owns fails the unique constraint at confirm; the controller collapses the changeset error into a generic message and the transfer stays pending | `credential.ex:77-82`; `priv/repo/migrations/20240810082050_add_uniqueness_to_credential_name_per_user.exs:24`; `credentials.ex:1693-1694`; `credential_transfer_controller.ex:19-22` | "Credential transfer couldn't be confirmed." with no reason, and nothing at start warned about it | fix |
| If the confirmation email fails to send, `initiate_credential_transfer` still returns `:ok` | `credentials.ex:1596-1604`; `user_notifier.ex:57-59` | "We've sent you a confirmation email", no email, and a credential stuck at "Revoke transfer" | fix |
| `initiate_credential_transfer` does not check `transfer_status`; only the menu label stops a second start. A second tab opened before the first transfer still shows "Transfer" and can start another to a different person, leaving two valid links | `credentials.ex:1572-1609`; `transfer_credential_modal.ex:12`; `credential_index_component.html.heex:87-94` | two pending links for one credential; whichever is clicked first wins | fix |
| Replaying a spent link, or confirming after the owner has changed, shows the "No Access" panel rather than a transfer message | `credentials.ex:1666`, `:1698`; `credential_transfer_controller.ex:14-17` | the owner opens their own email and is told they don't have access | fix |

### 6.2 Quirks and implementation details

| What | Where | Disposition |
|------|-------|-------------|
| The audit event is spelled "transfered" | `audit.ex:14`; `credentials.ex:1677` | decide |
| After confirming, the owner lands on `/projects`, not `/credentials`, for success and every error | `credential_transfer_controller.ex:12`, `:17`, `:22` | decide |
| The confirm is a state-changing GET with no confirmation page | `router.ex:238-240`; `credential_transfer_controller.ex:6-25` | decide |
| `:not_found`, `:token_error`, `:not_pending` and changeset errors all show "Credential transfer couldn't be confirmed." | `credential_transfer_controller.ex:19-22`; `credentials.ex:1696-1701` | preserve |
| The token is a stateless JWT signed with the workers private key; its `sub` prefix keeps it from authenticating as an API bearer | `credentials.ex:1760-1773`; `tokens.ex:49-51`; `config.ex:11-27`; `tokens_test.exs:139-150` | preserve |
| Transfers of different credentials by one owner are independent; confirming one does not invalidate another | `credentials_test.exs:1362-1398` | preserve |
| The completion email has no greeting line and, like the confirmation email, is plain text only | `user_notifier.ex:49-55`, `:510-516` | preserve |
| `transfer_status` stays `:completed` on the credential under its new owner | `credentials.ex:1673`; credentials-index 6.2 covers the menu label | preserve |
| Docstrings disagree with the code: `initiate_credential_transfer` says the email goes to the receiver; `confirm_transfer` says both parties are notified (only the recipient is); `validate_credential_transfer` says "the email does not already exist" | `credentials.ex:1504-1508`, `:1545-1548`, `:1614-1618` | fix |
| No PubSub broadcast: an open credentials page in another tab, for owner or recipient, shows the old state until reload | `credentials.ex:1656-1702` | preserve |

### 6.3 Unreachable or dead code

| What | Where | Why unreachable |
|------|-------|-----------------|
| `{:error, :not_owner}` from `initiate_credential_transfer` | `credentials.ex:1577-1581` | the modal takes the owner from the session and the credential from the owner's list, as the comment at `:1584-1588` says |
| `nil -> "User not found"` in the modal's submit | `transfer_credential_modal.ex:102-103` | `validate_credential_transfer` has already refused an unknown email (`credentials.ex:1863-1864`) |

### 6.4 Performance and operational limits

| What | Where | User-visible? | Disposition |
|------|-------|---------------|-------------|
| Link validity 2 days, hard-coded rather than configurable | `config.ex:263-265`; `tokens.ex:69-84` | yes, in the email and on expiry | preserve |
| Emails are sent synchronously inside the request with no retry | `user_notifier.ex:49-60` | yes, a slow mail server delays the flash and redirect | decide |

### 6.5 Things seen but not understood

- The controller test for signed-out access asserts only the redirect to `/users/log_in` (`credential_transfer_controller_test.exs:36-40`); nothing tests that confirming after login works (S04).
- Nothing tests the recipient's completion email body or that its link reaches `/credentials`; `credentials_test.exs:1178-1181` asserts only recipient and subject.
- Whether a credential scheduled for deletion can be transferred: `confirm_transfer` does not look at `scheduled_deletion` (`credentials.ex:1656-1668`). Not traced through the list's menu for scheduled rows.

## 7. Not migrating

| Item | Reason | Decided by | Date |
|------|--------|------------|------|

## 8. Open questions

- Should revoking, or starting a new transfer, invalidate earlier links (6.1)?
- Should recipient project membership and name uniqueness be re-checked at confirm, and reported with a specific message (6.1)?
- Should the owner land on `/credentials` after confirming (6.2)?
- Should confirming be a GET, or a page with a button (6.2)?

## Proposed flows

- none. Referenced: credentials-index S20 (start), S21 (membership refusal), S22 (revoke); shared-credential-index-component S01, S02 (menu item).

## Proposed shared

- none. Referenced: shared-credential-index-component.
