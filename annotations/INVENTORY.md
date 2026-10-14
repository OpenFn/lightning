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

## Projects and workflows

| id | Route | Module | Main files | Status |
|----|-------|--------|------------|--------|
| projects-dashboard | `live /projects` (config-injected); `/` redirects here | `DashboardLive.Index` | `live/dashboard_live/{index,components,project_creation_modal,user_projects_section}.ex` | todo |
| mfa-required | `live /mfa_required` | `ProjectLive.MFARequired` | `live/project_live/mfa_required.ex`, `.html.heex` | todo |
| workflows-index | `live /projects/:project_id/w` | `WorkflowLive.Index` | `live/workflow_live/{index,dashboard_components,helpers}.ex` | done-with-decides |
| workflow-health | `live /projects/:project_id/w/:id/health` | `WorkflowLive.Health` | `live/workflow_live/health.ex`, `controllers/api/workflow_health_controller.ex`, React mount it renders | todo |
| sandboxes-index | `live /projects/:project_id/sandboxes`, `/new`, `/:id/edit` | `SandboxLive.Index` | `live/sandbox_live/{index,form_component,components}.ex` | todo |
| channels-index | `live /projects/:project_id/channels`, `/new`, `/:id/edit` | `ChannelLive.Index` | `live/channel_live/{index,form_component,helpers}.ex` | todo |

## Collaborative workflow editor

One LiveView (`live/workflow_live/collaborate.ex`) hosts the React app at
`assets/js/collaborative-editor/` via the `ReactComponent` hook (`collaborate.ex:253`).
Split by panel; each sub-view shares the route and differs by URL params or UI state.

| id | Route / state | Module | Main files | Status |
|----|---------------|--------|------------|--------|
| workflow-editor-canvas | `live /projects/:project_id/w/:id` (diagram, header, save, presence, read-only states) | `WorkflowLive.Collaborate` | `collaborate.ex`, `CollaborativeEditor.tsx`, `components/{Header,WorkflowEditor,ActiveCollaborators,Cursors,ReadOnlyWarning,StaleBuildNotice,SandboxIndicatorBanner,EmailVerificationBanner,Breadcrumbs}.tsx`, `components/diagram/`, `stores/`, `lib/lightning_web/channels/workflow_channel.ex` | todo |
| workflow-editor-new | `live /projects/:project_id/w/new` (landing, templates, YAML import) | `WorkflowLive.Collaborate :new` | `components/{LandingScreen,TemplateBrowserModal,YAMLImportModal}.tsx`, `components/yaml-import/` | todo |
| workflow-editor-inspectors | `?job=`, trigger, edge, workflow settings side panels | (React) | `components/inspector/`, `components/{AdaptorSelectionModal,ConfigureAdaptorModal,AdaptorSelector}.tsx`, webhook auth modals in `collaborate.ex:331` | todo |
| workflow-editor-ide | `?panel=editor&job=` full-screen code editor | (React) | `components/ide/FullScreenIDE.tsx`, `components/CollaborativeMonaco.tsx` | todo |
| workflow-editor-manual-run | manual run panel (run from a job or trigger with a chosen input) | (React) | `components/{ManualRunPanel,NewRunButton,RunRetryButton}.tsx`, `components/manual-run/`, `controllers/workflow_controller.ex` (`create_run`, `retry_run`), `controllers/dataclip_controller.ex` | todo |
| workflow-editor-run-viewer | `?run=` run panel (steps, input, output, logs) | (React) | `components/run-viewer/`, `controllers/workflow_controller.ex` (`get_run_steps`) | todo |
| workflow-editor-ai-assistant | `?chat=` AI assistant panel | (React) | `components/{AIAssistantPanel,AIAssistantPanelWrapper,ChatInput,MessageList,SessionList,AIButton}.tsx`, `controllers/api/ai_assistant_controller.ex`, AI channel | todo |
| workflow-editor-versions-and-promote | version picker, history, restore, diff; GitHub sync modal; sandbox promote and edit-in-sandbox | (React) | `components/{VersionPicker,VersionDropdown,SnapshotVersionDropdown,RestoreVersionDialog,WorkflowDiffBlocks,GitHubSyncModal,PromoteDialog,PromotedNotice,EditInSandboxPicker}.tsx`, `components/diagram/MiniHistory.tsx` | todo |

## History and runs

| id | Route | Module | Main files | Status |
|----|-------|--------|------------|--------|
| history-work-orders | `live /projects/:project_id/history` | `RunLive.Index :index` | `live/run_live/{index,index.html.heex,workorder_component,rerun_job_component,export_confirmation_modal,components}.ex` | done-with-decides |
| history-channel-logs | `live /projects/:project_id/history/channels` | `RunLive.Index :channel_logs` | `live/run_live/channel_logs_component.ex` | todo |
| channel-request-show | `live /projects/:project_id/history/channels/:id` | `ChannelRequestLive.Show` | `live/channel_request_live/{show,components,helpers,timing}.ex` | todo |
| run-show | `live /projects/:project_id/runs/:id` | `RunLive.Show` | `live/run_live/{show,streaming,components,cancel_helper}.ex` | todo |
| dataclip-show | `live /projects/:project_id/dataclips/:id/show` | `DataclipLive.Show` | `live/dataclip_live/show.ex`, `form_component.html.heex` | todo |

## Project settings (`live /projects/:project_id/settings`, config-injected, `ProjectLive.Settings`)

All panels share `live/project_live/settings.ex` and `settings.html.heex`. Line ranges are the panel in the template.

| id | Route | Module | Main files | Status |
|----|-------|--------|------------|--------|
| project-settings-setup | `#project`; also `live /projects/:project_id/settings/delete` | `ProjectLive.Settings` | `settings.html.heex:67-313`, `project_live/concurrency_input_component.ex`, `live/components/project_deletion_modal.ex` | done-with-decides |
| project-settings-credentials | `#credentials` | `ProjectLive.Settings` | `settings.html.heex:315-365`, inherits shared-credential-index-component | todo |
| project-settings-collections | `#collections` | `ProjectLive.Settings` | `settings.html.heex:367-376`, `project_live/collections_component.ex` | todo |
| project-settings-webhook-security | `#webhook_security` | `ProjectLive.Settings` | `settings.html.heex:378-568`, `workflow_live/webhook_auth_method_form_component.ex`, `workflow_live/webhook_auth_method_delete_modal.ex`, `workflow_live/components.ex` | todo |
| project-settings-collaborators | `#collaboration` | `ProjectLive.Settings` | `settings.html.heex:570-679`, `project_live/{collaborators,invited_collaborators,new_collaborator_component,invite_collaborator_component}.ex` | done-with-decides |
| project-settings-security | `#security` (require MFA) | `ProjectLive.Settings` | `settings.html.heex:681-756` | todo |
| project-settings-github-sync | `#vcs` | `ProjectLive.Settings` | `settings.html.heex:758-860`, `project_live/github_sync_component.ex`, `.html.heex`, `components/github_components.ex` | todo |
| project-settings-data-storage | `#data-storage` (retention, dataclip storage) | `ProjectLive.Settings` | `settings.html.heex:862-1053` | todo |
| project-settings-history-exports | `#history-exports` | `ProjectLive.Settings` | `settings.html.heex:1055-1103`, `controllers/project_file_controller.ex` | todo |

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
