---
paths:
  - "lib/lightning_web/api/**"
  - "lib/lightning_web/controllers/api/**"
  - "lib/lightning_web/controllers/collections_controller.ex"
  - "lib/lightning_web/plugs/authorize_action.ex"
  - "lib/lightning_web/auth.ex"
  - "lib/lightning_web/router.ex"
---

# API controllers and errors

Tests for these files follow `.claude/rules/api-tests.md`. Policies and `Lightning.Scope` follow `.claude/rules/policies.md`.

## Problem documents

- Every error on `/api/*` (except the OAuth token endpoint), `/collections/*` and `/adaptors/catalogue` is an RFC 9457 problem document built by `LightningWeb.API.Problem`; `LightningWeb.API.ProblemPaths` lists those paths. Answer an error by returning it to `FallbackController`, or with `Problem.new/2` and `Problem.respond/2` in a controller without the fallback. `Lightning.Credo.Check.ApiErrorsAsProblems` refuses an error status set with `put_status`, `send_resp` or `resp`.
- Entries built in web go out as `Errors.refuse(entries)`; the fallback passes a `%Problem{}` straight through. When a schema field isn't the key the client sent, call `Errors.problem(changeset, renames)` so each pointer uses the client's key.
- An entry says where the problem is, its `code` and its `detail`, and never anything about another record, such as the id of the user who holds a taken email. A refusal must not tell a token more than its grants allow; a client that needs the other record reads it with a token that may.

## Order and statuses

- The first failed check answers, in this order: a failed login, 401 or 400 for a malformed `Authorization` header (`LightningWeb.Auth.refuse/2`); 403 `insufficient_scope`; 403 `forbidden` for no permission; 409 `scheduled_for_deletion` for a project in the path, whether or not the record under it exists; 400 `invalid_parameter` for a path id that isn't a UUID; 404 `not_found`; 409 `scheduled_for_deletion` for a record itself scheduled, which only the lookup finds; 409 `id_taken`; 400 for parameters, headers or a non-object body; 503 `not_ready`; 422 `invalid`; 402 `exceeds_limit`.
- Permission is checked before any validation, and before any lookup except the one a rule that reads the record needs (AIP-193, AIP-211). Inside a project it is standing, a role the route's rule accepts, and MFA where the project requires it. A caller without it gets 403 `forbidden` whether or not the record exists, so a viewer's `PATCH` on a missing workflow is 403 and their `GET` on it is 404. Only a permitted caller hears 404 for a missing record, or 400 `invalid_parameter` for a path id that isn't a UUID, with one entry whose `path` names the segment, on any route including a `PUT` that would create.
- The parent of `/api/projects/:id`, `/api/provision/:id`, `/api/credentials/:id`, `/api/users/:id` and the top-level `/api/workflows/:id`, `/api/jobs/:id`, `/api/runs/:id` and `/api/work_orders/:id` is the instance. Permission on it is permission to learn which records of that kind exist. For projects that is `Scope.instance_wide?/1` (a superuser or the service account). For workflows, jobs, runs, work orders and users it is only the service account (`Scope.operator?/1`). For credentials it is only the service account to read, and anyone holding the grant to create through `PUT`, so a malformed id on `PUT /api/credentials/:id` is 400 to all of them. Anyone without it gets 403 for an unknown or malformed id. The parent of every route under `/api/projects/:project_id/` is that project, and a record that isn't in it is missing. A list's `project_id` query parameter is its parent in the same way, with the same 403, 404 and 400.
- A rule that reads the record itself, such as a credential's owner or the project a top-level record sits in, can't be decided when the record is missing. Decide first the part of the rule that needs no record and answer 403 if it refuses, as for the service account on any credential `DELETE`. Only when the answer depends on the record, answer 404 to a caller who may learn which records of that kind exist and 403 to anyone else (AIP-211). `Target.in_project_of/5` answers this for workflows, jobs, runs and work orders, and `Target.record/4` for credentials by asking the policy with a nil subject, which means the instance. A role or MFA never needs the record.
- A `PUT` on an id is an update that may create (AIP-134 `allow_missing`), except on workflows, where `PUT` is a plain update for now (404 for an unknown id). When the URL names the record that holds the id, it is an update, answering 200, or 403 `forbidden` to a caller without permission to update that record, even one who can see it. A free id is a create in the parent (201). An id held by a record at another URL is a create decided by permission on the URL's parent alone, answering 403 without it and 409 `id_taken` with it, whether or not the caller can see the holder.
- Read an id from the request with `Request.param/2`, which keeps where the request sent it, and hand that to `Target` or `Request.id/1`. When `Target` returns `{:error, :no_standing}`, `{:error, :no_such_project}` or `{:error, {:invalid_id, location}}`, return it unchanged for `FallbackController` to answer with 403, 404 or 400. The last is `Scope.fetch/2`'s answer to an instance-wide caller for a project id that isn't a UUID, with `Target` naming where the request sent it. Check every other id with `Request.id/1` after permission and before the lookup. On a project route, hand the id to `Target.in_project/5`, which parses it once permission is settled.
- `AuthorizeAction` checks the token grant before any lookup or body read. Passing it is not permission, so an action with a target asks again through `LightningWeb.API.Target`.
- 409 is about the record in the URL (`scheduled_for_deletion`, `concurrent_edit`, or `id_taken` for an id held at another URL). 422 is about the body. A duplicate, even alone, is a `taken` entry in a 422 `invalid` from `Errors.problem/3`. A reference in the body the caller can't use is 422 too, not 403; on a credential's project links it is a `not_found` or `no_access` entry. `concurrent_edit` comes only from the write, so a 422 beats it. A credential's owner applies only on create, so a replace that names a different owner is 422 with a `not_allowed` entry at `#/owner`.
- 503 `not_ready` always carries `retry_after: 5`, through `Problem.new(:not_ready, retry_after: 5)` or a changeset error coded `not_ready`, which `Errors.problem/3` maps.

