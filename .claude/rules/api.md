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

- The first failed check answers, in this order: a failed login, 401 or 400 for a malformed `Authorization` header (`LightningWeb.Auth.refuse/2`); 403 `insufficient_scope`; 403 `forbidden` for no standing on the record or its parent; 404 `not_found`, only to a caller past that step; 403 for MFA or the rule; 409 `scheduled_for_deletion`; 400 for parameters, headers or a non-object body; 503 `not_ready`; 422 `invalid`; 402 `exceeds_limit`.
- Access errors follow Google's AIP-193, and permission is checked before the request is validated (AIP-211). A caller without permission on the record, or on the parent it sits in, gets 403 `forbidden` whether or not the record exists. Only a caller with permission on the parent gets 404 `not_found` for a missing record. A path id that isn't a UUID names nothing, so it answers the same way as an unknown id.
- The parent of `/api/projects/:id`, `/api/provision/:id`, `/api/credentials/:id` and the top-level `/api/workflows/:id`, `/api/jobs/:id`, `/api/runs/:id` and `/api/work_orders/:id` is the instance. So an unknown or malformed project id is 403 to anyone but a superuser or the service account, and an unknown credential id on `GET` or `DELETE` is 403 to anyone but the service account. The parent of every route under `/api/projects/:project_id/` is the project, so a stranger to it gets 403 whatever the inner id, and a record that isn't in that project is missing.
- A `PUT` the caller may use to create (a credential, or a collection in a project they may write) answers an unknown id with 201. When the id is already held, it is 409 `id_taken` only if the caller can see the record that holds it; otherwise 403 `forbidden` (AIP-133). Ask the policy's see action, such as `:see_credential`, or the caller's standing on the project that holds the record. A refused edit alone doesn't decide it.
- When `Scope.fetch/2` (through `Target`) returns `{:error, :no_standing}` or `{:error, :no_such_project}`, return it unchanged and let `FallbackController` answer it, 403 and 404 respectively. Don't pick a status for it in a controller, and don't answer a missing record with `:not_found` before the caller's standing on its parent is known.
- `AuthorizeAction` checks the token grant before any lookup or body read. Passing it is not permission: an action with a target asks again through `LightningWeb.API.Target`.
- 409 is about the record in the URL (`scheduled_for_deletion`, `concurrent_edit`, or `id_taken` for an id held by a record the caller can see but can't touch). 422 is about the body. A duplicate, even alone, is a `taken` entry in a 422 `invalid` from `Errors.problem/3`. A reference in the body the caller can't use is 422 too, not 403; on a credential's project links it is a `not_found` or `no_access` entry.
- Look the id up before reading the body, so `id_taken` and `scheduled_for_deletion` beat body errors. `concurrent_edit` comes only from the write, so a 422 beats it.
- 503 `not_ready` always carries `retry_after: 5`: `Problem.new(:not_ready, retry_after: 5)`, or a changeset error coded `not_ready`, which `Errors.problem/3` maps.

## Controllers and contexts

- Controllers call context functions and never use `Repo` or build queries; `Lightning.Credo.Check.ApiControllerNoRepo` enforces this under `controllers/api/`. Changesets to check input are fine. For pages, read the parameters with `LightningWeb.API.Filters.page/1` and pass them to the context.
- A controller with `action_fallback LightningWeb.API.FallbackController` leaves every status to it. Return the refusal from the `with`.
- `FallbackController` has one clause per known result and no catch-all, so anything else raises as a 500. Don't add a catch-all, or a clause for `{:error, :unauthorized}`: a refused permission is 403, never 401.
- A context function never names a status. It returns a changeset, a bare atom such as `{:error, :concurrent_edit}`, or a limiter refusal `{:error, reason, %Lightning.Extensions.Message{}}`.
- `PUT` on projects, credentials and a project's collections creates (201) when the id is free and replaces (200) when it belongs to that record. A repeat request writes nothing and no audit entry. A create that fails on the id (`Request.id_taken?/1`) means another request created it first, so rerun it as a replace. A body `id` must match the path (`Request.validate_matches_path/4`).
- On `/collections` (`LightningWeb.CollectionsController`), a missing item answers 204 and a delete that finds nothing answers 200 with `deleted: 0`, never 404: deployed adaptors treat any 404 as a missing collection and fail the job. Resolve a name with `Collections.resolve_collection/3`, which looks only among the projects the caller can see.

## Codes

- `LightningWeb.API.Codes` is the contract. Adding a code is compatible; renaming, removing or moving one to another status is breaking, entry codes included.
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
  4. Name the route's parent, the instance or a project. Use `Target.project/3` or `Target.in_project/4` on `conn.assigns.scope`; delete hand-written not-found branches. A lookup outside `Target` checks the caller's standing on the parent before it answers `:not_found`.
  5. Leave every status to `FallbackController`.
