# Capabilities not yet catalogued

A capability is behaviour with no screen: an API endpoint, an inbound webhook, a
scheduled job, an email, a socket (see `../TEMPLATE.md`). None has its own
annotation yet. This lists what Lightning has, so the gap is visible. When one
is written, it goes beside this file as `<id>.md` and its row's status changes.

"Seen in" names the flows that already cover part of it where it touches a
screen. That is not the same as describing it.

Status: `todo` | `done`.

## Public interfaces

Anything a script, worker or other system relies on. Changing these breaks
someone outside Lightning, so they matter most for releasing the API.

| id                   | What                                                                                                    | Where                                                                                           | Seen in                                                                                   | Status |
| -------------------- | ------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------- | ------ |
| api-rest             | The JSON API: users, projects, credentials, workflows, jobs, work orders, runs, log lines, provisioning | `router.ex:124-165`, `controllers/api/`                                                         | flow-personal-access-token-use, flow-workflow-api-edit-conflict, flow-export-project-yaml | todo   |
| api-registration     | Registering a user over the API                                                                         | `router.ex:167-171`                                                                             |                                                                                           | todo   |
| api-app-json         | Cookie-authenticated JSON for the app's React components: AI sessions, workflow health                  | `router.ex:173-190`                                                                             | flow-workflow-health-drilldown                                                            | todo   |
| api-oauth-token      | Service account token exchange and the OAuth server metadata                                            | `router.ex:114-119`, `TokenExchangeController`                                                  |                                                                                           | todo   |
| collections-api      | Reading and writing collection items: stream, get, put, put all, delete                                 | `router.ex:206-220`, `CollectionsController`                                                    | flow-admin-collection-reaches-project, flow-download-collection                           | todo   |
| webhook-trigger      | An inbound request to `/i/*path` starting a work order, and its auth methods                            | `router.ex:384-385`, `WebhooksController`                                                       | flow-webhook-auth-method-enforcement, flow-zero-persistence-runs                          | todo   |
| channel-proxy        | A request to a channel passed on to its destination and logged                                          | `endpoint.ex:90`, `ChannelProxyPlug`                                                            | flow-channel-proxy-request, flow-zero-persistence-channel-requests                        | todo   |
| kafka-trigger        | A Kafka topic starting work orders                                                                      | `workflows/trigger.ex` (`kafka_configuration`), `runs.ex`                                       |                                                                                           | todo   |
| worker-protocol      | Workers claiming runs and reporting steps and logs over their socket                                    | `channels/worker_socket.ex`, `worker_channel.ex`, `run_channel.ex`                              | flow-manual-run-live-follow, flow-run-show-live-updates                                   | todo   |
| app-sockets          | The app's own live connections: workflow editing, AI assistant, work listener                           | `channels/user_socket.ex`, `workflow_channel.ex`, `ai_assistant_channel.ex`, `work_listener.ex` | shared-editor-session and the editor flows                                                | todo   |
| health-and-catalogue | `/health_check`, adaptor icons and the adaptor catalogue                                                | `router.ex:203`, `router.ex:430`                                                                | flow-adaptor-catalogue-update                                                             | todo   |

## Scheduled jobs

From the Oban crontab in `lib/lightning/config/bootstrap.ex:297-323`.

