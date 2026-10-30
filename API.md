# API

Lightning's API lets a program manage an instance's users, projects, credentials
and collections, and read its workflows, runs and logs.

> #### Still being built {: .warning}
>
> The API is undergoing extensive improvements. Expect fixes and new endpoints.
> This page covers what every route shares and lists the routes. Fuller
> reference docs, with request and response bodies, will follow.

## Authenticate

Send a token in the `Authorization` header on every request:

```
Authorization: Bearer <token>
```

Two kinds of token work:

- The service account's access token, for automation that sets up an instance.
  [Service accounts](SERVICE_ACCOUNTS.md) explains how to get one. It carries
  only the token grants it asked for, and the [routes](#routes) table lists the
  grant each route needs.
- A personal access token, which you create in Lightning under your profile at
  **Personal Access Tokens**. It acts with your own permissions on your
  projects, works on every route except `/api/users`, and lasts until you revoke
  it.

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

| Status | `code`                   | Meaning                                                             |
| ------ | ------------------------ | ------------------------------------------------------------------- |
| 400    | `invalid_request`        | The `Authorization: Bearer` header is malformed.                    |
| 400    | `invalid_parameter`      | A path or query parameter isn't valid. See `errors`.                |
| 400    | `malformed`              | The body isn't a JSON object.                                       |
| 401    | `unauthenticated`        | The request has no bearer token.                                    |
| 401    | `invalid_token`          | The token is unknown, revoked or expired.                           |
| 403    | `insufficient_scope`     | The token lacks the token grant the route needs.                    |
| 403    | `forbidden`              | You may not do this, or the record might not exist.                 |
| 404    | `not_found`              | The record doesn't exist, or the route doesn't.                     |
| 409    | `id_taken`               | The id belongs to a record elsewhere.                               |
| 409    | `scheduled_for_deletion` | The record is scheduled for deletion.                               |
| 409    | `concurrent_edit`        | Another request changed the record first. Fetch it again and retry. |
| 422    | `invalid`                | The body isn't valid. See `errors`.                                 |

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

"Session only" routes serve Lightning's own web app and take no token. A route
"not open to the service account" answers its token with 403 `forbidden`.

### Accounts

| Method  | Path                  | What it does                                        | Token grant   |
| ------- | --------------------- | --------------------------------------------------- | ------------- |
| `POST`  | `/api/oauth/token`    | Exchanges a service account's assertion for a token | None          |
| `GET`   | `/api/users`          | Lists users, or finds one by `email`                | `users:read`  |
| `GET`   | `/api/users/:id`      | Reads a user                                        | `users:read`  |
| `POST`  | `/api/users`          | Creates a user                                      | `users:write` |
| `PATCH` | `/api/users/:id`      | Changes a user                                      | `users:write` |
| `POST`  | `/api/users/register` | Signs up, where the instance offers it              | None          |

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

### Credentials

| Method   | Path                                    | What it does                                           | Token grant                                                   |
| -------- | --------------------------------------- | ------------------------------------------------------ | ------------------------------------------------------------- |
| `GET`    | `/api/credentials`                      | Lists your credentials, or a project's by `project_id` | `credentials:write`, and `project_id` for the service account |
| `GET`    | `/api/projects/:project_id/credentials` | Lists a project's credentials                          | `credentials:write`                                           |
| `GET`    | `/api/credentials/:id`                  | Reads a credential, without its secrets                | `credentials:write`                                           |
| `PUT`    | `/api/credentials/:id`                  | Creates or replaces a credential                       | `credentials:write`                                           |
| `POST`   | `/api/credentials`                      | Creates a credential you own                           | Not open to the service account                               |
| `DELETE` | `/api/credentials/:id`                  | Deletes a credential you own                           | Not open to the service account                               |

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

### Lightning's web app

| Method | Path                                                               | What it does                  | Token grant  |
| ------ | ------------------------------------------------------------------ | ----------------------------- | ------------ |
| `GET`  | `/api/ai_assistant/sessions`                                       | Lists AI assistant sessions   | Session only |
| `GET`  | `/api/projects/:project_id/workflows/:workflow_id/health/outcomes` | Workflow health: run outcomes | Session only |
| `GET`  | `/api/projects/:project_id/workflows/:workflow_id/health/failures` | Workflow health: failures     | Session only |
| `GET`  | `/api/projects/:project_id/workflows/:workflow_id/health/runs`     | Workflow health: runs         | Session only |

## Create the first superuser

On a new instance, the service account creates the first superuser. Get a token
with the `users:write` grant, as
[Service accounts](SERVICE_ACCOUNTS.md#get-an-access-token) describes, then:

```sh
curl -s https://lightning.example.org/api/users \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"email":"admin@example.org","password":"<a strong password>","first_name":"Ada","last_name":"Admin","role":"superuser","confirmed":true}'
```

Lightning answers 201 with the new user. Leave out `role` and `confirmed` to
create an ordinary user.

## Create a project

A project needs exactly one owner, who must already be a user. With a token that
has the `projects:write` grant, choose a UUID and `PUT` the project to it:

```sh
PROJECT_ID=$(uuidgen | tr A-Z a-z)

curl -s -X PUT https://lightning.example.org/api/projects/$PROJECT_ID \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name":"intake","members":[{"email":"admin@example.org","role":"owner"}]}'
```

The `PUT` answers 201 the first time and 200 when you send it again. Read the
project back with `GET /api/projects/$PROJECT_ID`.
