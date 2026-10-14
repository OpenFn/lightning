# View inventory

Source of truth for which views exist and how far each is catalogued. Built from
`lib/lightning_web/router.ex`, the routes injected by `config :lightning,
Lightning.Extensions.Routing` in `config/config.exs:50`, the tabs in
`lib/lightning_web/live/project_live/settings.html.heex:31`, and the cards in
`lib/lightning_web/live/profile_live/components.ex:35`.

Status: `todo` | `batch-N` (in flight) | `done` | `done-with-decides` (has section 6 items at `decide`).

Paths below are relative to `lib/lightning_web/` unless they start with `assets/`.

## Auth and onboarding

| id | Route | Module | Main files | Status |
|----|-------|--------|------------|--------|
| auth-login | `GET/POST /users/log_in` | `UserSessionController` (controller view) | `controllers/user_session_controller.ex`, `controllers/user_session_html/new.html.heex`, `controllers/user_auth.ex`, `controllers/oidc_controller.ex` (SSO buttons) | todo |
| auth-register | `GET/POST /users/register` | `UserRegistrationController` (controller view); blocked by `:allow_signup` (`router.ex:31`) | `controllers/user_registration_controller.ex`, `controllers/user_registration_html/new.html.heex` | todo |
| auth-reset-password | `GET/POST /users/reset_password`, `GET/PUT /users/reset_password/:token` | `UserResetPasswordController` (controller view) | `controllers/user_reset_password_controller.ex`, `controllers/user_reset_password_html/{new,edit}.html.heex` | todo |
| auth-two-factor | `GET/POST /users/two-factor` | `UserTOTPController` (controller view) | `controllers/user_totp_controller.ex`, `controllers/user_totp_html/new.html.heex` | todo |
| auth-confirm-account | `GET/POST /users/confirm`, `GET/POST /users/confirm/:token`, `GET /users/send-confirmation-email` | `UserConfirmationController` (controller view) | `controllers/user_confirmation_controller.ex`, `controllers/user_confirmation_html/{new,edit}.html.heex` | todo |
| auth-confirmation-required | `live /users/confirm-required` (`:confirmation_required` session, no on_mount) | `UserConfirmationRequiredLive` | `live/user_confirmation_required_live.ex`, `.html.heex` | todo |
| auth-confirm-access | `live /auth/confirm_access` | `ReAuthenticateLive.New` | `live/re_authenticate_live/new.ex`, `new.html.heex` | todo |
| first-setup | `live /first_setup`; blocked by `:allow_first_setup`, forced by `Plugs.FirstSetup` | `FirstSetupLive.Superuser` | `live/first_setup_live/superuser.ex`, `superuser.html.heex` | todo |
| projects-dashboard | `live /projects` (config-injected); `/` redirects here | `DashboardLive.Index` | `live/dashboard_live/{index,components,project_creation_modal,user_projects_section}.ex` | done-with-decides |

## Projects and workflows

| id | Route | Module | Main files | Status |
|----|-------|--------|------------|--------|
| mfa-required | `live /mfa_required` | `ProjectLive.MFARequired` | `live/project_live/mfa_required.ex`, `.html.heex` | todo |
| workflows-index | `live /projects/:project_id/w` | `WorkflowLive.Index` | `live/workflow_live/{index,dashboard_components,helpers}.ex` | done-with-decides |
| workflow-health | `live /projects/:project_id/w/:id/health` | `WorkflowLive.Health` | `live/workflow_live/health.ex`, `controllers/api/workflow_health_controller.ex`, React mount it renders | done-with-decides |
| sandboxes-index | `live /projects/:project_id/sandboxes`, `/new`, `/:id/edit` | `SandboxLive.Index` | `live/sandbox_live/{index,form_component,components}.ex` | done-with-decides |
| channels-index | `live /projects/:project_id/channels`, `/new`, `/:id/edit` | `ChannelLive.Index` | `live/channel_live/{index,form_component,helpers}.ex` | done-with-decides |

## Collaborative workflow editor

