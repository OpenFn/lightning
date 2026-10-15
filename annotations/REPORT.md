# Cataloguing report

All 52 views in [INVENTORY.md](INVENTORY.md) are catalogued, with 52 flows and 20 shared annotations.
Every scenario is `@pending`. Nothing has been run against the app yet.

| | Files | Scenarios | Section 6 at `decide` |
|---|---|---|---|
| Views | 52 | 929 | 540 |
| Flows | 52 | 381 | 306 |
| Shared | 20 | 207 | 144 |

All 990 `decide` items are listed by file in [DECIDES.md](DECIDES.md).

## Straightforwardness

Every view, flow and shared annotation has a straightforwardness rating and a list of its most surprising behaviours in section 2. 5 means it does what it says on the tin, 1 means it's full of surprising edge cases.

| | 2 | 3 | 4 | Total |
|---|---|---|---|---|
| Views | 9 | 36 | 7 | 52 |
| Flows | 9 | 37 | 6 | 52 |
| Shared | 5 | 10 | 5 | 20 |

Nothing was rated 1 or 5. These are rated 2, where attention should go first:

- **Views**: [admin-auth-providers](views/admin-auth-providers.md), [admin-user-edit](views/admin-user-edit.md), [credentials-index](views/credentials-index.md), [history-work-orders](views/history-work-orders.md), [project-settings-github-sync](views/project-settings-github-sync.md), [sandboxes-index](views/sandboxes-index.md), [workflow-editor-ai-assistant](views/workflow-editor-ai-assistant.md), [workflow-editor-canvas](views/workflow-editor-canvas.md), [workflow-editor-versions-and-promote](views/workflow-editor-versions-and-promote.md)
- **Flows**: [flow-admin-created-account-confirm](flows/flow-admin-created-account-confirm.md), [flow-ai-session-collaborators](flows/flow-ai-session-collaborators.md), [flow-github-sync-actions](flows/flow-github-sync-actions.md), [flow-history-live-updates](flows/flow-history-live-updates.md), [flow-oauth-credential-authorize](flows/flow-oauth-credential-authorize.md), [flow-restore-version-open-editor](flows/flow-restore-version-open-editor.md), [flow-sandbox-merge](flows/flow-sandbox-merge.md), [flow-sandbox-scheduled-deletion](flows/flow-sandbox-scheduled-deletion.md), [flow-zero-persistence-runs](flows/flow-zero-persistence-runs.md)
- **Shared**: [shared-adaptor-credential-config](shared/shared-adaptor-credential-config.md), [shared-dataclip-body-viewer](shared/shared-dataclip-body-viewer.md), [shared-editor-session](shared/shared-editor-session.md), [shared-run-retry-controls](shared/shared-run-retry-controls.md), [shared-workflow-yaml-format](shared/shared-workflow-yaml-format.md)

## Views

Straightforwardness is the section 2 rating: 5 does what it says on the tin, 1 is full of surprising edge cases. Each view's section 2 lists its most surprising behaviours.

