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

## Order and statuses

- The first failed check answers, in this order: a failed login, 401 or 400 for a malformed `Authorization` header (`LightningWeb.Auth.refuse/2`); 403 `insufficient_scope`; no standing on the record or its parent; 404, only to a caller past that step; 403 for MFA or the rule; 409 `scheduled_for_deletion`; 400 for parameters, headers or a non-object body; 503 `not_ready`; 422 `invalid`; 402 `exceeds_limit` (contract doc, "Which status you get").
- When `Scope.fetch/2` (through `Target`) returns `{:error, :no_standing}` or `{:error, :no_such_project}`, return it unchanged and let `FallbackController` answer it. Don't pick a status for it in a controller.
- `AuthorizeAction` checks the token grant before any lookup or body read. Passing it is not permission: an action with a target asks again through `LightningWeb.API.Target`.
- 409 is about the record in the URL (`scheduled_for_deletion`, `concurrent_edit`, or `id_taken` for an id that belongs to something the caller can't touch). 422 is about the body. A duplicate, even alone, is a `taken` entry in a 422 `invalid` from `Errors.problem/3`. A reference in the body the caller can't use is 422 too, not 403; on a credential's project links it is a `not_found` or `no_access` entry.

## Controllers and contexts

- Controllers call context functions and never use `Repo` or build queries; `Lightning.Credo.Check.ApiControllerNoRepo` enforces this under `controllers/api/`. Changesets to check input are fine. For pages, read the parameters with `LightningWeb.API.Filters.page/1` and pass them to the context.
- A controller with `action_fallback LightningWeb.API.FallbackController` leaves every status to it. Return the refusal from the `with`.
- `FallbackController` has one clause per known result and no catch-all, so anything else raises as a 500. Don't add a catch-all, or a clause for `{:error, :unauthorized}`: a refused permission is 403, never 401.
- A context function never names a status. It returns a changeset, a bare atom such as `{:error, :concurrent_edit}`, or a limiter refusal `{:error, reason, %Lightning.Extensions.Message{}}` (contract doc, "How an error becomes a response").
- `PUT` on projects, credentials and a project's collections creates (201) when the id is free and replaces (200) when it belongs to that record. A repeat request writes nothing and no audit entry. A body `id` must match the path (`Request.validate_matches_path/4`).
- On `/collections` (`LightningWeb.CollectionsController`), a missing item answers 204 and a delete that finds nothing answers 200 with `deleted: 0`, never 404: deployed adaptors treat any 404 as a missing collection and fail the job.

## Codes

- `LightningWeb.API.Codes` is the contract. Adding a code is compatible; renaming, removing or moving one to another status is breaking, entry codes included.
- A response's top-level `detail` is fixed per code and never repeats a request value or a limiter's message. `Errors.problem/3` raises on a changeset error that has neither a `code:` nor an Ecto option it maps; there is no fallback code.
- To add a code (contract doc, "Codes are the contract"):
  1. Reuse an existing code in `Codes` if one means the same. A code that only restates an HTTP status takes HTTP's name, such as `content_too_large`.
  2. For an entry code in `lib/lightning`, add `code: :your_code` to the validator, then to the entry list.
  3. For an entry code set in `lib/lightning_web`, add it to the entry list.
  4. For a response code, add it with its status and fixed detail, add the row to `codes_test.exs`, then produce it with a `FallbackController` clause or `Problem.new`.

## A new endpoint

- Five steps (auth doc, "Five steps for a new endpoint"):
  1. Choose the pipeline; for people and the service account, `person_or_service_account_api`.
  2. Give the action a token grant and a rule in a policy (see `policies.md`). A new resource API brings its own write grant, added to `Lightning.ServiceAccount.AccessToken`'s list; a write grant also covers reads of that resource.
  3. Add `plug AuthorizeAction, {policy, action}` per action.
  4. Use `Target.project/3` or `Target.in_project/4` on `conn.assigns.scope`; delete hand-written not-found branches.
  5. Leave every status to `FallbackController`.