One LiveView (`live/workflow_live/collaborate.ex`) hosts the React app at
`assets/js/collaborative-editor/` via the `ReactComponent` hook (`collaborate.ex:253`).
Split by panel; each sub-view shares the route and differs by URL params or UI state.

| id | Route / state | Module | Main files | Status |
|----|---------------|--------|------------|--------|
| workflow-editor-canvas | `live /projects/:project_id/w/:id` (diagram, header, save, presence, read-only states) | `WorkflowLive.Collaborate` | `collaborate.ex`, `CollaborativeEditor.tsx`, `components/{Header,WorkflowEditor,ActiveCollaborators,Cursors,ReadOnlyWarning,StaleBuildNotice,SandboxIndicatorBanner,EmailVerificationBanner,Breadcrumbs}.tsx`, `components/diagram/`, `stores/`, `lib/lightning_web/channels/workflow_channel.ex` | done-with-decides |
| workflow-editor-new | `live /projects/:project_id/w/new` (landing, templates, YAML import) | `WorkflowLive.Collaborate :new` | `components/{LandingScreen,TemplateBrowserModal,YAMLImportModal}.tsx`, `components/yaml-import/` | done-with-decides |
| workflow-editor-inspectors | `?job=`, trigger, edge, workflow settings side panels | (React) | `components/inspector/`, `components/{AdaptorSelectionModal,ConfigureAdaptorModal,AdaptorSelector}.tsx`, webhook auth modals in `collaborate.ex:331` | done-with-decides |
| workflow-editor-ide | `?panel=editor&job=` full-screen code editor | (React) | `components/ide/FullScreenIDE.tsx`, `components/CollaborativeMonaco.tsx` | done-with-decides |
| workflow-editor-manual-run | manual run panel (run from a job or trigger with a chosen input) | (React) | `components/{ManualRunPanel,NewRunButton,RunRetryButton}.tsx`, `components/manual-run/`, `controllers/workflow_controller.ex` (`create_run`, `retry_run`), `controllers/dataclip_controller.ex` | done-with-decides |
| workflow-editor-run-viewer | `?run=` run panel (steps, input, output, logs) | (React) | `components/run-viewer/`, `controllers/workflow_controller.ex` (`get_run_steps`) | todo |
| workflow-editor-ai-assistant | `?chat=` AI assistant panel | (React) | `components/{AIAssistantPanel,AIAssistantPanelWrapper,ChatInput,MessageList,SessionList,AIButton}.tsx`, `controllers/api/ai_assistant_controller.ex`, AI channel | todo |
| workflow-editor-versions-and-promote | version picker, history, restore, diff; GitHub sync modal; sandbox promote and edit-in-sandbox | (React) | `components/{VersionPicker,VersionDropdown,SnapshotVersionDropdown,RestoreVersionDialog,WorkflowDiffBlocks,GitHubSyncModal,PromoteDialog,PromotedNotice,EditInSandboxPicker}.tsx`, `components/diagram/MiniHistory.tsx` | todo |

## History and runs

| id | Route | Module | Main files | Status |
|----|-------|--------|------------|--------|
| history-work-orders | `live /projects/:project_id/history` | `RunLive.Index :index` | `live/run_live/{index,index.html.heex,workorder_component,rerun_job_component,export_confirmation_modal,components}.ex` | done-with-decides |
| history-channel-logs | `live /projects/:project_id/history/channels` | `RunLive.Index :channel_logs` | `live/run_live/channel_logs_component.ex` | done-with-decides |
| channel-request-show | `live /projects/:project_id/history/channels/:id` | `ChannelRequestLive.Show` | `live/channel_request_live/{show,components,helpers,timing}.ex` | done-with-decides |
| run-show | `live /projects/:project_id/runs/:id` | `RunLive.Show` | `live/run_live/{show,streaming,components,cancel_helper}.ex` | done-with-decides |
| dataclip-show | `live /projects/:project_id/dataclips/:id/show` | `DataclipLive.Show` | `live/dataclip_live/show.ex`, `form_component.html.heex` | done-with-decides |

