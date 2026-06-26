# Decoupling experiment: service skeletons

This directory holds the **Phase 3** proof for the Lightning decoupling
experiment (see `../MIGRATION_PLAN.md` and `../docs/`). It is a *design
experiment*, not production code.

## What's here

```
decoupling-experiment/
  credentials_service/   ← the ONE real vertical slice (Credentials), compiles + tests pass
```

Only **Credentials** is migrated, per the phase plan. Every other surface
(Projects, Workflows, Runs, AI, ...) is intentionally NOT built here; they are
mapped in `../docs/page-inventory.md` and represented as clearly-marked stub
modules in `credentials_service/lib/credentials_service/stubs.ex`. Nothing is
silently faked: the stubs raise, and the cross-service seams are named.

## credentials_service

A standalone Phoenix + Ecto service (no LiveView) that owns only the Credentials
surface, extracted from `lib/lightning/credentials*` and
`lib/lightning_web/controllers/api/credential_*`. It implements the REST contract
from `../docs/api.md` (JSON:API envelope) over the real schemas and Cloak
encryption.

- **Schemas:** `Credential`, `CredentialBody` (Cloak-encrypted, per-environment),
  `OauthClient`, `ProjectCredential` (the projects↔credentials join).
- **Context:** `CredentialsService.Credentials` (create/list/get/delete + the
  pure OAuth-expiry and sensitive-value logic).
- **Encryption:** `CredentialsService.Vault` + `...Encrypted.Map` mirror
  `Lightning.Vault` / `Lightning.Encrypted.Map`.
- **Web:** `CredentialController` + `CredentialJSON` + `FallbackController`, with
  authentication moved into a request plug (`AuthPlug`) instead of LiveView
  `on_mount`.

### Running it

Requires Elixir + Erlang and a reachable PostgreSQL. In this experiment's
container the toolchain was Elixir 1.17.3 on Erlang/OTP 25 with Postgres 16 at
`postgres:postgres@localhost`. (The monolith targets Elixir 1.18 / OTP 27; see
the toolchain note below.)

```bash
cd credentials_service
mix deps.get
mix test            # creates + migrates the test DB, then runs the suite
```

Last run: **17 tests, 0 failures** (context + encryption-at-rest + DB + the
Phoenix controller end to end).

## What building the slice actually revealed (feeds Phase 4)

These are observations from doing the extraction, not hypotheticals:

1. **The encryption key travels with the data.** `credential_bodies.body` is only
   ever ciphertext, so any service owning that table must hold the AES key (or run
   a re-encryption migration). The monolith's audit rows *also* embed encrypted
   bodies, so the audit store is in scope too.
2. **Identity and project scope become opaque cross-context FKs.** `user_id`
   (Accounts) and `project_id` (Projects, via `project_credentials`) are plain
   `:binary_id` columns here, not `belongs_to`. The service can store them but
   cannot answer "can this user access this project?" locally: roles live in
   `project_users`, owned by Projects. Authorization needs a membership contract
   across the boundary.
3. **Deletion is an `Ecto.Multi` that spans context boundaries.** Only deleting
   the local `project_credentials` rows stays a real DB transaction. Nulling
   `jobs.project_credential_id` (Workflows), revoking OAuth tokens (AuthProviders,
   HTTP), and emailing the owner (Accounts) cannot join that transaction. The
   `remove_external_associations/1` seam marks exactly where atomicity is lost.
4. **OAuth refresh is hot-path, network-bound, and must persist transactionally.**
   It is documented as a stub, not built, because it pulls in AuthProviders and
   sits on the critical path of every run that uses an OAuth credential.
5. **The audit trail resists clean extraction.** 9 credential audit events, some
   emitted inside the deletion/transfer Multi. Kept as a documented stub.
6. **`oauth_clients.client_secret` is plaintext at rest** in the monolith today.
   Preserved faithfully here (flagged) rather than silently "fixed."
7. **The REST/controller/JSON layer was the easy part.** The monolith's `api/*`
   controllers already modeled the pattern, and moving auth into a plug was clean.
   The friction is entirely in the data/transaction/encryption coupling above, not
   the HTTP layer.

### Toolchain note

The container shipped no Elixir; apt offered only 1.14, but modern hex deps
(`plug` 1.18, `postgrex` 0.19+, `ecto_sql` 3.14) require Elixir 1.15+. Rather than
pin every dependency down to ancient versions, a precompiled Elixir 1.17.3
(OTP-25 build) was installed over the apt Erlang 25. This itself mirrors a real
constraint: Lightning pins Erlang 27.3.3 / Elixir 1.18.3 in `.tool-versions`, and
the dependency floor is why.