## Controllers and contexts

- Controllers call context functions and never use `Repo` or build queries; `Lightning.Credo.Check.ApiControllerNoRepo` enforces this under `controllers/api/`. Changesets to check input are fine. For pages, read the parameters with `LightningWeb.API.Filters.page/1` and pass them to the context.
- The service account (`Scope.operator?/1`) must send `project_id` on `GET /api/log_lines`, `/api/runs` and `/api/work_orders`, because those tables grow with every run and an unfiltered page counts every row in them. Without it the answer is 400 `invalid_parameter` with a `required` entry at `parameter: project_id`.
- A controller with `action_fallback LightningWeb.API.FallbackController` leaves every status to it. Return the refusal from the `with`.
- `FallbackController` has one clause per known result and no catch-all, so anything else raises as a 500. Don't add a catch-all, or a clause for `{:error, :unauthorized}`, because a refused permission is 403, never 401.
- A context function never names a status. It returns a changeset, a bare atom such as `{:error, :concurrent_edit}`, or a limiter refusal `{:error, reason, %Lightning.Extensions.Message{}}`.
- A repeat `PUT` writes nothing and no audit entry. A create that fails on the id (`Request.id_taken?/1`) means another request created it first, so rerun the request from the lookup, which now finds the id. A body `id` must match the path (`Request.validate_matches_path/4`).
- On `/collections` (`LightningWeb.CollectionsController`), a missing item answers 204 and a delete that finds nothing answers 200 with `deleted: 0`, never 404, because deployed adaptors treat any 404 as a missing collection and fail the job. Resolve a name with `Collections.resolve_collection/3`, which looks only among the projects the caller can see. A `project_id` narrows that search, so one outside it, or one that isn't a UUID, matches nothing and answers 404.

## Codes

- `LightningWeb.API.Codes` is the contract. Adding a code is compatible; renaming, removing or moving one to another status is breaking, entry codes included. Moving a refusal between 404 and 403 is breaking too.
- A response's top-level `detail` is fixed per code and never repeats a request value or a limiter's message. `Errors.problem/3` raises on a changeset error that has neither a `code:` nor an Ecto option it maps; there is no fallback code.
- To add a code:
  1. Reuse an existing code in `Codes` if one means the same. A code that only restates an HTTP status takes HTTP's name, such as `content_too_large`.
  2. For an entry code in `lib/lightning`, add `code: :your_code` to the validator, then to the entry list.
  3. For an entry code set in `lib/lightning_web`, add it to the entry list.
  4. For a response code, add it with its status and fixed detail, add the row to `codes_test.exs`, then produce it with a `FallbackController` clause or `Problem.new`.

## A new endpoint

- Five steps:
  1. Choose the pipeline; for people and the service account, `person_or_service_account_api`.
  2. Give the action a token grant and a rule in a policy (see `policies.md`). A new resource API brings its own write grant, added to `Lightning.ServiceAccount.AccessToken`'s list; a write grant also covers reads of that resource, unless the resource has its own read grant, as users have `users:read`.
  3. Add `plug AuthorizeAction, {policy, action}` per action.
  4. Name the route's parent, the instance or a project. On `conn.assigns.scope`, use `Target.project/3` for a project, `Target.in_project/5` for a record in the path's project, `Target.in_project_of/5` for a top-level record whose project comes from the record, and `Target.record/4` for a top-level record with no project, such as a credential. Delete hand-written not-found branches. A lookup outside `Target` asks the policy before it answers `:not_found`.
  5. Leave every status to `FallbackController`.