## Project settings (`live /projects/:project_id/settings`, config-injected, `ProjectLive.Settings`)

All panels share `live/project_live/settings.ex` and `settings.html.heex`. Line ranges are the panel in the template.

| id | Route | Module | Main files | Status |
|----|-------|--------|------------|--------|
| project-settings-setup | `#project`; also `live /projects/:project_id/settings/delete` | `ProjectLive.Settings` | `settings.html.heex:67-313`, `project_live/concurrency_input_component.ex`, `live/components/project_deletion_modal.ex` | done-with-decides |
| project-settings-credentials | `#credentials` | `ProjectLive.Settings` | `settings.html.heex:315-365`, inherits shared-credential-index-component | done-with-decides |
| project-settings-collections | `#collections` | `ProjectLive.Settings` | `settings.html.heex:367-376`, `project_live/collections_component.ex` | done-with-decides |
| project-settings-webhook-security | `#webhook_security` | `ProjectLive.Settings` | `settings.html.heex:378-568`, `workflow_live/webhook_auth_method_form_component.ex`, `workflow_live/webhook_auth_method_delete_modal.ex`, `workflow_live/components.ex` | done-with-decides |
| project-settings-collaborators | `#collaboration` | `ProjectLive.Settings` | `settings.html.heex:570-679`, `project_live/{collaborators,invited_collaborators,new_collaborator_component,invite_collaborator_component}.ex` | done-with-decides |
| project-settings-security | `#security` (require MFA) | `ProjectLive.Settings` | `settings.html.heex:681-756` | done-with-decides |
| project-settings-github-sync | `#vcs` | `ProjectLive.Settings` | `settings.html.heex:758-860`, `project_live/github_sync_component.ex`, `.html.heex`, `components/github_components.ex` | done-with-decides |
| project-settings-data-storage | `#data-storage` (retention, dataclip storage) | `ProjectLive.Settings` | `settings.html.heex:862-1053` | done-with-decides |
| project-settings-history-exports | `#history-exports` | `ProjectLive.Settings` | `settings.html.heex:1055-1103`, `controllers/project_file_controller.ex` | done-with-decides |

## User settings

| id | Route | Module | Main files | Status |
|----|-------|--------|------------|--------|
| credentials-index | `live /credentials` | `CredentialLive.Index` | `live/credential_live/index.ex`, `index.html.heex`, inherits shared-credential-index-component | done-with-decides |
| profile-account | `live /profile` (config-injected) | `ProfileLive.Edit` + `ProfileLive.FormComponent` | `live/profile_live/{edit,components,form_component}.ex`, `form_component.html.heex`; GDPR preferences card is config-only (`config.exs:291`, off by default) | todo |
| profile-mfa | `/profile` MFA card | `ProfileLive.MfaComponent` | `live/profile_live/mfa_component.ex`, `.html.heex` | todo |
| profile-github | `/profile` GitHub card | `ProfileLive.GithubComponent` | `live/profile_live/github_component.ex`, `components/github_components.ex` | todo |
| profile-experimental-features | `/profile` experimental features card | `ProfileLive.ExperimentalFeaturesComponent` | `live/profile_live/experimental_features_component.ex`, `.html.heex` | todo |
| profile-delete-account | `live /profile/:id/delete` | `ProfileLive.Edit :delete` | `live/components/user_deletion_modal.ex` (config-injected `delete_modal`) | todo |
| profile-tokens | `live /profile/tokens`, `/profile/tokens/:id/delete` | `TokensLive.Index` | `live/tokens_live/index.ex`, `index.html.heex`, `live/components/token_deletion_modal.ex` | todo |
| profile-backup-codes | `live /profile/auth/backup_codes` (sudo), `GET /profile/auth/backup_codes/print` | `BackupCodesLive.Index` | `live/backup_codes_live/index.ex`, `.html.heex`, `controllers/backup_codes_controller.ex`, `backup_codes_html/print.html.heex` | todo |

## Admin (superuser, `on_mount :ensure_admin`)