| View | Straightforward | Scenarios | 6.1 | 6.2 | 6.3 | 6.4 | 6.5 | Decide |
|---|---|---|---|---|---|---|---|---|
| [auth-login](views/auth-login.md) | 3 | 20 | 3 | 10 | 2 | 3 | 5 | 7 |
| [auth-register](views/auth-register.md) | 3 | 16 | 6 | 14 | 4 | 3 | 7 | 13 |
| [auth-reset-password](views/auth-reset-password.md) | 3 | 14 | 6 | 15 | 3 | 4 | 5 | 10 |
| [auth-two-factor](views/auth-two-factor.md) | 3 | 13 | 4 | 14 | 0 | 2 | 5 | 8 |
| [auth-confirm-account](views/auth-confirm-account.md) | 4 | 6 | 4 | 13 | 2 | 5 | 2 | 10 |
| [auth-confirmation-required](views/auth-confirmation-required.md) | 3 | 14 | 6 | 13 | 0 | 5 | 2 | 9 |
| [auth-confirm-access](views/auth-confirm-access.md) | 3 | 7 | 6 | 12 | 3 | 1 | 1 | 8 |
| [first-setup](views/first-setup.md) | 3 | 11 | 6 | 8 | 2 | 3 | 3 | 3 |
| [projects-dashboard](views/projects-dashboard.md) | 3 | 19 | 4 | 19 | 7 | 6 | 5 | 22 |
| [mfa-required](views/mfa-required.md) | 4 | 4 | 0 | 9 | 0 | 1 | 2 | 4 |
| [workflows-index](views/workflows-index.md) | 3 | 29 | 9 | 18 | 4 | 4 | 3 | 11 |
| [workflow-health](views/workflow-health.md) | 3 | 27 | 3 | 19 | 3 | 7 | 3 | 9 |
| [sandboxes-index](views/sandboxes-index.md) | 2 | 47 | 11 | 19 | 8 | 6 | 4 | 18 |
| [channels-index](views/channels-index.md) | 3 | 28 | 8 | 16 | 3 | 5 | 4 | 14 |
| [workflow-editor-canvas](views/workflow-editor-canvas.md) | 2 | 29 | 3 | 15 | 5 | 4 | 3 | 8 |
| [workflow-editor-new](views/workflow-editor-new.md) | 3 | 27 | 5 | 16 | 7 | 5 | 5 | 8 |
| [workflow-editor-inspectors](views/workflow-editor-inspectors.md) | 3 | 45 | 8 | 17 | 12 | 5 | 3 | 13 |
| [workflow-editor-ide](views/workflow-editor-ide.md) | 3 | 22 | 10 | 24 | 8 | 5 | 5 | 13 |
| [workflow-editor-manual-run](views/workflow-editor-manual-run.md) | 3 | 25 | 11 | 28 | 5 | 6 | 3 | 20 |
| [workflow-editor-run-viewer](views/workflow-editor-run-viewer.md) | 3 | 13 | 8 | 18 | 6 | 4 | 3 | 10 |
| [workflow-editor-ai-assistant](views/workflow-editor-ai-assistant.md) | 2 | 32 | 6 | 18 | 8 | 9 | 6 | 8 |
| [workflow-editor-versions-and-promote](views/workflow-editor-versions-and-promote.md) | 2 | 34 | 6 | 23 | 5 | 5 | 4 | 12 |
| [history-work-orders](views/history-work-orders.md) | 2 | 42 | 13 | 18 | 6 | 10 | 2 | 15 |
| [history-channel-logs](views/history-channel-logs.md) | 4 | 15 | 4 | 13 | 2 | 4 | 2 | 11 |
| [channel-request-show](views/channel-request-show.md) | 3 | 21 | 7 | 14 | 3 | 3 | 4 | 11 |
| [run-show](views/run-show.md) | 3 | 20 | 6 | 14 | 4 | 4 | 4 | 13 |
| [dataclip-show](views/dataclip-show.md) | 4 | 10 | 3 | 13 | 3 | 3 | 3 | 11 |
| [project-settings-setup](views/project-settings-setup.md) | 3 | 21 | 8 | 12 | 4 | 3 | 5 | 11 |
| [project-settings-credentials](views/project-settings-credentials.md) | 3 | 19 | 4 | 10 | 3 | 2 | 4 | 6 |
| [project-settings-collections](views/project-settings-collections.md) | 3 | 19 | 6 | 14 | 3 | 5 | 3 | 9 |
| [project-settings-webhook-security](views/project-settings-webhook-security.md) | 3 | 18 | 7 | 15 | 6 | 4 | 3 | 9 |
| [project-settings-collaborators](views/project-settings-collaborators.md) | 3 | 29 | 9 | 17 | 4 | 6 | 3 | 14 |
| [project-settings-security](views/project-settings-security.md) | 3 | 8 | 7 | 10 | 2 | 1 | 3 | 7 |
| [project-settings-github-sync](views/project-settings-github-sync.md) | 2 | 30 | 9 | 23 | 2 | 5 | 3 | 16 |
| [project-settings-data-storage](views/project-settings-data-storage.md) | 3 | 15 | 7 | 13 | 2 | 4 | 3 | 7 |
| [project-settings-history-exports](views/project-settings-history-exports.md) | 4 | 5 | 4 | 9 | 1 | 1 | 1 | 4 |
| [credentials-index](views/credentials-index.md) | 2 | 32 | 6 | 19 | 12 | 8 | 6 | 6 |
| [profile-account](views/profile-account.md) | 3 | 12 | 3 | 15 | 4 | 5 | 4 | 9 |
| [profile-mfa](views/profile-mfa.md) | 3 | 10 | 6 | 17 | 3 | 3 | 3 | 12 |
| [profile-github](views/profile-github.md) | 3 | 7 | 4 | 10 | 3 | 1 | 3 | 7 |
| [profile-experimental-features](views/profile-experimental-features.md) | 3 | 6 | 4 | 8 | 2 | 1 | 3 | 3 |
| [profile-delete-account](views/profile-delete-account.md) | 3 | 7 | 4 | 12 | 4 | 2 | 3 | 7 |
| [profile-tokens](views/profile-tokens.md) | 4 | 11 | 4 | 14 | 2 | 4 | 4 | 9 |
| [profile-backup-codes](views/profile-backup-codes.md) | 3 | 7 | 6 | 14 | 4 | 3 | 2 | 10 |
| [admin-users](views/admin-users.md) | 3 | 8 | 4 | 18 | 3 | 3 | 3 | 16 |
| [admin-user-edit](views/admin-user-edit.md) | 2 | 12 | 5 | 18 | 4 | 3 | 4 | 15 |
| [admin-projects](views/admin-projects.md) | 3 | 15 | 7 | 17 | 4 | 4 | 3 | 15 |
| [admin-audit](views/admin-audit.md) | 4 | 9 | 3 | 12 | 2 | 3 | 3 | 8 |
| [admin-maintenance](views/admin-maintenance.md) | 3 | 8 | 3 | 9 | 2 | 5 | 2 | 7 |
| [admin-auth-providers](views/admin-auth-providers.md) | 2 | 10 | 8 | 16 | 4 | 3 | 3 | 9 |
| [admin-collections](views/admin-collections.md) | 3 | 13 | 5 | 19 | 1 | 4 | 5 | 18 |
| [admin-live-dashboard](views/admin-live-dashboard.md) | 3 | 8 | 1 | 10 | 6 | 4 | 5 | 7 |
| **Total (52 views)** | | **929** | **300** | **781** | **202** | **209** | **182** | **540** |

