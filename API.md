# API

Lightning's API lets a program manage an instance's users, projects, credentials
and collections, and read its workflows, runs and logs.

> #### Still being built {: .warning}
>
> The API is undergoing extensive improvements. Expect fixes and new endpoints.
> This page covers what every route shares and lists the routes.

## Authenticate

Send a token in the `Authorization` header on every request:

```
Authorization: Bearer <token>
```

Two kinds of bearer token work:

- The service account's access token, for automation that sets up an instance.
  [Service accounts](SERVICE_ACCOUNTS.md) explains how to get one. It carries
  only the token grants it asked for, and the [routes](#routes) table lists the
  grant each route needs.
- A personal access token, which you create in Lightning under your profile at
  **Personal Access Tokens**. It acts with your own permissions on your projects
  and lasts until you revoke it. `/api/users` takes only the service account's
  token. It answers a personal access token with 403 `forbidden`, and a project
  repo connection's token with 403 `insufficient_scope` naming `users:read` or
  `users:write`.

Lightning's own web app calls the API with a session token instead: the session
cookie that signing in sets, whether through the sign-in page, a single sign-on
provider or `POST /api/session`. A request with no `Authorization` header is
authenticated by that cookie, but only when the request comes from Lightning's
own pages, as the browser says in `Sec-Fetch-Site` (or `Origin`). A request from
another site is treated as sending no token. A write also needs the session's
CSRF token, from `GET /api/session`, in the `x-csrf-token` header; without it
the answer is 400 `invalid_header`. A session token acts as the person, with
their project roles, wherever a personal access token does.

Some routes take only a session token, and answer any other token with 403
`forbidden`. A few of those also need the person to have entered their password
or an MFA code in the last five minutes, which they do by posting it to
`POST /api/session`; until then the answer is 403 `step_up_required`.

## Conventions

- Send request bodies as JSON with `Content-Type: application/json`. Responses
  are JSON, except `GET /api/provision/yaml`.
- Ids are UUIDs.
- A `PUT` on a route the table marks "create or replace" takes an id you choose.
  It answers 201 when it creates the record and 200 when it replaces one.
- Send only the keys a route accepts. A route can refuse any other key with a
  422 whose entry has the code `unknown_key`.
- Lists that page take `page`, from 1, and `page_size`, which defaults to 10 and
  is at most 100. Their `links` give the `next` and `prev` pages.

## Errors

Every error from `/api` is an RFC 9457 problem document, except those from the
token endpoint, which
[Service accounts](SERVICE_ACCOUNTS.md#when-the-exchange-is-refused) covers. Its
content type is `application/problem+json` when your `Accept` header names that
type, and `application/json` otherwise.

```json
{
  "type": "about:blank",
  "status": 400,
  "title": "Bad Request",
  "code": "invalid_parameter",
  "detail": "A path or query parameter is not valid. See errors.",
  "errors": [{ "path": "id", "code": "type", "detail": "is not a UUID" }]
}
```

Branch on `code`. It is stable, and each one always comes with the same status.
`title` and `detail` are for people and can change.

`errors` appears when the problem is in specific parts of the request. Each
entry has a `code`, a `detail`, and one member that says where the problem is:

- `pointer`: a JSON Pointer into the request body, such as `#/members/0/email`.
- `parameter`: a query parameter's name.
- `header`: a request header's name, in lower case.
- `path`: a path segment, named as in the [routes](#routes) table, such as `id`
  or `project_id`.

These are the codes most callers handle. The full list, entry codes included, is
in `LightningWeb.API.Codes`.

| Status | `code`                   | Meaning                                                                                                                                                                                                 |
| ------ | ------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 400    | `invalid_request`        | The `Authorization: Bearer` header is malformed.                                                                                                                                                        |
| 400    | `invalid_parameter`      | A path or query parameter isn't valid. See `errors`.                                                                                                                                                    |
| 400    | `malformed`              | The body isn't a JSON object.                                                                                                                                                                           |
| 400    | `invalid_header`         | A header isn't valid. See `errors`. A write on a session token without the session's `x-csrf-token` gets this.                                                                                          |
| 401    | `unauthenticated`        | The request has no bearer token, or no session token from Lightning's own pages.                                                                                                                        |
| 401    | `invalid_token`          | The token is unknown, revoked or expired, or the route doesn't take that kind of token. An expired service account token says so in `WWW-Authenticate`: `error_description="The access token expired"`. |
| 403    | `insufficient_scope`     | The token lacks the token grant the route needs. `scope` in the body and in `WWW-Authenticate` names it.                                                                                                |
| 403    | `forbidden`              | You may not do this, or the record might not exist.                                                                                                                                                     |
| 403    | `step_up_required`       | The route needs the person to enter their password or an MFA code again, at `POST /api/session`.                                                                                                        |
| 404    | `not_found`              | The record doesn't exist, or the route doesn't.                                                                                                                                                         |
| 409    | `id_taken`               | The id belongs to a record elsewhere.                                                                                                                                                                   |
| 409    | `scheduled_for_deletion` | The record is scheduled for deletion.                                                                                                                                                                   |
| 409    | `concurrent_edit`        | Another request changed the record first. Fetch it again and retry.                                                                                                                                     |
| 422    | `invalid`                | The body isn't valid. See `errors`.                                                                                                                                                                     |

### What you hear for a record you name

Lightning checks a request in this order, and the first check that fails
answers:

1. The token: 401, or 400 for a header it can't read.
2. The token grant: 403 `insufficient_scope`.
3. Your permission on the project or record: 403 `forbidden`.
4. The id: 400 `invalid_parameter` if it isn't a UUID, 404 `not_found` if no
   such record exists.
5. The body: 400 or 422.

A caller without permission hears 403 whether the record exists or not, and
whether the id is a UUID or not. Only a caller who may learn which records exist
hears 404 or 400 for the id:

| The id names                                        | 404 and 400 go to                     |
| --------------------------------------------------- | ------------------------------------- |
| A record under `/api/projects/:project_id/`         | Anyone with permission on the project |
| A project                                           | Superusers and the service account    |
| A workflow, job, run or work order at the top level | The service account                   |
| A credential, to read it                            | The service account                   |
| A user                                              | The service account                   |

A record in another project counts as missing. A project scheduled for deletion
answers 409 `scheduled_for_deletion`, but only to a caller who would otherwise
be allowed.

## Routes

"Session only" routes serve Lightning's own web app and take only a session
token; a bearer token counts as none, so the answer is 401 `unauthenticated`. A
route "not open to the service account" answers its token with 403 `forbidden`.
"Session token" routes take only a session token and answer any other token with
403 `forbidden`; "stepped up" ones also answer a session that hasn't been
stepped up with 403 `step_up_required`.

### Accounts

| Method   | Path                  | What it does                                        | Token grant                     |
| -------- | --------------------- | --------------------------------------------------- | ------------------------------- |
| `POST`   | `/api/oauth/token`    | Exchanges a service account's assertion for a token | None                            |
| `GET`    | `/api/instance`       | Reads what the app needs before anyone signs in     | None                            |
| `POST`   | `/api/session`        | Signs in, or steps the session up                   | None                            |
| `GET`    | `/api/session`        | Reads the session and its CSRF token                | Session only                    |
| `DELETE` | `/api/session`        | Signs out                                           | Session only                    |
| `GET`    | `/api/me`             | Reads the person the token belongs to               | Not open to the service account |
| `GET`    | `/api/users`          | Lists users, or finds one by `email`                | `users:read`                    |
| `GET`    | `/api/users/:id`      | Reads a user                                        | `users:read`                    |
| `POST`   | `/api/users`          | Creates a user                                      | `users:write`                   |
| `PATCH`  | `/api/users/:id`      | Changes a user                                      | `users:write`                   |
| `POST`   | `/api/users/register` | Signs up, where the instance offers it              | None                            |

### Your account and signing in

Routes for resetting a password and confirming an email, for a person managing
their own account, and for a superuser setting up single sign-on.

| Method   | Path                                         | What it does                                                    | Token grant                     |
| -------- | -------------------------------------------- | --------------------------------------------------------------- | ------------------------------- |
| `POST`   | `/api/password_resets`                       | Emails a link to reset a forgotten password                     | None                            |
| `PUT`    | `/api/password_resets/:token`                | Resets a password with the emailed token                        | None                            |
| `POST`   | `/api/confirmations`                         | Sends the account confirmation email again                      | None                            |
| `PUT`    | `/api/confirmations/:token`                  | Confirms an account, email or credential transfer               | Session only                    |
| `GET`    | `/api/me/tokens`                             | Lists your personal access tokens, masked                       | Not open to the service account |
| `POST`   | `/api/me/tokens`                             | Creates a personal access token                                 | Session token, stepped up       |
| `DELETE` | `/api/me/tokens/:id`                         | Revokes one of your personal access tokens                      | Not open to the service account |
| `GET`    | `/api/me/mfa`                                | Reads your MFA settings                                         | Session token                   |
| `POST`   | `/api/me/mfa`                                | Starts setting up an authenticator                              | Session token                   |
| `PUT`    | `/api/me/mfa`                                | Turns MFA on, or replaces the authenticator                     | Session token, stepped up       |
| `DELETE` | `/api/me/mfa`                                | Turns MFA off                                                   | Session token, stepped up       |
| `POST`   | `/api/me/mfa/backup_codes`                   | Replaces your backup codes                                      | Session token, stepped up       |
| `DELETE` | `/api/me/github_connection`                  | Disconnects your GitHub account                                 | Session token                   |
| `GET`    | `/api/me/github_repos`                       | Lists the GitHub repositories you can connect                   | Session token                   |
| `GET`    | `/api/me/github_repos/:owner/:name/branches` | Lists a GitHub repository's branches                            | Session token                   |
| `GET`    | `/api/auth_provider`                         | Reads the single sign-on provider, as a superuser               | Not open to the service account |
| `PUT`    | `/api/auth_provider`                         | Sets up or replaces the single sign-on provider, as a superuser | Not open to the service account |
| `DELETE` | `/api/auth_provider`                         | Removes the single sign-on provider, as a superuser             | Not open to the service account |

### Projects

| Method | Path                                        | What it does                                                  | Token grant                     |
| ------ | ------------------------------------------- | ------------------------------------------------------------- | ------------------------------- |
| `GET`  | `/api/projects`                             | Lists projects                                                | `projects:write`                |
| `GET`  | `/api/projects/:id`                         | Reads a project                                               | `projects:write`                |
| `PUT`  | `/api/projects/:id`                         | Creates or replaces a project                                 | `projects:write`                |
| `GET`  | `/api/provision/:id`                        | Reads a project as a [provisioning](PROVISIONING.md) document | `projects:write`                |
| `GET`  | `/api/provision/yaml`                       | Reads a project, named by `id`, as YAML                       | `projects:write`                |
| `POST` | `/api/provision`                            | Applies a [provisioning](PROVISIONING.md) document            | Not open to the service account |
| `GET`  | `/api/projects/:project_id/collections/:id` | Reads a collection                                            | `collections:write`             |
| `PUT`  | `/api/projects/:project_id/collections/:id` | Creates or replaces a collection                              | `collections:write`             |

Settings, deletion and members:

| Method   | Path                                                       | What it does                                  | Token grant                     |
| -------- | ---------------------------------------------------------- | --------------------------------------------- | ------------------------------- |
| `DELETE` | `/api/projects/:id`                                        | Schedules a project for deletion              | `projects:write`                |
| `DELETE` | `/api/projects/:id/scheduled_deletion`                     | Cancels a project's deletion                  | `projects:write`                |
| `PUT`    | `/api/projects/:id/data_retention`                         | Sets a project's data retention               | `projects:write`                |
| `PUT`    | `/api/projects/:id/mfa_requirement`                        | Requires MFA on a project, or stops           | `projects:write`                |
| `PUT`    | `/api/projects/:id/support_access`                         | Allows support users into a project, or stops | `projects:write`                |
| `GET`    | `/api/projects/:project_id/members`                        | Lists a project's members                     | `projects:write`                |
| `PUT`    | `/api/projects/:project_id/members/:user_id`               | Adds a member or changes their role           | `projects:write`                |
| `DELETE` | `/api/projects/:project_id/members/:user_id`               | Removes a member                              | `projects:write`                |
| `PUT`    | `/api/projects/:project_id/members/:user_id/notifications` | Sets your notifications for a project         | Not open to the service account |
| `POST`   | `/api/projects/:project_id/invitations`                    | Invites someone new to a project              | Not open to the service account |

### Sandboxes

| Method | Path                                                     | What it does                                     | Token grant                     |
| ------ | -------------------------------------------------------- | ------------------------------------------------ | ------------------------------- |
| `GET`  | `/api/projects/:project_id/sandboxes`                    | Lists a project's sandboxes                      | `projects:write`                |
| `PUT`  | `/api/projects/:project_id/sandboxes/:id`                | Creates a sandbox of a project                   | Not open to the service account |
| `POST` | `/api/projects/:project_id/sandboxes/:id/merge_previews` | Previews merging a sandbox                       | Not open to the service account |
| `POST` | `/api/projects/:project_id/sandboxes/:id/merges`         | Merges a sandbox into a project in its workspace | Not open to the service account |

### GitHub sync

| Method   | Path                                              | What it does                                                    | Token grant                     |
| -------- | ------------------------------------------------- | --------------------------------------------------------------- | ------------------------------- |
| `GET`    | `/api/projects/:project_id/repo_connection`       | Reads a project's GitHub connection and checks the repo         | Not open to the service account |
| `PUT`    | `/api/projects/:project_id/repo_connection`       | Connects a project to a GitHub repo, or replaces its connection | Not open to the service account |
| `DELETE` | `/api/projects/:project_id/repo_connection`       | Disconnects a project from GitHub                               | Not open to the service account |
| `POST`   | `/api/projects/:project_id/repo_connection/syncs` | Commits a project to its GitHub branch                          | Not open to the service account |

### Credentials

The service account must send `project_id` to list credentials at
`/api/credentials`.

| Method   | Path                                    | What it does                                           | Token grant                     |
| -------- | --------------------------------------- | ------------------------------------------------------ | ------------------------------- |
| `GET`    | `/api/credentials`                      | Lists your credentials, or a project's by `project_id` | `credentials:write`             |
| `GET`    | `/api/projects/:project_id/credentials` | Lists a project's credentials                          | `credentials:write`             |
| `GET`    | `/api/credentials/:id`                  | Reads a credential, without its secrets                | `credentials:write`             |
| `PUT`    | `/api/credentials/:id`                  | Creates or replaces a credential                       | `credentials:write`             |
| `POST`   | `/api/credentials`                      | Creates a credential you own                           | Not open to the service account |
| `DELETE` | `/api/credentials/:id`                  | Deletes a credential you own                           | Not open to the service account |

### Credential deletion, links, environments and transfers

| Method   | Path                                        | What it does                                       | Token grant                     |
| -------- | ------------------------------------------- | -------------------------------------------------- | ------------------------------- |
| `PUT`    | `/api/credentials/:id/scheduled_deletion`   | Schedules a credential's deletion                  | `credentials:write`             |
| `DELETE` | `/api/credentials/:id/scheduled_deletion`   | Cancels a credential's scheduled deletion          | `credentials:write`             |
| `PUT`    | `/api/projects/:project_id/credentials/:id` | Links a credential to a project                    | `credentials:write`             |
| `DELETE` | `/api/projects/:project_id/credentials/:id` | Unlinks a credential from a project                | `credentials:write`             |
| `GET`    | `/api/credentials/:id/environments`         | Lists a credential's environments                  | `credentials:write`             |
| `PUT`    | `/api/credentials/:id/environments/:name`   | Creates or replaces an environment's body          | `credentials:write`             |
| `DELETE` | `/api/credentials/:id/environments/:name`   | Deletes an environment                             | `credentials:write`             |
| `PUT`    | `/api/credentials/:id/transfer`             | Starts giving a credential you own to another user | Not open to the service account |
| `DELETE` | `/api/credentials/:id/transfer`             | Cancels a credential's pending transfer            | Not open to the service account |

### Workflows and runs

The service account must send `project_id` to list work orders, runs or log
lines at the top level.

| Method  | Path                                        | What it does                      | Token grant      |
| ------- | ------------------------------------------- | --------------------------------- | ---------------- |
| `GET`   | `/api/projects/:project_id/workflows`       | Lists a project's workflows       | `projects:write` |
| `GET`   | `/api/projects/:project_id/workflows/:id`   | Reads a workflow                  | `projects:write` |
| `POST`  | `/api/projects/:project_id/workflows`       | Creates a workflow                | `projects:write` |
| `PATCH` | `/api/projects/:project_id/workflows/:id`   | Changes a workflow                | `projects:write` |
| `PUT`   | `/api/projects/:project_id/workflows/:id`   | Changes a workflow                | `projects:write` |
| `GET`   | `/api/projects/:project_id/jobs`            | Lists a project's jobs            | `projects:write` |
| `GET`   | `/api/projects/:project_id/jobs/:id`        | Reads a job                       | `projects:write` |
| `GET`   | `/api/projects/:project_id/work_orders`     | Lists a project's work orders     | `projects:write` |
| `GET`   | `/api/projects/:project_id/work_orders/:id` | Reads a work order                | `projects:write` |
| `GET`   | `/api/projects/:project_id/runs`            | Lists a project's runs            | `projects:write` |
| `GET`   | `/api/projects/:project_id/runs/:id`        | Reads a run                       | `projects:write` |
| `GET`   | `/api/workflows`                            | Lists workflows across projects   | `projects:write` |
| `GET`   | `/api/workflows/:id`                        | Reads a workflow                  | `projects:write` |
| `GET`   | `/api/jobs`                                 | Lists jobs across projects        | `projects:write` |
| `GET`   | `/api/jobs/:id`                             | Reads a job                       | `projects:write` |
| `GET`   | `/api/work_orders`                          | Lists work orders across projects | `projects:write` |
| `GET`   | `/api/work_orders/:id`                      | Reads a work order                | `projects:write` |
| `GET`   | `/api/runs`                                 | Lists runs across projects        | `projects:write` |
| `GET`   | `/api/runs/:id`                             | Reads a run                       | `projects:write` |
| `GET`   | `/api/log_lines`                            | Lists log lines                   | `projects:write` |

### A workflow's history and lifecycle

| Method   | Path                                        | What it does                           | Token grant                     |
| -------- | ------------------------------------------- | -------------------------------------- | ------------------------------- |
| `DELETE` | `/api/projects/:project_id/workflows/:id`   | Marks a workflow deleted               | Not open to the service account |
| `GET`    | `/api/workflows/:id/snapshots`              | Lists a workflow's snapshots           | Not open to the service account |
| `GET`    | `/api/workflows/:id/snapshots/:snapshot_id` | Reads a workflow as a snapshot kept it | Not open to the service account |
| `GET`    | `/api/workflows/:id/versions`               | Lists a workflow's version hashes      | Not open to the service account |

### Workflow templates

| Method | Path                          | What it does                       | Token grant                     |
| ------ | ----------------------------- | ---------------------------------- | ------------------------------- |
| `GET`  | `/api/workflow_templates`     | Lists workflow templates           | Not open to the service account |
| `PUT`  | `/api/workflows/:id/template` | Publishes a workflow as a template | Not open to the service account |

### Running workflows and history

For people only: a personal access token or a session token. The service account
and repo connections are refused 403 `forbidden`.

| Method  | Path                                                           | What it does                           | Token grant                     |
| ------- | -------------------------------------------------------------- | -------------------------------------- | ------------------------------- |
| `POST`  | `/api/projects/:project_id/workflows/:workflow_id/work_orders` | Runs a workflow by hand                | Not open to the service account |
| `POST`  | `/api/projects/:project_id/work_orders/retries`                | Retries many work orders               | Not open to the service account |
| `POST`  | `/api/projects/:project_id/work_orders/cancellations`          | Cancels many work orders' waiting runs | Not open to the service account |
| `PATCH` | `/api/work_orders/:id`                                         | Cancels a work order's waiting runs    | Not open to the service account |
| `PATCH` | `/api/runs/:id`                                                | Cancels a run no worker has claimed    | Not open to the service account |
| `POST`  | `/api/runs/:id/retries`                                        | Retries a run from one of its steps    | Not open to the service account |
| `GET`   | `/api/runs/:id/steps`                                          | Lists a run's steps                    | Not open to the service account |
| `POST`  | `/api/projects/:project_id/history_exports`                    | Exports work orders matching a filter  | Not open to the service account |
| `GET`   | `/api/projects/:project_id/history_exports`                    | Lists a project's history exports      | Not open to the service account |
| `GET`   | `/api/projects/:project_id/history_exports/:id`                | Reads a history export                 | Not open to the service account |
| `GET`   | `/api/projects/:project_id/history_exports/:id/download`       | Downloads a completed history export   | Not open to the service account |

### Lightning's web app

| Method | Path                                                               | What it does                  | Token grant  |
| ------ | ------------------------------------------------------------------ | ----------------------------- | ------------ |
| `GET`  | `/api/ai_assistant/sessions`                                       | Lists AI assistant sessions   | Session only |
| `GET`  | `/api/projects/:project_id/workflows/:workflow_id/health/outcomes` | Workflow health: run outcomes | Session only |
| `GET`  | `/api/projects/:project_id/workflows/:workflow_id/health/failures` | Workflow health: failures     | Session only |
| `GET`  | `/api/projects/:project_id/workflows/:workflow_id/health/runs`     | Workflow health: runs         | Session only |