| id | Route | Module | Main files | Status |
|----|-------|--------|------------|--------|
| admin-users | `live /settings/users` (config-injected), `/settings/users/:id/delete` | `UserLive.Index` | `live/user_live/{index,table_component,components}.ex`, `index.html.heex` | todo |
| admin-user-edit | `live /settings/users/new`, `/settings/users/:id` | `UserLive.Edit` | `live/user_live/{edit,form_component}.ex`, `.html.heex` | todo |
| admin-projects | `live /settings/projects`, `/new`, `/:id`, `/:id/delete` | `ProjectLive.Index` | `live/project_live/{index,form_component}.ex`, `.html.heex` | todo |
| admin-audit | `live /settings/audit` | `AuditLive.Index` | `live/audit_live/index.ex`, `.html.heex` | todo |
| admin-maintenance | `live /settings/maintenance` | `MaintenanceLive.Index` | `live/maintenance_live/index.ex`, `.html.heex` | todo |
| admin-auth-providers | `live /settings/authentication`, `/new` | `AuthProvidersLive.Index` | `live/auth_providers/{index,form_component}.ex` | todo |
| admin-collections | `live /settings/collections` | `CollectionLive.Index` | `live/collection_live/{index,components,collection_creation_modal}.ex` | todo |
| admin-live-dashboard | `live_dashboard /dashboard` | `Phoenix.LiveDashboard` (third party) | `router.ex:362` | todo |

## Not catalogued as views

These are routes but not screens. They belong in `capabilities/` or appear as hops inside flows.

- JSON APIs under `/api` (`router.ex:96-163`), collections API (`router.ex:172`), token exchange (`router.ex:89`), webhooks `/i/*path` (`router.ex:340`): capabilities.
- Controller hops: `/users/log_out`, `/authenticate/*` (OIDC), `/oauth/:provider/callback`, `/setup_vcs`, `/credentials/transfer/:token`, `/profile/confirm_email/:token`, `/users/token_exchange/:token`, `/w/new/legacy` and `/w/:id/legacy` redirects, downloads, dataclip JSON endpoints: flow surfaces.
- `/health_check`, `/adaptors/icons/*`, `/adaptors/catalogue`: capabilities.
- `/dev/*` (`router.ex:376`): dev build only, out of scope.

## Pending cross-references

Flows and shared annotations that name a view not yet catalogued. Each is passed to that view's
cataloguer with its inventory row, and removed from here once the view lists it.