## Flows created

`flow-account-revocation-teardown`, `flow-adaptor-catalogue-update`, `flow-admin-collection-reaches-project`, `flow-admin-created-account-confirm`, `flow-ai-session-collaborators`, `flow-change-email-confirm`, `flow-channel-proxy-request`, `flow-collaborator-added-email`, `flow-credential-scheduled-deletion`, `flow-credential-transfer`, `flow-dashboard-history-drilldown`, `flow-dashboard-request-logger`, `flow-data-retention-change-email`, `flow-delete-open-workflow`, `flow-digest-email`, `flow-download-collection`, `flow-edit-in-sandbox`, `flow-editor-credentials-broadcast`, `flow-export-project-yaml`, `flow-failure-alert-email`, `flow-first-superuser-sign-in`, `flow-forgot-password`, `flow-github-app-install`, `flow-github-connect`, `flow-github-sync-actions`, `flow-history-export`, `flow-history-live-updates`, `flow-invite-new-collaborator`, `flow-legacy-editor-redirect`, `flow-log-out`, `flow-login-return-to`, `flow-manual-run-live-follow`, `flow-oauth-credential-authorize`, `flow-open-run-in-editor`, `flow-personal-access-token-use`, `flow-reauth-backup-codes`, `flow-register-first-workflow`, `flow-require-project-mfa`, `flow-resend-account-confirmation`, `flow-restore-version-open-editor`, `flow-run-show-live-updates`, `flow-sandbox-merge`, `flow-sandbox-scheduled-deletion`, `flow-schedule-project-deletion`, `flow-spend-backup-code`, `flow-sso-login`, `flow-toggle-workflow-open-editor`, `flow-webhook-auth-method-enforcement`, `flow-workflow-api-edit-conflict`, `flow-workflow-health-drilldown`, `flow-zero-persistence-channel-requests`, `flow-zero-persistence-runs`

## Shared annotations created

