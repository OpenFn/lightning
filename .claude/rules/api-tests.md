---
paths:
  - "test/lightning_web/api/**/*.exs"
  - "test/lightning_web/controllers/api/**/*.exs"
  - "test/lightning_web/controllers/webhooks_controller*_test.exs"
  - "test/lightning_web/controllers/project_mfa_enforcement_test.exs"
  - "test/lightning_web/controllers/user_auth_test.exs"
  - "test/lightning_web/controllers/adaptor_controller_test.exs"
  - "test/lightning_web/collections_controller_test.exs"
  - "test/lightning_web/collections/**/*.exs"
  - "test/lightning_web/controllers/webhooks/**/*.exs"
  - "test/lightning_web/plugs/channel_proxy/**/*.exs"
  - "test/lightning_web/auth_test.exs"
  - "test/lightning_web/plugs/access_token_auth_test.exs"
  - "test/lightning_web/plugs/person_or_service_account_auth_test.exs"
  - "test/lightning_web/plugs/webhook_auth_test.exs"
  - "test/lightning_web/plugs/channel_proxy*_test.exs"
  - "test/support/api_*.ex"
  - "test/lightning/collections_test.exs"
  - "test/lightning/collections_item*_test.exs"
  - "test/lightning/invocation/query_test.exs"
  - "test/lightning/projects/provisioner_test.exs"
  - "test/lightning/workflows/graph_rules_test.exs"
---

# API error tests

These files test what clients of `/api`, `/collections`, `/i/*` webhooks and the `/channels/*` proxy get back, and the modules that build those answers. Each promise a client relies on is tested in exactly one home. Before writing a test, find that home.

## Where each promise is tested

- **No token, a garbage token, a token of the wrong kind:** `api/sentinel_sweep_test.exs`, which walks every route from the router, and `auth_test.exs`, which holds the token-kind table and the lockout example. Controller test files keep no "without a token" or "with an invalid token" test.
- **A rule in shared code** (`Filters`, `Request`, `Problem`'s Accept handling, pointer escaping, `Errors`): the module's unit test holds the cases. Each route that uses the module keeps one test that fails if the route stops calling it, for example one paging test per route that calls `Filters.page/1`.
- **Who may reach a resource, what role it needs:** one table test per route family. For each caller without permission (no standing, a role the rule refuses, unmet MFA) it covers an existing record, an unknown id and a malformed id, and asserts the same 403 `forbidden` body for all three. For a permitted caller, a malformed id is 400 `invalid_parameter`, and an unknown id is 404 (a `PUT` that creates is the success test's promise). The table holds refusals and the permitted 404 and 400, each an answer that varies by caller; success stays in its own test. Where the rule reads the record, a missing one is 404 to a caller who may learn which records of that kind exist and 403 to anyone else. A `PUT` also covers a record the caller may see but not update (403 `forbidden`), and an id held at another URL, which is 409 `id_taken` to a caller permitted on the URL's parent, whether or not they can see the holder, and 403 to one who isn't.
- **Every route reaches the MFA check:** `project_mfa_enforcement_test.exs` sweeps the routes on an existing record, each beside an enrolled member. The family tables still hold the unmet-MFA rows, which show the 403 doesn't depend on the id.
- **Each code's status and `detail` wording:** the table in `api/codes_test.exs`, written out literally. Rewording a code means editing its row there.
- **Everything else a route does:** the route test, through the router (`put(conn, ~p"/api/...", body)`), asserting status, headers and the whole body.

A unit test of an API module exists for a promise no route can show (a 16-byte string as an id, the five-way Accept table) or a guard a developer hits. When a route test and a unit test both hold a promise, the unit test keeps the cases and the route keeps its one wiring test.

## Writing a test

- When a status or body changes, change the existing test, renaming it if its name stops being true. Add a test only for a promise that did not exist before. A new test with the same route and setup as an existing one means the existing one should have been edited.
- One operation per test, every assertion in it. Compare the whole body with `==`. Several inputs to one rule go in one table test (`for {input, expected} <- [...]`); different setups, or success against refusal, stay separate tests.
- Assert errors with `assert_problem(conn, status, code, entries)` by code, listing the entries exactly (`[]` when there are none). The response `detail` comes from `codes_test.exs`; each entry's `detail` is written out in the route test that produces it. Write challenge strings out in full with `assert_unauthenticated/3`.
- Every `/api` route that writes has its own stale-write test, in which another request deletes or changes the record mid-write (`Lightning.RaceHelpers.after_first_query/4`), and the route answers `assert_problem(409, :concurrent_edit, [])` and leaves the record as the other request left it. A new write route gets one too.
- `Lightning.Extensions.UsageLimiting.error_reason` lists four reasons, and the production limiter returns others as well. A test that stubs a limiter (`MockUsageLimiter`, `MockRateLimiter`) stubs at least one reason outside that type alongside the ones it checks. A stub that always returns `:exceeds_limit` passes even when every other reason crashes with a 500.
- When the same setup or assertion appears a third time, move it to `test/support`.
- Before deleting or merging a test, name the test that still holds its promise, then break that behaviour in `lib` and watch the surviving test fail.

## Names and layout

- Describes and test names say what the client is doing: "reading", "creating", "refusals", "stale writes", "who may reach it". Put a new test beside the behaviour it refines.
- Names, describes and comments cite no spec section numbers, commit refs, ticket numbers or files outside this repo. Say the rule itself.
- Keep a file near 400 lines and always under 1,000. Split by behaviour (`workflows/creating_test.exs`, `workflows/stale_writes_test.exs`), not by position in the file.

## Core context tests

The `test/lightning/` files here alias and import only `Lightning` modules. Assert on `changeset.errors`, with each error's `code:` and key list. Pointer strings and problem bodies are a web promise, so they belong in a route test.