| view | must reference |
|------|----------------|
| auth-login | flow-invite-new-collaborator, flow-login-return-to |
| auth-confirm-account | flow-resend-account-confirmation |
| auth-register | flow-register-first-workflow (proposed; create with this view) |
| auth-reset-password | flow-invite-new-collaborator |
| workflow-editor-run-viewer | shared-editor-session, flow-workflow-api-edit-conflict, flow-manual-run-live-follow (exit), shared-run-retry-controls, shared-dataclip-body-viewer, flow-zero-persistence-runs (shows raw null; see the flow's 6.1), flow-open-run-in-editor (exit), shared-log-viewer |
| admin-projects | flow-collaborator-added-email, flow-schedule-project-deletion, shared-project-deletion-modal |
| profile-github | flow-github-connect |
| profile-mfa | flow-require-project-mfa |
| mfa-required | flow-require-project-mfa (exit) |
| workflow-editor-ai-assistant | shared-editor-session, shared-workflow-yaml-format (AI apply), flow-workflow-api-edit-conflict |
| workflow-editor-versions-and-promote | shared-editor-session, flow-workflow-api-edit-conflict, flow-github-sync-actions (GitHubSyncModal), flow-sandbox-merge (PromoteDialog) |
| profile-backup-codes | shared-authenticated-session (mounted via `:sudo_auth`), flow-require-project-mfa (first enrolment lands here) |

## Proposed, not yet created

Held until the views they touch are catalogued, then deduplicated with those batches' proposals.

| id | proposed by | note |
|----|-------------|------|
| shared-project-mail-recipients | flow-history-export | reads as a capability (who may receive mail); deferred to the capabilities pass |
| flow-editor-credentials-broadcast | shared-adaptor-credential-config | credential created elsewhere appearing in an open editor; consolidate after batch 6 |
| flow-adaptor-catalogue-refresh | shared-adaptor-credential-config | likely a capability (/adaptors/catalogue); decide after batch 6 |
| flow-workflow-yaml-copy | shared-workflow-yaml-format | consolidate after batch 6 |
| flow-register-first-workflow | workflow-editor-new | revisit with auth-register |
| flow-account-revocation-teardown | shared-authenticated-session | revisit with admin-users and profile-delete-account |
| capability:webhook-auth-method-purge | project-settings-webhook-security | capabilities pass |
| capability:data-retention-cleanup | project-settings-data-storage | capabilities pass |
| capability:collection-api-name-resolution | project-settings-collections | capabilities pass |

## Overlaps to clean up

- workflow-editor-manual-run S12, S15 to S19, S22, S23 and six 6.2 rows: now owned by shared-run-retry-controls.
- workflow-editor-ide metadata rows in 6.1: now owned by shared-adaptor-credential-config; its inspectors citations for AdaptorSelector, AdaptorDisplay and the confirmation hook were wrong and are corrected there.
- workflow-editor-canvas 6.x rows on session plumbing: now owned by shared-editor-session (see its section 8). Canvas cites `LoadingBoundary.tsx:284-330`; the file is 72 lines.
- flow-schedule-project-deletion S04, S05: editor-channel half now owned by shared-editor-session.
- workflow-editor-new: its 6.1 row on v1 `enabled` defaults is unreachable and its 6.3 `deduplicateJobNames` entry is wrong for v2 (see shared-workflow-yaml-format).
- workflow-editor-canvas S29 Value line overstates: `/api/provision` (CLI deploy, GitHub sync) does not check presence. Consider a flow for that gap.
- workflow-editor-inspectors S04 to S15: now owned by shared-adaptor-credential-config.
- shared-channel-project-scope folded into shared-editor-session (editor channels); run and AI channel teardown to be checked when those views are catalogued.
- dataclip-show S03 to S06 and the viewer steps in run-show S07: now owned by shared-dataclip-body-viewer.
- history-work-orders `url_params`: add workflow-health to `set_by` for the status and date filters; its flow summary should mention the donut links.
- workflow-health S15: point to flow-workflow-health-drilldown S10 and S11.
- shared-authenticated-session Proposed flows: rename controller:user-session to auth-login.
- run-show: its dataclip input and output rendering is now owned by shared-dataclip-body-viewer.
- shared-project-header: projects-dashboard inherits it for the picker and menus on a page with no project; check its scenarios say which parts apply without a project.
- run-show S10 to S13 and its highlighting, save-log-filter and level-scoring rows: now owned by shared-log-viewer.
- shared-project-settings-tab-chrome S01 to S04: repeat shared-hash-tabs S01, S02, S03, S05; make them references.
- flow-run-show-live-updates: drop its note that shared-log-viewer does not exist yet.
- shared-project-settings-tab-chrome: tab navigation now owned by shared-hash-tabs; reference it.
- project-settings-webhook-security: form scenarios and form 6.x rows now owned by shared-webhook-auth-method-form.
- flow-delete-open-workflow: add the GitHub deploy (flow-github-sync-actions) as a second entry that sends WorkflowDeleted.
- flow-oauth-credential-authorize says "Add new" is hidden for viewers on the credentials tab; project-settings-credentials found it always enabled with only its options disabled. Correct the flow.

Scenarios written in a view before the shared annotation that now owns them existed. Remove from the view in the final pass.

- project-settings-setup S13, S14 and its modal rows in 6.1 to 6.3: now owned by shared-project-deletion-modal
- history-work-orders S13, S14, S22: now owned by shared-run-components S07, S08, S13; its 6.1 cites `cancel_helper.ex:310-315`, should be `:12-17`
- shared-usage-limits-banner section 2 book-a-demo line: now owned by shared-authenticated-session S08