`shared-adaptor-credential-config`, `shared-admin-space`, `shared-authenticated-session`, `shared-credential-index-component`, `shared-dataclip-body-viewer`, `shared-editor-session`, `shared-flash-messages`, `shared-hash-tabs`, `shared-local-datetime`, `shared-log-viewer`, `shared-project-deletion-modal`, `shared-project-header`, `shared-project-scope`, `shared-project-settings-tab-chrome`, `shared-run-components`, `shared-run-retry-controls`, `shared-usage-limits-banner`, `shared-user-deletion-modal`, `shared-webhook-auth-method-form`, `shared-workflow-yaml-format`

## The decisions that matter most

There are too many `decide` items to list here; DECIDES.md has all of them. These are the ones to take first, because they are security or data-integrity calls rather than product taste.

**Access and accounts**
- The last superuser can be demoted or disabled, including by themselves. Demoting reopens `/first_setup` to anonymous visitors when first setup is allowed (admin-user-edit 6.1).
- First setup never re-checks for an existing superuser, so a stale tab can create a second one (first-setup 6.1).
- No rate limit or lockout on passwords, two-factor codes, reset requests or the re-auth page; no audit or log of sign-ins (auth-login, auth-two-factor, auth-reset-password, auth-confirm-access).
- Reset responses take measurably different time for registered emails; the confirmation-required page's email check reveals whether an account exists.
- Logging out never deletes the sudo token (flow-log-out 6.1).
- GitHub account connect has no OAuth `state` check (flow-github-connect 6.1).
- An unenrolled admin can require MFA and lock everyone with a role out (flow-require-project-mfa 6.1).

**Data that crosses a boundary it shouldn't**
- Collections can be moved into any project because the changeset accepts `project_id` from the form (project-settings-collections, admin-collections).
- The audit page shows OAuth client secrets, which are only Base64-encoded (admin-audit 6.1).
- A crafted superuser project save can change MFA, support access, retention or the parent project with no audit event (admin-projects 6.1).
- The LiveDashboard request logger runs before auth, so a superuser can capture other users' requests (flow-dashboard-request-logger).
- A channel with no client auth, or whose last client credential is deleted, is an open proxy (flow-channel-proxy-request).
- `/api/provision` (CLI deploy, GitHub sync) does not check editor presence, so a deploy can overwrite open edits (flow-workflow-api-edit-conflict 6.5).

**Deletion and lifecycle**
- Scheduling a root project for deletion leaves its sandboxes running and their members unemailed, then purges them anyway (flow-schedule-project-deletion).
- The deletion email's date can be a day later than the purge (02:04 vs 02:45 cron).
- Sandbox deletion from its own settings is immediate, despite modal copy promising a grace period.
- Cancelling a user's deletion doesn't stop an already queued purge (admin-users 6.1).

## What I was unsure about

- **Nothing was run.** There is no Elixir runtime or `deps/` here. Every crash in 6.1 and every library behaviour (phoenix_html password echo, LiveView internals, NimbleTOTP window, LiveDashboard defaults) was read from code or from memory of the library. The old-app run will confirm or refute them.
- **Tests that prove nothing** turned up in six batches: assertions without `assert`, refutes that can't fail, editor tests that mock every hook or use selectors that don't exist. Several scenarios are therefore code-only. It may be worth a separate pass on the test suite.
- **Overlaps.** A handful of view scenarios now duplicate shared annotations created after them. They are listed under "Overlaps to clean up" in INVENTORY.md and not yet removed, so the scenario lint will see duplicates there.
- **102 non-view surfaces** named in flows (controllers, emails, Oban jobs, PubSub topics, capabilities, external services) have no annotation, because this session catalogued views only. The flow lint will flag them until a capabilities pass is done. Deferred capabilities are listed in INVENTORY.md.
- **Brief deviations.** I had subagents draft the flow and shared files to my deduplicated ids and scopes rather than writing them myself, to keep my context for coordination. I also told cataloguers never to set `drop`, so section 7 is empty everywhere and every cut is a `decide`. Batch 11 ran alongside batch 10's consolidation because they shared nothing.
- **Inventory errors of mine.** I split the editor into 8 views by panel, put a wrong file in one row, and twice damaged INVENTORY.md with over-broad edits (repaired and checked before every commit since).