| id                    | What                                                                                                  | Schedule              | Seen in                                                                                             | Status |
| --------------------- | ----------------------------------------------------------------------------------------------------- | --------------------- | --------------------------------------------------------------------------------------------------- | ------ |
| cron-trigger          | Cron triggers starting work orders (`Workflows.Scheduler`)                                            | every minute          |                                                                                                     | todo   |
| janitor               | Marking lost runs (`Janitor`)                                                                         | every 5 minutes       |                                                                                                     | todo   |
| ai-stuck-messages     | Failing AI messages that never got a reply (`StuckMessageReaper`)                                     | every 5 minutes       | flow-ai-session-collaborators                                                                       | todo   |
| service-account-check | Service account assertion (`ServiceAccount.Assertion`)                                                | every 10 minutes      |                                                                                                     | todo   |
| digest-emails         | Daily, weekly and monthly project digests (`DigestEmailWorker`)                                       | 10:00 daily, Mon, 1st | flow-digest-email                                                                                   | todo   |
| data-retention        | Deleting history past a project's retention period (`Projects`)                                       | every 2 hours         | flow-data-retention-change-email                                                                    | todo   |
| search-indexing       | Search vectors for log lines and dataclips                                                            | every minute          |                                                                                                     | todo   |
| scheduled-deletions   | Purging users, credentials, projects, webhook auth methods and workflows once their grace period ends | nightly, 02:15-03:15  | flow-schedule-project-deletion, flow-credential-scheduled-deletion, flow-sandbox-scheduled-deletion | todo   |
| usage-tracking        | Daily usage reports and resubmissions (`UsageTracking.*`)                                             | when configured       |                                                                                                     | todo   |

## Background work and limits

| id                    | What                                                                          | Where                                                                       | Seen in                          | Status |
| --------------------- | ----------------------------------------------------------------------------- | --------------------------------------------------------------------------- | -------------------------------- | ------ |
| bulk-work-orders      | Bulk retry and bulk cancel of work orders                                     | `workorders/retry_many_workorders_job.ex`, `cancel_many_work_orders_job.ex` | flow-dashboard-history-drilldown | todo   |
| history-export        | Building a history export in the background                                   | `workorders/export_worker.ex`                                               | flow-history-export              | todo   |
| ai-messages           | Processing AI assistant messages                                              | `ai_assistant/message_processor.ex`                                         | flow-ai-session-collaborators    | todo   |
| orphaned-steps        | Removing steps left without a run                                             | `invocation/delete_orphaned_steps.ex`                                       |                                  | todo   |
| oban-pruning          | Pruning finished jobs                                                         | `oban_pruner.ex`                                                            |                                  | todo   |
| usage-and-rate-limits | What the usage limiter, rate limiter and run queue extensions refuse or delay | `lib/lightning/extensions/`                                                 | shared-usage-limits-banner       | todo   |
| extension-hooks       | Account, project and collection hooks other deployments plug into             | `lib/lightning/extensions/*_hook.ex`                                        |                                  | todo   |

## Emails

Every message in `lib/lightning/accounts/user_notifier.ex`. Most are already the
end of a flow; the ones with no flow are the gap.

| id                        | Function                                                                                            | Seen in                                                              | Status |
| ------------------------- | --------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------- | ------ |
| email-confirmation        | `deliver_confirmation_instructions`                                                                 | flow-resend-account-confirmation, flow-admin-created-account-confirm | todo   |
| email-reset-password      | `deliver_reset_password_instructions`                                                               | flow-forgot-password                                                 | todo   |
| email-change              | `deliver_update_email_instructions`, `deliver_update_email_warning`                                 | flow-change-email-confirm                                            | todo   |
| email-project-addition    | `deliver_project_addition_notification`                                                             | flow-collaborator-added-email                                        | todo   |
| email-project-invitation  | `deliver_project_invitation_email`                                                                  | flow-invite-new-collaborator                                         | todo   |
| email-data-retention      | `send_data_retention_change_email`                                                                  | flow-data-retention-change-email                                     | todo   |
| email-user-deletion       | `send_deletion_notification_email`                                                                  |                                                                      | todo   |
| email-credential-deletion | `send_credential_deletion_notification_email`                                                       | flow-credential-scheduled-deletion                                   | todo   |
| email-credential-transfer | `deliver_credential_transfer_confirmation_instructions`, `deliver_credential_transfer_notification` | flow-credential-transfer                                             | todo   |
| email-history-export      | `notify_history_export_completion`                                                                  | flow-history-export                                                  | todo   |
| email-project-digest      | `deliver_project_digest`                                                                            | flow-digest-email                                                    | todo   |
| email-project-deletion    | `notify_project_deletion`                                                                           | flow-schedule-project-deletion                                       | todo   |
| email-failure-alert       | Failure alerts on a failed run                                                                      | flow-failure-alert-email                                             | todo   |
