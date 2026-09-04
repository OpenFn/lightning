# Issue Triage — 100 Oldest Open Issues, openfn/lightning

Run 2026-09-04 against the 100 oldest open issues (created Apr 2022 – Feb 2024),
out of 661 open in total. Each issue was fetched with its comments, checked
against the current code in the local checkout, and cross-checked against open
and closed issues for duplicates and prior fixes.

## Headline

| Verdict | Count |
|---|---|
| New — genuinely open work | 56 |
| Already fixed | 29 |
| Already tracked elsewhere | 8 |
| Not an issue | 7 |

**44 of 100 (44%) are closable today** — fixed, superseded, or not actionable.
Nothing in the set scored above P2, and only one scored P2.

| Priority | Count |
|---|---|
| P2 | 1 |
| P3 | 21 |
| P4 | 34 |

| Type | Count |  | Complexity | Count |  | Quality | Count |
|---|---|---|---|---|---|---|---|
| Improvement | 42 |  | Low | 17 |  | High | 7 |
| Feature | 17 |  | Medium | 28 |  | Medium | 28 |
| Bug | 8 |  | High | 11 |  | Low | 22 |

Issue quality is the weak spot: of the 56 live issues, 22 scored Low. Several
2023-era issues have bodies consisting only of dead private Zenhub image links
(#1444, #1445, #1447), so the original ask is unrecoverable.

## What to look at first

Three items stand out from the 56 live issues, for different reasons:

- **[#1579](https://github.com/openfn/lightning/issues/1579) — Either Password or 2FA for accessing Webhook Auth info, not both.** This is a live authorization gap, not a UX nit. `lib/lightning_web/live/workflow_live/webhook_auth_method_form_component.ex:208` accepts `valid_password?(...) || valid_user_totp?(...)` and never checks `mfa_enabled`, so a user with 2FA enabled can reveal a webhook secret with a password alone. The correct pattern already exists in `re_authenticate_live/new.ex`. Low complexity, High quality, and the only security-relevant finding in the set.
- **[#589](https://github.com/openfn/lightning/issues/589) — Remove run logs from emails.** The only P2. `failure_alert.html.heex:23` still dumps every log line into the alert email with no config knob, which is a data-exposure surface for anyone whose logs carry sensitive state.
- **[#59](https://github.com/openfn/lightning/issues/59) — Add CSP to router.ex.** Open since April 2022 and still fully open: `router.ex:27` has a bare `put_secure_browser_headers` and `.sobelow-conf` still ignores `Config.CSP`. High complexity because of inline scripts and Monaco, but there is an in-repo precedent at `lib/lightning_web/plugs/channel_proxy_plug.ex:39-45`.

A recurring pattern worth noting separately: several issues are **stale in approach rather than stale in problem**. #158, #160, #470, #518 and #1594 describe real needs, but were written against an architecture (no-code job builder, `assemble_state`, standalone `workflow-diagram` library, intro.js onboarding) that no longer exists. Those need a product decision before they can be estimated, not engineering triage.

## The 44 closable issues

### Already fixed (29)
Verified against current code; see per-issue detail for the specific module or PR.
- [#117](https://github.com/openfn/lightning/issues/117) Decide if/how to handle SSL cert authenticity warning for repo connection
- [#259](https://github.com/openfn/lightning/issues/259) Unclear error message when credential ownership transfer is blocked?
- [#262](https://github.com/openfn/lightning/issues/262) Broaden access for project admin role
- [#308](https://github.com/openfn/lightning/issues/308) Application fails to start when external auth provider is unavailable
- [#318](https://github.com/openfn/lightning/issues/318) Set character limit for workflow names
- [#397](https://github.com/openfn/lightning/issues/397) Get superusers to set up a project on account creation
- [#597](https://github.com/openfn/lightning/issues/597) Hide noisy schema installation log from tests
- [#715](https://github.com/openfn/lightning/issues/715) Improve API error codes
- [#749](https://github.com/openfn/lightning/issues/749) Clear runs queue for a project
- [#751](https://github.com/openfn/lightning/issues/751) Adaptors should not be installed as latest
- [#789](https://github.com/openfn/lightning/issues/789) Handle session token expiry
- [#808](https://github.com/openfn/lightning/issues/808) Add confirmation modal to project deletion (superuser)
- [#815](https://github.com/openfn/lightning/issues/815) Handle final status for parallel runs
- [#913](https://github.com/openfn/lightning/issues/913) Export projects as .zip (yaml, state, config)
- [#934](https://github.com/openfn/lightning/issues/934) `googlehealthcare` credential setup
- [#946](https://github.com/openfn/lightning/issues/946) Add a flag to stop sensitive state being logged
- [#1081](https://github.com/openfn/lightning/issues/1081) Show read-only view to non-admins in Project Settings section
- [#1254](https://github.com/openfn/lightning/issues/1254) Partition tables by week and setup maintenance code
- [#1437](https://github.com/openfn/lightning/issues/1437) Improve UX for adding/removing auth methods to webhooks
- [#1444](https://github.com/openfn/lightning/issues/1444) Need to create an empty state for the webhook auth methods settings page when no auth methods exist
- [#1447](https://github.com/openfn/lightning/issues/1447) Update UI for personal access token copy field
- [#1535](https://github.com/openfn/lightning/issues/1535) Allow input and output dataclips to be optional for runs
- [#1544](https://github.com/openfn/lightning/issues/1544) Relax log event restrictions for runs
- [#1582](https://github.com/openfn/lightning/issues/1582) Improve UX around "disabling" first edge
- [#1590](https://github.com/openfn/lightning/issues/1590) Harmonize different uses of new inputs
- [#1597](https://github.com/openfn/lightning/issues/1597) Support smaller screens on inspector
- [#1693](https://github.com/openfn/lightning/issues/1693) Solve the `other_params` problem (UberAuth/OAuth2 library)
- [#1713](https://github.com/openfn/lightning/issues/1713) Set names via exmachina sequences
- [#1755](https://github.com/openfn/lightning/issues/1755) Control log outputs (Epic)

### Already tracked elsewhere (8)
- [#220](https://github.com/openfn/lightning/issues/220) Credential types list should be pre-populated (caching?)
- [#251](https://github.com/openfn/lightning/issues/251) Rollback to a previous version
- [#299](https://github.com/openfn/lightning/issues/299) OIDC multiple providers user interface
- [#301](https://github.com/openfn/lightning/issues/301) OIDC account creation
- [#325](https://github.com/openfn/lightning/issues/325) Build service to pull credential schemas from npm/github
- [#981](https://github.com/openfn/lightning/issues/981) Improve performance of the History page queries
- [#1445](https://github.com/openfn/lightning/issues/1445) Improve validation handling when changing email
- [#1670](https://github.com/openfn/lightning/issues/1670) Un-mark workflow deletion

### Not an issue (7)
Questions, dead premises, or asks with no actionable work left.
- [#290](https://github.com/openfn/lightning/issues/290) Standard patterns for LiveView and changesets (incl embeds)
- [#300](https://github.com/openfn/lightning/issues/300) OIDC
- [#703](https://github.com/openfn/lightning/issues/703) Better performance profiling/stress-testing
- [#772](https://github.com/openfn/lightning/issues/772) Benchmark data sent between page loads
- [#894](https://github.com/openfn/lightning/issues/894) Improve pattern for conditionally render things based on permissions
- [#1697](https://github.com/openfn/lightning/issues/1697) Sql to clean duplicate dataclips
- [#1717](https://github.com/openfn/lightning/issues/1717) Can't load workflow on Safari 15.3

## Full summary table

| # | Title | Verdict | Type | Priority | Complexity | Quality |
|---|---|---|---|---|---|---|
| [#59](https://github.com/openfn/lightning/issues/59) | Add CSP to router.ex | New | Improvement | P3 | High | Medium |
| [#117](https://github.com/openfn/lightning/issues/117) | Decide if/how to handle SSL cert authenticity warning for repo connection | Already fixed | — | — | — | — |
| [#119](https://github.com/openfn/lightning/issues/119) | Get buildx with linux/amd64 platform working on M1s | New | Bug | P4 | Medium | Medium |
| [#123](https://github.com/openfn/lightning/issues/123) | Consider moving Sentry out of lightning | New | Improvement | P4 | Medium | Medium |
| [#152](https://github.com/openfn/lightning/issues/152) | Documentation for the API | New | Improvement | P3 | Medium | Low |
| [#158](https://github.com/openfn/lightning/issues/158) | Render adaptor functions in a picklist, display labelled text inputs for each argument | New | Feature | P4 | High | Medium |
| [#160](https://github.com/openfn/lightning/issues/160) | Add interface to set default "initial state" for a job | New | Feature | P4 | Medium | Medium |
| [#201](https://github.com/openfn/lightning/issues/201) | Choose between `select_field` and `select`; document and implement across app | New | Improvement | P4 | Low | Medium |
| [#220](https://github.com/openfn/lightning/issues/220) | Credential types list should be pre-populated (caching?) | Already tracked | — | — | — | — |
| [#251](https://github.com/openfn/lightning/issues/251) | Rollback to a previous version | Already tracked | — | — | — | — |
| [#259](https://github.com/openfn/lightning/issues/259) | Unclear error message when credential ownership transfer is blocked? | Already fixed | Bug | — | — | — |
| [#262](https://github.com/openfn/lightning/issues/262) | Broaden access for project admin role | Already fixed | Improvement | — | — | — |
| [#290](https://github.com/openfn/lightning/issues/290) | Standard patterns for LiveView and changesets (incl embeds) | Not an issue | — | — | — | — |
| [#299](https://github.com/openfn/lightning/issues/299) | OIDC multiple providers user interface | Already tracked | Feature | — | — | — |
| [#300](https://github.com/openfn/lightning/issues/300) | OIDC | Not an issue | — | — | — | — |
| [#301](https://github.com/openfn/lightning/issues/301) | OIDC account creation | Already tracked | Feature | — | — | — |
| [#308](https://github.com/openfn/lightning/issues/308) | Application fails to start when external auth provider is unavailable | Already fixed | Bug | — | — | — |
| [#312](https://github.com/openfn/lightning/issues/312) | Assign a map of global constants to a job | New | Feature | P4 | High | Low |
| [#318](https://github.com/openfn/lightning/issues/318) | Set character limit for workflow names | Already fixed | Improvement | — | — | — |
| [#325](https://github.com/openfn/lightning/issues/325) | Build service to pull credential schemas from npm/github | Already tracked | Feature | — | — | — |
| [#365](https://github.com/openfn/lightning/issues/365) | Log access control events | New | Feature | P3 | Medium | Low |
| [#397](https://github.com/openfn/lightning/issues/397) | Get superusers to set up a project on account creation | Already fixed | — | — | — | — |
| [#457](https://github.com/openfn/lightning/issues/457) | Ability to skip downstream jobs when invoking a manual run | New | Feature | P3 | High | Low |
| [#470](https://github.com/openfn/lightning/issues/470) | Integrate intro.js tutorial | New | Feature | P4 | Medium | Low |
| [#475](https://github.com/openfn/lightning/issues/475) | General performance concerns with large dataclips | New | Improvement | P3 | Medium | Medium |
| [#492](https://github.com/openfn/lightning/issues/492) | Add endpoint for generating adaptor docs | New | Improvement | P3 | Medium | High |
| [#496](https://github.com/openfn/lightning/issues/496) | Refactor namespacing to better fit our current design | New | Improvement | P4 | High | High |
| [#513](https://github.com/openfn/lightning/issues/513) | Convert controller pages to liveview | New | Improvement | P4 | Medium | Low |
| [#518](https://github.com/openfn/lightning/issues/518) | Add property to control edge type | New | Improvement | P4 | Low | Low |
| [#524](https://github.com/openfn/lightning/issues/524) | Adaptor docs sometimes pulls down too much data (and so is slow) | New | Bug | P4 | Low | High |
| [#589](https://github.com/openfn/lightning/issues/589) | Add feature to remove run logs from emails | New | Feature | P2 | Medium | Medium |
| [#593](https://github.com/openfn/lightning/issues/593) | Allow user to limit search for last run per work order | New | Improvement | P3 | Medium | Medium |
| [#597](https://github.com/openfn/lightning/issues/597) | Hide noisy schema installation log from tests | Already fixed | — | — | — | — |
| [#598](https://github.com/openfn/lightning/issues/598) | Fix (or silence?) occasional postgrex connection error in tests | New | Bug | P4 | Medium | Low |
| [#635](https://github.com/openfn/lightning/issues/635) | Convert registration page from controller page to liveview | New | Improvement | P4 | Medium | Medium |
| [#643](https://github.com/openfn/lightning/issues/643) | Enable caching | New | Improvement | P4 | Low | Medium |
| [#644](https://github.com/openfn/lightning/issues/644) | Refresh cache on application start up | New | Improvement | P4 | Low | Medium |
| [#693](https://github.com/openfn/lightning/issues/693) | Spike: Find better solution for Process.sleep() for FailureAlert tests | New | Improvement | P4 | Medium | Medium |
| [#703](https://github.com/openfn/lightning/issues/703) | Better performance profiling/stress-testing | Not an issue | — | — | — | — |
| [#715](https://github.com/openfn/lightning/issues/715) | Improve API error codes | Already fixed | — | — | — | — |
| [#720](https://github.com/openfn/lightning/issues/720) | Use html templates for emailing | New | Improvement | P4 | Medium | Low |
| [#724](https://github.com/openfn/lightning/issues/724) | Improve UI for roles and permissions | New | Improvement | P4 | Medium | Low |
| [#749](https://github.com/openfn/lightning/issues/749) | Clear runs queue for a project | Already fixed | — | — | — | — |
| [#751](https://github.com/openfn/lightning/issues/751) | Adaptors should not be installed as latest | Already fixed | — | — | — | — |
| [#772](https://github.com/openfn/lightning/issues/772) | Benchmark data sent between page loads | Not an issue | — | — | — | — |
| [#780](https://github.com/openfn/lightning/issues/780) | Warn before closing a form with unsaved changes | New | Improvement | P3 | Medium | Medium |
| [#789](https://github.com/openfn/lightning/issues/789) | Handle session token expiry | Already fixed | — | — | — | — |
| [#795](https://github.com/openfn/lightning/issues/795) | Provide count of work orders that had failed but have been fixed in the last week | New | Feature | P4 | Medium | Medium |
| [#808](https://github.com/openfn/lightning/issues/808) | Add confirmation modal to project deletion (superuser) | Already fixed | — | — | — | — |
| [#815](https://github.com/openfn/lightning/issues/815) | Handle final status for parallel runs | Already fixed | — | — | — | — |
| [#843](https://github.com/openfn/lightning/issues/843) | Workflow Diagram: Keyboard control | New | Feature | P4 | Medium | Medium |
| [#844](https://github.com/openfn/lightning/issues/844) | Notify users when a deletion is cancelled | New | Improvement | P3 | Low | Medium |
| [#849](https://github.com/openfn/lightning/issues/849) | Refactor delete user | New | Improvement | P4 | Low | Low |
| [#876](https://github.com/openfn/lightning/issues/876) | Consider blocking project update via API once its been marked for deletion | New | Improvement | P4 | Low | Medium |
| [#894](https://github.com/openfn/lightning/issues/894) | Improve pattern for conditionally render things based on permissions | Not an issue | — | — | — | Low |
| [#896](https://github.com/openfn/lightning/issues/896) | UI tweaks on bulk rerun modal | New | Improvement | P4 | Low | Low |
| [#913](https://github.com/openfn/lightning/issues/913) | Export projects as .zip (yaml, state, config) | Already fixed | — | — | — | — |
| [#934](https://github.com/openfn/lightning/issues/934) | `googlehealthcare` credential setup | Already fixed | — | — | — | — |
| [#946](https://github.com/openfn/lightning/issues/946) | Add a flag to stop sensitive state being logged | Already fixed | — | — | — | — |
| [#981](https://github.com/openfn/lightning/issues/981) | Improve performance of the History page queries | Already tracked | — | — | — | — |
| [#1000](https://github.com/openfn/lightning/issues/1000) | Refactor runtime handler and taskworker for dialyzer | New | Improvement | P4 | Low | Low |
| [#1055](https://github.com/openfn/lightning/issues/1055) | Adaptor docs: common `http` namespace is wrongly listed | New | Bug | P3 | Medium | Medium |
| [#1081](https://github.com/openfn/lightning/issues/1081) | Show read-only view to non-admins in Project Settings section | Already fixed | — | — | — | — |
| [#1138](https://github.com/openfn/lightning/issues/1138) | Add an "End of automation" node to the workflow | New | Feature | P4 | Medium | Medium |
| [#1207](https://github.com/openfn/lightning/issues/1207) | Allow user to have multiple triggers on a workflow | New | Feature | P3 | High | Low |
| [#1226](https://github.com/openfn/lightning/issues/1226) | Make it easier to see how to select all work orders | New | Improvement | P4 | Medium | Low |
| [#1254](https://github.com/openfn/lightning/issues/1254) | Partition tables by week and setup maintenance code | Already fixed | — | — | — | — |
| [#1300](https://github.com/openfn/lightning/issues/1300) | Port `crash_test` to `janitor_test` | New | Improvement | P4 | Low | Medium |
| [#1314](https://github.com/openfn/lightning/issues/1314) | In password inputs only show the eye/mask icon when the field is active | New | Improvement | P4 | Low | Medium |
| [#1349](https://github.com/openfn/lightning/issues/1349) | Add `error_type` granularity to pills displaying run state | New | Improvement | P3 | Medium | Medium |
| [#1350](https://github.com/openfn/lightning/issues/1350) | Adjust history filters to allow sub-selection of error_type under "state" | New | Improvement | P3 | Medium | Medium |
| [#1360](https://github.com/openfn/lightning/issues/1360) | Consider Re-ordering the activity history page when a work order is re-run | New | Improvement | P4 | Low | Low |
| [#1410](https://github.com/openfn/lightning/issues/1410) | Call a run "lost" if the socket is closed for N minutes | New | Improvement | P3 | High | High |
| [#1413](https://github.com/openfn/lightning/issues/1413) | Unsubscribe from Workflow emails via a link | New | Feature | P4 | Medium | Medium |
| [#1422](https://github.com/openfn/lightning/issues/1422) | Add ability to edit a stored dataclip | New | Feature | P4 | High | Low |
| [#1437](https://github.com/openfn/lightning/issues/1437) | Improve UX for adding/removing auth methods to webhooks | Already fixed | Improvement | — | — | — |
| [#1444](https://github.com/openfn/lightning/issues/1444) | Need to create an empty state for the webhook auth methods settings page when no auth methods exist | Already fixed | Improvement | — | — | — |
| [#1445](https://github.com/openfn/lightning/issues/1445) | Improve validation handling when changing email | Already tracked | Improvement | — | — | — |
| [#1447](https://github.com/openfn/lightning/issues/1447) | Update UI for personal access token copy field | Already fixed | Improvement | — | — | — |
| [#1460](https://github.com/openfn/lightning/issues/1460) | Redirect to desired page after login | New | Improvement | P3 | Medium | High |
| [#1467](https://github.com/openfn/lightning/issues/1467) | Improve Email Failure Alerts | New | Improvement | P4 | Low | Low |
| [#1478](https://github.com/openfn/lightning/issues/1478) | Introduce Node Authentication Audit information for ATNA compliance | New | Feature | P3 | High | Low |
| [#1535](https://github.com/openfn/lightning/issues/1535) | Allow input and output dataclips to be optional for runs | Already fixed | — | — | — | — |
| [#1544](https://github.com/openfn/lightning/issues/1544) | Relax log event restrictions for runs | Already fixed | — | — | — | — |
| [#1579](https://github.com/openfn/lightning/issues/1579) | Either Password or 2FA for accessing Webhook Auth info, not both | New | Bug | P3 | Low | High |
| [#1582](https://github.com/openfn/lightning/issues/1582) | Improve UX around "disabling" first edge | Already fixed | — | — | — | — |
| [#1583](https://github.com/openfn/lightning/issues/1583) | Handle different scenarios when user doesn't have access to page/feature | New | Improvement | P3 | High | Low |
| [#1590](https://github.com/openfn/lightning/issues/1590) | Harmonize different uses of new inputs | Already fixed | — | — | — | — |
| [#1594](https://github.com/openfn/lightning/issues/1594) | Rename MFA to 2FA | New | Improvement | P4 | Medium | Medium |
| [#1597](https://github.com/openfn/lightning/issues/1597) | Support smaller screens on inspector | Already fixed | — | — | — | — |
| [#1637](https://github.com/openfn/lightning/issues/1637) | Metadata Service (and docs service?) | New | Improvement | P3 | High | Medium |
| [#1651](https://github.com/openfn/lightning/issues/1651) | Investigate UX and tech limitations of deleting Jobs in the middle of workflow | New | Improvement | P3 | Medium | Low |
| [#1666](https://github.com/openfn/lightning/issues/1666) | Allow endpoint to be configured the same in dev as in prod | New | Improvement | P4 | Low | High |
| [#1670](https://github.com/openfn/lightning/issues/1670) | Un-mark workflow deletion | Already tracked | — | — | — | — |
| [#1693](https://github.com/openfn/lightning/issues/1693) | Solve the `other_params` problem (UberAuth/OAuth2 library) | Already fixed | — | — | — | — |
| [#1697](https://github.com/openfn/lightning/issues/1697) | Sql to clean duplicate dataclips | Not an issue | — | — | — | — |
| [#1713](https://github.com/openfn/lightning/issues/1713) | Set names via exmachina sequences | Already fixed | — | — | — | — |
| [#1717](https://github.com/openfn/lightning/issues/1717) | Can't load workflow on Safari 15.3 | Not an issue | — | — | — | — |
| [#1739](https://github.com/openfn/lightning/issues/1739) | Selecting a job node with a slow internet causes a `:timeout` error | New | Bug | P3 | Low | Medium |
| [#1755](https://github.com/openfn/lightning/issues/1755) | Control log outputs (Epic) | Already fixed | — | — | — | — |

## Detail by issue

# Triage batch 01 — openfn/lightning (issues 59, 117, 119, 123, 152, 158, 160, 201, 220, 251)

## #59 — Add CSP to router.ex
- **Verdict:** New
- **Type:** Improvement
- **Priority:** P3
- **Complexity:** High
- **Quality:** Medium
- **Stale?:** No — `lib/lightning_web/router.ex:27` still calls bare `plug :put_secure_browser_headers` with no CSP, and `/home/user/lightning/.sobelow-conf` still carries `ignore: ["Config.CSP", "Config.HTTPS"]`.
- **Summary:** Lightning serves no `Content-Security-Policy` header on browser responses; the sobelow security scan is silenced for this finding rather than the policy being fixed. A naive `default-src 'self'` is not viable: LiveView pushes inline styles, and the app loads Monaco, React islands, inline SVG and heroicon backgrounds, so a real policy needs per-request nonce plumbing through the layouts (the approach Stuart and an outside commenter both pointed at, plus `Content-Security-Policy-Report-Only` to find breakage first). A precedent already exists in-repo: `lib/lightning_web/plugs/channel_proxy_plug.ex:39-45` sets a strict `default-src 'none'; sandbox; frame-ancestors 'none'` policy on proxied channel responses because it bypasses the `:browser` pipeline.
- **Questions:** (1) Is a report-only rollout with a collection endpoint acceptable as the first deliverable, or does this need to land enforcing? (2) Do any customer deployments embed Lightning in an iframe or inject scripts (analytics, session replay) that a `frame-ancestors`/`script-src` policy would break?

## #117 — Decide if/how to handle SSL cert authenticity warning for repo connection
- **Verdict:** Already fixed
- **Type:** —
- **Priority:** —
- **Complexity:** —
- **Quality:** —
- **Stale?:** Yes — resolved by commit `e77a926` "Verify the Postgres server certificate on SSL connections".
- **Summary:** The 2022 warning (`Authenticity is not established by certificate path validation` / `Option {verify, verify_peer} and cacertfile/cacerts is missing`) came from the Repo connecting over TLS with no trust store. Config has since moved out of `config/runtime.exs` into `lib/lightning/config/bootstrap.ex:558-578`, which now derives verified TLS options with `:tls_certificate_check.options(db_host)` and exposes deliberate escape hatches (`DISABLE_DB_SSL`, `DISABLE_DB_SSL_CERT_VERIFY`) instead of suppressing the warning. Nothing left to decide.
- **Questions:** None

## #119 — Get buildx with linux/amd64 platform working on M1s
- **Verdict:** New
- **Type:** Bug
- **Priority:** P4
- **Complexity:** Medium
- **Quality:** Medium
- **Stale?:** Partly — the specific 2022 failure (qemu `signal 11` on `mix local.hex` under amd64 emulation, Elixir 1.13/Debian bullseye) almost certainly no longer reproduces; the Dockerfile now parameterises `BUILDER_IMAGE`/`RUNNER_IMAGE`, and no CI workflow does a multi-platform buildx build.
- **Summary:** Cross-building the production image for `linux/amd64` on Apple Silicon segfaulted inside emulated Erlang. Taylor re-opened the question in Sept 2025 wanting local Docker builds to work so the Docker setup can be promoted more widely; Frank's reply pointed only at the README's separate Apple Silicon notes (`README.md:477-505`), which cover a different `ssl_app` crash under `docker compose up` and the `mix compile.rambo` missing-binary problem, not the cross-arch buildx path. The actionable work is to re-verify on current toolchain and, if it now works, document it or add a multi-arch build; if it still fails, capture the current error.
- **Questions:** (1) Is the goal cross-building amd64 images from an M-series Mac, or just a working native arm64 local build? (2) Should CI publish multi-arch images so contributors never need to cross-build?

## #123 — Consider moving Sentry out of lightning
- **Verdict:** New
- **Type:** Improvement
- **Priority:** P4
- **Complexity:** Medium
- **Quality:** Medium
- **Stale?:** Mostly — the "starts processes" half is already addressed, and OpenFn has since built more on Sentry, so this reads more like a close-without-change candidate.
- **Summary:** The ask was that a self-hoster with no error-monitoring plans shouldn't see or run Sentry. `lib/lightning/application.ex:19-29` now attaches the `Sentry.LoggerHandler` only when a DSN is configured, so no Sentry machinery starts by default; what remains is the compiled-in dependency (`mix.exs:157`, `{:sentry, "~> 13.2.0"}`) and its config. Removing it entirely would mean extracting error reporting behind a pluggable behaviour, and Sentry has since become load-bearing for OpenFn's own operations (see #4780, where a Sentry-path crash disabled AI-assistant error recovery).
- **Questions:** (1) Has any self-hoster actually complained about the bundled Sentry dependency, or is this purely a purity concern? (2) Given OpenFn's own reliance on Sentry, is the intended outcome extraction behind an adapter, or closing this as accepted?

## #152 — Documentation for the API
- **Verdict:** New
- **Type:** Improvement
- **Priority:** P3
- **Complexity:** Medium
- **Quality:** Low
- **Stale?:** Yes — written for the single 2022 endpoint set; the API has since grown to ~10 controllers, so the original scope no longer describes the work.
- **Summary:** A one-line request to document the API added in #137. Today `lib/lightning_web/router.ex:74-123` exposes a much larger bearer-token surface — projects, workflows, jobs, work orders, runs, credentials, log lines, provisioning (including `GET /api/provision/yaml`), user registration, plus a separate cookie-authenticated AI-assistant endpoint and the `/collections` KV API. There is no OpenAPI/Swagger spec anywhere in the repo and no `open_api_spex`-style dependency, so any docs are hand-written and live outside this repo (openfn/docs). The real decision is whether to generate a spec from the router or keep prose docs external.
- **Questions:** (1) Should the deliverable be a generated OpenAPI spec served by Lightning, or prose in the openfn/docs site? (2) Which endpoints are considered public/stable versus internal (provisioning, AI assistant, collections)?

## #158 — Render adaptor functions in a picklist, display labelled text inputs for each argument
- **Verdict:** New
- **Type:** Feature
- **Priority:** P4
- **Complexity:** High
- **Quality:** Medium
- **Stale?:** Yes — this is a 2022 no-code job-builder concept that the product moved away from; the job editor is now a Monaco code editor with adaptor docs, autocomplete and the AI assistant.
- **Summary:** The proposal was a form-based job builder: introspect an adaptor package for executable operations (functions returning `state => Promise`), render them in a picklist, and generate labelled inputs per argument, degrading to a free-text code box for multi-operation jobs. It depended on parallel changes in `language-common` 2.0.0-pre that never shipped in that form. Taylor's own comment notes only the first part (the adaptor picklist itself) was done and pushed the visual single-operation interface back to the backlog. The adaptor picker has since been rebuilt several times (#3717, #3831, #3904, #2720) with no argument-form component, so the remaining scope here is genuinely net-new and needs a product decision before any engineering.
- **Questions:** (1) Is a form-based no-code job builder still on the roadmap, or should this be closed in favour of the code editor plus AI assistance? (2) Where would the per-argument metadata come from now — adaptor JSON schemas, TypeScript types, or the docs bundle?

## #160 — Add interface to set default "initial state" for a job
- **Verdict:** New
- **Type:** Feature
- **Priority:** P4
- **Complexity:** Medium
- **Quality:** Medium
- **Stale?:** Partly — the stated blocker ("run job with arbitrary dataclip", #321/#322) is long since closed, but the model the issue describes no longer exists.
- **Summary:** The request is a persisted, user-configured default `state` for a job — built by picking dataclips and assigning them to keys — used whenever the job runs without an explicit input, particularly on a first run. The issue's mechanics are obsolete: `assemble_state` no longer exists anywhere in the codebase, there are no "global dataclips", and jobs now live inside workflow DAGs rather than owning their own triggers. What exists today is per-run selection in the manual-run UI (`lib/lightning_web/live/workflow_live/new_manual_run.ex`, `search_selectable_dataclips`) and cron workflows reusing the last run's dataclip via `Invocation.list_dataclips_for_job_with_cron_state`. Note the caveat in the original issue still applies: `data` and `configuration` keys get overwritten at run assembly.
- **Questions:** (1) Should the default attach to the workflow/trigger rather than the individual job, given the current DAG model? (2) Is the real need "seed a first run" (a onboarding/testing concern) or "a permanent default input" (a runtime-semantics change)?

## #201 — Choose between `select_field` and `select`; document and implement across app
- **Verdict:** New
- **Type:** Improvement
- **Priority:** P4
- **Complexity:** Low
- **Quality:** Medium
- **Stale?:** No, but the answer has changed: both functions now appear to be dead code, so the choice may be "delete both".
- **Summary:** Both duplicate select components still sit in `lib/lightning_web/live/components/form.ex` — `select_field/1` at line 418 (wrapping `PhoenixHTMLHelpers.Form.select`) and `select/1` at line 444 (a raw `<select>` with an inner-block slot). Neither has `@doc`. Grepping `lib`, `assets` and `test` for `select_field`, `Form.select` and `<.select` finds no callers of either — the app has migrated to `core_components.ex` / `new_inputs.ex` for form inputs. Taylor's Apr 2025 comment reclassified this from product to tech-debt and noted Stuart may want to keep both, but the usage evidence suggests straight removal rather than consolidation.
- **Questions:** (1) Confirm neither component is used by anything outside `lib`/`test` (e.g. a downstream or extension module) before deleting. (2) Is `core_components`/`new_inputs` the sanctioned home for selects going forward?

## #220 — Credential types list should be pre-populated (caching?)
- **Verdict:** Already tracked
- **Type:** —
- **Priority:** —
- **Complexity:** —
- **Quality:** —
- **Stale?:** No — still a live problem, but it is now a child of active work.
- **Summary:** GitHub already records this as a sub-issue of #4771 "Update adaptors on the fly", with open PR #4801 configured to close it (earlier attempt PR #4473 was closed). Joseph's 2024 comment restates the core coupling: the credential-type list and adaptor schemas are baked into the built Lightning image, so a newly released adaptor's credential is unusable until Lightning itself is rebuilt/released. Triage should roll into #4771 rather than scoring this separately.
- **Questions:** None

## #251 — Rollback to a previous version
- **Verdict:** Already tracked
- **Type:** —
- **Priority:** —
- **Complexity:** —
- **Quality:** —
- **Stale?:** No — the need persists and is covered by newer, better-scoped work.
- **Summary:** Superseded by open issue #4864 "Restore from a version" (Jun 2026), which sits on infrastructure that did not exist in 2022: `Lightning.Workflows.Snapshot`, `Lightning.Workflows.WorkflowVersion` / `Lightning.WorkflowVersions`, sandboxes, and `lock_version` optimistic locking. Related open issues #4534 (history shows the wrong snapshot) and #4535 (stuck version after sandbox merge) indicate the version-history surface is under active repair. This 2022 issue is labelled "needs detail" and carries no acceptance criteria; treat it as a +1 on #4864.
- **Questions:** None

# Issue triage — openfn/lightning batch 02

## #259 — Unclear error message when credential ownership transfer is blocked?
- **Verdict:** Already fixed
- **Type:** Bug
- **Priority:** —
- **Complexity:** —
- **Quality:** —
- **Stale?:** Yes — the 2022 transfer UI it describes no longer exists.
- **Summary:** The complaint was that ownership-transfer validation used stale state: after removing the offending project inside the same form session, the "Invalid owner" error persisted. Credential transfer has since been rebuilt as a standalone, token-confirmed flow in `lib/lightning_web/live/credential_live/transfer_credential_modal.ex`, decoupled from the project-sharing form. Validation now runs per keystroke against the DB via `validate_project_access/2` and `projects_blocking_credential_transfer/2` in `lib/lightning/credentials.ex:1755-1795`, and the message names the specific blocking projects ("User doesn't have access to these projects: ..."), with modal copy stating the requirement up front. There is no shared changeset for the stale-state scenario to arise in.
- **Questions:** None

## #262 — Broaden access for project admin role
- **Verdict:** Already fixed
- **Type:** Improvement
- **Priority:** —
- **Complexity:** —
- **Quality:** —
- **Stale?:** Yes — the role model was rewritten since 2022.
- **Summary:** Asked that project admins be able to reach admin settings, audit credentials, add users to a project, and create users. `lib/lightning/policies/project_users.ex` now grants `:admin` the `@admin_actions` set including `:add_project_user`, `:remove_project_user`, `:edit_project`, `:edit_data_retention`, `:edit_run_settings`, `:write_webhook_auth_method` and `:write_github_connection`, and project settings gates its member-management UI on those checks. The two remaining asks — the instance admin settings page and creating brand-new user accounts — are deliberately superuser-scoped (`Lightning.Policies.Users`), not a gap in the project-admin role.
- **Questions:** None

## #290 — Standard patterns for LiveView and changesets (incl embeds)
- **Verdict:** Not an issue
- **Type:** —
- **Priority:** —
- **Complexity:** —
- **Quality:** —
- **Stale?:** Yes — an internal alignment discussion for a 2022 team-onboarding meeting.
- **Summary:** A team-conventions discussion (changeset function naming, virtual-field validation, embed changesets) intended to seed a meeting when new engineers joined, with no defined deliverable or acceptance criteria. Any convention decisions from it belong in `CLAUDE.md`/`.claude/guidelines`, not a code ticket. No actionable work item.
- **Questions:** None

## #299 — OIDC multiple providers user interface
- **Verdict:** Already tracked
- **Type:** Feature
- **Priority:** —
- **Complexity:** —
- **Quality:** —
- **Stale?:** Yes — product direction has moved away from UI-configured providers.
- **Summary:** Asked for a superuser UI to configure multiple acceptable OIDC providers. Today `Lightning.AuthProviders` still stores a single config row (`get_existing/0`, `AuthConfig`, `AuthConfigForm`), so multi-provider support is genuinely unbuilt — but the direction reversed: #4904 ("Configure the external OIDC auth provider via env vars") tracks moving provider config out of the UI to align with the GitHub/Google SSO config style, and per-provider sign-in is covered by #4693/#4721 under the reopened SSO epic #4621. This ticket's UI premise conflicts with that work.
- **Questions:** None

## #300 — OIDC
- **Verdict:** Not an issue
- **Type:** —
- **Priority:** —
- **Complexity:** —
- **Quality:** —
- **Stale?:** Yes — empty 2022 epic container.
- **Summary:** An `Epic`-labelled placeholder with an empty body and no linked children; it exists only to group the 2022 OIDC tickets (#299, #301, #308). The live successor is the "Full SSO Experience" epic #4621 (reopened after the SSO implementation was reverted in `ed944da`, "Revert SSO Epic (#5032)"), with #4693/#4695/#4721/#4904 as its children. Nothing actionable is described here.
- **Questions:** None

## #301 — OIDC account creation
- **Verdict:** Already tracked
- **Type:** Feature
- **Priority:** —
- **Complexity:** —
- **Quality:** —
- **Stale?:** Partly — SSO sign-up was built, then reverted pending security review.
- **Summary:** Asked for self-service account creation via OIDC (passwordless) restricted to an allow-list of email domains. SSO sign-up with a confirmation step, email-collision handling and `AccountHook` integration was implemented in PR #4751 and then reverted wholesale in `ed944da` (migrations dropped, `user_identities` removed, `users.hashed_password` back to NOT NULL) so it could get a security review; epic #4621 and #4693/#4695 are reopened and own this. The domain allow-list piece has no implementation in the tree (no `allowed_domains` config anywhere) and is not visibly captured in the SSO children.
- **Questions:** Should the domain allow-list for self-service SSO sign-up be split out as its own child of #4621, or is it out of scope now?

## #308 — Application fails to start when external auth provider is unavailable
- **Verdict:** Already fixed
- **Type:** Bug
- **Priority:** —
- **Complexity:** —
- **Quality:** —
- **Stale?:** Yes — the exact crash path has been closed in code.
- **Summary:** Boot crashed because `CacheWarmer.execute/1` passed a `{:error, %HTTPoison.Error{}}` tuple into `Handler.new/2`, where `Map.from_struct/1` raised a `FunctionClauseError`, taking down Cachex and with it the whole supervision tree. `Handler.from_model/1` in `lib/lightning/auth_providers/handler.ex` now pattern-matches `WellKnown.fetch/1` and returns `{:error, reason}` instead of threading the tuple onward (with a comment naming this scenario), and `CacheWarmer.execute/1` wraps the whole thing in a `with` that falls through to `:ignore`. An unreachable or misconfigured discovery URL now degrades to a cache miss rather than a failed boot.
- **Questions:** None

## #312 — Assign a map of global constants to a job
- **Verdict:** New
- **Type:** Feature
- **Priority:** P4
- **Complexity:** High
- **Quality:** Low
- **Stale?:** Likely — Collections now covers much of the underlying need.
- **Summary:** Requests named "globals" selectable per job and merged into initial state at assembly time. Nothing named `globals` exists: the only nearby concept is `Dataclip` `source_type: :global` (`lib/lightning/invocation/dataclip.ex`), which is a whole-body input rather than a composable named constant, and job state assembly moved to the ws-worker, so there is no `assemble_state` in this repo to hook into. The comment thread leaves the hard questions open — separate table vs dataclips, whether globals resolve at retry time (Taylor: yes, like credential values), and whether globals/`configuration` are stripped from persisted output state. Since 2022 Collections (`lib/lightning/collections/`) has shipped as a project-scoped KV store that job code reads at runtime, which likely satisfies the original motivation without a state-assembly change.
- **Questions:** Does Collections already cover this need well enough to close it? If not, must globals be resolved at run time (retry picks up new values) or frozen into the run's input snapshot?

## #318 — Set character limit for workflow names
- **Verdict:** Already fixed
- **Type:** Improvement
- **Priority:** —
- **Complexity:** —
- **Quality:** —
- **Stale?:** Yes — the requested 25-char cap contradicts later product decisions.
- **Summary:** Filed against a 2023 dashboard where a long workflow name broke the layout; the ask was a hard 25-character limit. The display problem was instead solved presentationally — the dashboard row truncates with CSS (`lib/lightning_web/live/workflow_live/dashboard_components.ex:320`) and full names show in a tooltip (#2894, closed). Product direction then reversed: #2092 ("Don't truncate workflow names on dashboard and canvas") is open, and #3792 ("Remove or Adjust Character Limit for Step Names") was closed in favour of loosening limits. `Workflow.validate/1` still applies no `validate_length` on `:name` (only required + per-project uniqueness), which is now the intended state.
- **Questions:** None

## #325 — Build service to pull credential schemas from npm/github
- **Verdict:** Already tracked
- **Type:** Feature
- **Priority:** —
- **Complexity:** —
- **Quality:** —
- **Stale?:** No — active work, but owned elsewhere.
- **Summary:** This is a sub-issue of epic #4771 ("Update adaptors on the fly") and is in flight: PR #4473 ("Allow on-the-fly updates to adaptors, schemas, and icons") was closed and PR #4801 is open against it, with the April 2026 comments disputing only whether review feedback was already addressed. It is also a subtask by nature — pulling credential schemas from npm/GitHub can't land independently of the adaptor-registry refresh mechanism in the parent epic. The one open design question the body raises, where non-adaptor credential schemas should live versus adaptor-owned ones, should be resolved in #4771/#4801 rather than here.
- **Questions:** None

# Triage batch 03 — openfn/lightning (#365, 397, 457, 470, 475, 492, 496, 513, 518, 524)

Repo state checked against local checkout at HEAD (2026-09-03). Note: local git history is shallow (111 commits), so `git log --grep` was not usable for 2022-2024 fixes; verdicts are based on current code state plus GitHub issue search.

## #365 — Log access control events
- **Verdict:** New
- **Type:** Feature
- **Priority:** P3
- **Complexity:** Medium
- **Quality:** Low
- **Stale?:** No — arguably more relevant now, given recent authz-hardening work and the new channel/collaborative-editor surfaces.
- **Summary:** Lightning has a general auditing framework (`lib/lightning/auditing/audit.ex`) with per-context audit modules for credentials, OAuth clients, projects, workflows, webhook auth methods, dataclips, channels, version control and work-order export. Nothing audits authentication or authorization outcomes: `lib/lightning_web/controllers/user_session_controller.ex` and `user_auth.ex` emit no Logger or audit entry, and the rejection paths in `lib/lightning_web/plugs/api_auth.ex`, `webhook_auth.ex`, `metrics_auth.ex` and `channel_proxy_plug.ex` just return 401 without recording the attempt. Policy denials in `lib/lightning/policies/` are likewise silent. Related but distinct: #1478 (ATNA node-auth audit) and #4677 (project/sandbox/credential lifecycle audit trail).
- **Questions:** (1) Should these land in the existing `audit_events` table (queryable/exportable per project) or only as structured Logger output for external SIEM ingestion? (2) Which events are in scope — failed logins and 401s only, or also every policy denial including LiveView `on_mount` and channel joins?

## #397 — Get superusers to set up a project on account creation
- **Verdict:** Already fixed
- **Type:** —
- **Priority:** —
- **Complexity:** —
- **Quality:** —
- **Stale?:** Yes — the premise no longer holds.
- **Summary:** The "contact your administrator" empty state described in the issue no longer exists anywhere in the codebase. Ordinary users, not just superusers, can now create projects from the dashboard: `lib/lightning_web/live/dashboard_live/project_creation_modal.ex` plus a "Create project" button and an empty state ("No projects found. / Create a new one.") in `lib/lightning_web/live/dashboard_live/user_projects_section.ex:62-81`, alongside a welcome banner in `dashboard_live/components.ex`. There is also an `INIT_PROJECT_FOR_NEW_USER` bootstrap option (`lib/lightning/config/bootstrap.ex:355`) that auto-provisions a project on registration. Superseded by #1700 and #1927.
- **Questions:** None

## #457 — Ability to skip downstream jobs when invoking a manual run
- **Verdict:** New
- **Type:** Feature
- **Priority:** P3
- **Complexity:** High
- **Quality:** Low
- **Stale?:** No — still a live developer-workflow gap in the job inspector.
- **Summary:** A manual run is built by `Lightning.WorkOrders.create_for(%Manual{})` (`lib/lightning/work_orders.ex:123`), which creates a run starting at the selected job. Lightning does not walk the DAG itself; the external ws-worker follows the workflow's edges and executes downstream steps, so suppressing them cannot be done in Lightning alone. The existing per-run behaviour channel is `Lightning.Runs.RunOptions` (`save_dataclips`, `run_timeout_ms`, `run_memory_limit_mb`, `enable_job_logs`), serialized to the worker over the run channel; it has no notion of limiting traversal. Any implementation therefore spans the run-options schema, the worker protocol, and the manual-run UI in the collaborative editor.
- **Questions:** (1) Is the desired scope "run exactly this one step" or "run this step and stop after N"? (2) Does ws-worker already accept, or is it willing to accept, a traversal-limiting run option?

## #470 — Integrate intro.js tutorial
- **Verdict:** New
- **Type:** Feature
- **Priority:** P4
- **Complexity:** Medium
- **Quality:** Low
- **Stale?:** Yes — the specific approach is obsolete.
- **Summary:** Nothing in the repo implements a tour: `intro.js` is absent from `assets/package.json` and there is no onboarding/tutorial/walkthrough code in `lib/` or `assets/js/`. Onboarding has since been reworked by other means, and the closest work items are closed: #2523 (User onboarding enhancements, 2024) and #4868 (AI-First Starting UX landing screen, 2026). A DOM-anchored step-by-step tour is also a poor fit for the current UI, which is mid-migration to the React collaborative editor (`assets/js/collaborative-editor/`), so the selectors and screens the 2022 script describes largely no longer exist.
- **Questions:** (1) Given the AI-first starting UX shipped in #4868, is a scripted tour still wanted at all, or should this be closed in favour of that path?

## #475 — General performance concerns with large dataclips
- **Verdict:** New
- **Type:** Improvement
- **Priority:** P3
- **Complexity:** Medium
- **Quality:** Medium
- **Stale?:** Partly — the Elixir-side concern described in 2022 is gone; the cost has moved to the browser.
- **Summary:** The original complaint was Elixir-side parsing/formatting when rendering a dataclip. That path no longer exists: dataclip bodies are fetched over HTTP from `/dataclip/body/:id` and rendered by a Monaco-backed viewer (`assets/js/react/components/DataclipViewer.tsx`, `lib/lightning_web/components/viewers.ex`), and log lines stream in chunks (`lib/lightning_web/live/run_live/streaming.ex:98`). What remains is unbounded client work: `DataclipViewer` does `JSON.parse(body)` followed by `JSON.stringify(parsed, null, 2)` over the entire response before handing it to Monaco, with no size cap, truncation, or streaming, so a multi-megabyte dataclip still blocks the main thread. No Benchee profile of this ever landed. Related open reports: #2617, #3553, #3648.
- **Questions:** (1) What dataclip size should be treated as the supported ceiling before the UI truncates or offers download-only? (2) Is truncation acceptable to users, or must the full body always be inspectable in-app?

## #492 — Add endpoint for generating adaptor docs
- **Verdict:** New
- **Type:** Improvement
- **Priority:** P3
- **Complexity:** Medium
- **Quality:** High
- **Stale?:** Partly — the problem persists, but the proposed mechanism is a 2022 CLI design.
- **Summary:** Adaptor docs are still generated entirely in the browser: `assets/js/adaptor-docs/hooks/useDocs.tsx` calls `describePackage()` from `@openfn/describe-package` (pinned `^0.1.3` in `assets/package.json`) and caches results only in a module-level in-memory object, with a TODO acknowledging duplicate in-flight requests. There is no `/docs/:adaptor/:version` route in `lib/lightning_web/router.ex` and no server-side docgen anywhere in `lib/`. The same library is also used by the collaborative editor for type definitions (`assets/js/collaborative-editor/utils/loadDTS.ts`), so a server endpoint would only replace the docs-panel consumer unless DTS loading moves too. The issue's proposed `openfn docgen | tail -n 1` shell-out is tied to `@openfn/cli@0.0.20` and would need re-validation against current CLI behaviour and against clustered deployments (cf. #1996 on adaptor-registry cluster sync).
- **Questions:** (1) Does the current `@openfn/cli` still expose `docgen` with the same disk-cache and concurrency semantics? (2) Should the endpoint's cache be per-node disk (`OPENFN_REPO_DIR`) or shared, given Lightning runs clustered?

## #496 — Refactor namespacing to better fit our current design
- **Verdict:** New
- **Type:** Improvement
- **Priority:** P4
- **Complexity:** High
- **Quality:** High
- **Stale?:** No — confirmed still wanted by the CTO in Jul 2025 and re-planned Oct 2025.
- **Summary:** `Lightning.Invocation` still exists and still owns models that no longer belong to it: `lib/lightning/invocation.ex` plus `lib/lightning/invocation/{query,dataclip,dataclip_audit,step,log_line,run_step}.ex`, while `Lightning.WorkOrders` and `Lightning.Runs` own the rest of the execution lifecycle. The issue carries a detailed refactor plan in the Oct 2025 comment (move `Run`/`Step`/`RunStep`/`LogLine` under `WorkOrders`, extract a `Lightning.Dataclips` context, delete `Invocation`, no DB migrations needed) and explicitly sequences it after the React rewrite. Scope is 51+ call sites across contexts, controllers, LiveViews, workers, factories and fixtures. Note the issue body's secondary ask (rename `WorkOrder` to `Workorder`) is not part of the later plan and appears abandoned.
- **Questions:** (1) Is the React/collaborative-editor rewrite far enough along to unblock this, given the merge-conflict risk called out in the plan? (2) Clean break or a deprecation period with `defdelegate` facades?

## #513 — Convert controller pages to liveview
- **Verdict:** New
- **Type:** Improvement
- **Priority:** P4
- **Complexity:** Medium
- **Quality:** Low
- **Stale?:** Partly — still accurate, but the goal itself is now questionable.
- **Summary:** All five named modules still exist as controllers in `lib/lightning_web/controllers/`: `user_auth.ex`, `user_confirmation_controller.ex`, `user_registration_controller.ex`, `user_reset_password_controller.ex`, `user_session_controller.ex`, with `get`/`post "/users/log_in"` still routed to `UserSessionController` (`lib/lightning_web/router.ex:132-133`). The set has since grown (`user_totp_controller.ex`, `backup_codes_controller.ex`, `oauth_controller.ex`, `oidc_controller.ex`), all of which depend on the same plug-based session handling. Session creation and deletion inherently need a plug conn to write the session cookie, so a literal full conversion is not achievable for `user_session_controller` without a controller hand-off step. Open issue #635 covers the registration page specifically and overlaps this umbrella.
- **Questions:** (1) Is there a concrete user-facing motivation (validation UX, 2FA flow) or is this purely stylistic consistency? (2) Should #513 be narrowed to the pages where LiveView actually helps and #635 kept as the tracked subset?

## #518 — Add property to control edge type
- **Verdict:** New
- **Type:** Improvement
- **Priority:** P4
- **Complexity:** Low
- **Quality:** Low
- **Stale?:** Yes — written against a standalone library API that no longer exists.
- **Summary:** The diagram exposes exactly one edge type: `assets/js/workflow-diagram/edges/index.ts` exports `{ step: Edge }`, and `edges/Edge.tsx` hardcodes `BezierEdge` from `@xyflow/react`. Both edge producers hardcode the type string (`useConnect.ts:15`, `usePlaceholders.ts:50`), so there is no prop or config to select smoothstep/straight/step rendering. The issue was filed in 2022 when `workflow-diagram` was a separate package with a public prop surface; it is now vendored inside Lightning's assets and consumed only by Lightning itself, so "add a property" no longer corresponds to an external consumer. Any real need would be a product decision about how workflow edges should look, not an API request.
- **Questions:** (1) Is there an actual desired edge appearance change, or should this be closed as an artifact of the old standalone-library era?

## #524 — Adaptor docs sometimes pulls down too much data (and so is slow)
- **Verdict:** New
- **Type:** Bug
- **Priority:** P4
- **Complexity:** Low
- **Quality:** High
- **Stale?:** Partly — the described client path is unchanged, but the fix does not live in this repo.
- **Summary:** The reported mechanism is intact: the docs panel still calls `describePackage()` from `@openfn/describe-package` in the browser (`assets/js/adaptor-docs/hooks/useDocs.tsx`), so the over-fetch of `node_modules`-prefixed `.d.ts` files listed in older adaptors' `package.json` `files` arrays still applies to every uncached load. The actual code to change is in openfn/kit's `describe-package` (filter file listings beginning with `node_modules`), not in Lightning; nothing under `lib/` or `assets/js/` performs that listing. Impact is also bounded to pre-monorepo adaptor versions, which are increasingly unlikely to be selected. As the issue itself notes, #492 (server-side docgen with a disk cache) would largely absorb the symptom.
- **Questions:** (1) Should this be moved to openfn/kit and closed here, or kept as a Lightning-visible tracking issue behind #492? (2) Do any currently offered adaptor versions still exhibit the bad `files` manifest?

# Triage batch 04 — openfn/lightning

## #589 — Add feature to remove run logs from emails
- **Verdict:** New
- **Type:** Feature
- **Priority:** P2
- **Complexity:** Medium
- **Quality:** Medium
- **Stale?:** No — the behaviour it guards against still exists verbatim in the current code.
- **Summary:** Failure alert emails still embed the full run log body: `lib/lightning/pipeline/failure_alerter.ex:33` passes `run.log_lines` as `run_logs`, and `lib/lightning_web/templates/failure_notifier/failure_alert.html.heex:23` renders every `log.message` inside a `<pre>` block. There is no project- or instance-level switch to suppress this; `lib/lightning/config.ex` exposes only sender name and admin email for mail. Log lines are credential-scrubbed but can still carry record-level payload data, so this is a data-exposure concern for health/survey deployments where email is out of the security boundary. A setting would have to live on the project (or project_user notification prefs) and be read at alert-build time, not just at render time.
- **Questions:** (1) Should the toggle be per-project, per-instance, or per-recipient? (2) When logs are suppressed, should the email still deep-link to the run, or be suppressed entirely?

## #593 — Allow user to limit search for last run per work order
- **Verdict:** New
- **Type:** Improvement
- **Priority:** P3
- **Complexity:** Medium
- **Quality:** Medium
- **Stale?:** No — still unimplemented, but the vocabulary has shifted (2023 "run" ≈ today's step; a work order now has Runs containing Steps).
- **Summary:** `Lightning.WorkOrders.SearchParams` (lib/lightning/workorders/search_params.ex) has no "last run only" flag; its fields are status, search_fields (`:id, :body, :log, :dataclip_name`), search_term, workflow/workorder ids, date ranges and sort. The log/body search in `lib/lightning/invocation.ex` (`filter_by_body_or_log_or_id/3`, `build_body_and_log_union_query/3` around lines 716-745) unions dataclip-body and log-line matches across all steps of a work order, so a resolved error from an earlier run still matches. Scoping to the latest run requires narrowing that union to the most recent Run per WorkOrder before the tsquery filter, plus a new UI filter and URL/param round-trip, and the retry path (`search_workorders_for_retry/2`) and history export share the same params struct.
- **Questions:** (1) Does "last run" mean the newest Run, or the newest Step per job? (2) Should the flag also apply to the retry-from-search and history-export paths that reuse SearchParams?

## #597 — Hide noisy schema installation log from tests
- **Verdict:** Already fixed
- **Type:** —
- **Priority:** —
- **Complexity:** —
- **Quality:** —
- **Stale?:** Yes — the noise is captured today.
- **Summary:** The message comes from `Mix.shell().info(...)` at `lib/mix/tasks/install_schemas.ex:70`, i.e. stdout rather than Logger. The only test that invokes the task, `test/lightning/install_schemas_test.exs`, wraps `InstallSchemas.run([])` in `capture_io/1` (with `with_log/1` around it) and asserts on the captured output, so nothing leaks into the suite output while the app still prints it in real runs — exactly what the issue asked for.
- **Questions:** None

## #598 — Fix (or silence?) occasional postgrex connection error in tests
- **Verdict:** New
- **Type:** Bug
- **Priority:** P4
- **Complexity:** Medium
- **Quality:** Low
- **Stale?:** Yes, largely — the traceback is against ecto 3.9 / ecto_sql 3.9 / postgrex 0.16.5; the repo now runs ecto 3.13.2, ecto_sql 3.13.2, postgrex 0.22.4, and the reported frames no longer correspond to current library code.
- **Summary:** The report is red-but-harmless output from Ecto's SQL sandbox: a `Task`-spawned preload (`Ecto.Repo.Preloader.fetch_query/8` under `Task.Supervised`) outliving its owner process, so the sandbox connection is torn down mid-query. `config/test.exs:120` sets `config :logger, level: :warning`, which does not suppress `:error`-level DBConnection disconnect messages, so any surviving instance would still print. There is no current evidence in the repo that this recurs, and no reproduction beyond the pasted log; confirming it would mean running the suite and watching for the message rather than reading code.
- **Questions:** (1) Has anyone seen this message on a recent suite run? (2) If it still occurs, is silencing via a Logger filter acceptable, or should the offending async preload be found and fixed?

## #635 — Convert registration page from controller page to liveview
- **Verdict:** New
- **Type:** Improvement
- **Priority:** P4
- **Complexity:** Medium
- **Quality:** Medium
- **Stale?:** Partly — still true structurally, but lower value now that self-signup is off by default.
- **Summary:** Registration is still controller-rendered: `lib/lightning_web/controllers/user_registration_controller.ex` with `lib/lightning_web/controllers/user_registration_html/new.html.heex`, routed at `lib/lightning_web/router.ex:129-130` behind `:redirect_if_user_is_authenticated`, while a separate API route (`router.ex:77`) handles programmatic signup. The form posts to `Routes.user_registration_path(@conn, :create)` and uses `required={true}` inputs with no `phx-change`, so the "grey out Register until fields are filled" acceptance criterion has no live-validation path today. The route is additionally gated on the `:allow_signup` config (`ALLOW_SIGNUP`, default false per `lib/lightning/config/bootstrap.ex:351`), so most instances never show this page. A conversion must preserve the post-registration session establishment currently done in the controller.
- **Questions:** (1) Given signup is disabled by default, is a LiveView conversion still worth it versus leaving it as-is? (2) Should the LiveView also cover the confirmation/terms flow, or only the registration form?

## #643 — Enable caching
- **Verdict:** New
- **Type:** Improvement
- **Priority:** P4
- **Complexity:** Low
- **Quality:** Medium
- **Stale?:** Partly — the caching machinery exists but is still not env-configurable; the original slowness is reduced because the registry now populates at boot.
- **Summary:** `Lightning.AdaptorRegistry` already supports the requested behaviour: `handle_continue/2` (lib/lightning/adaptor_registry.ex ~line 100-125) honours a `:use_cache` option that is either `true` (writes to `System.tmp_dir!()/lightning/adaptor_registry_cache.json`) or a path string. What is missing is the wiring the issue asks for: `lib/lightning/application.ex:43-44` passes `Application.get_env(:lightning, Lightning.AdaptorRegistry, [])`, and the only place that key is configured is `config/test.exs:101` — nothing in `config/runtime.exs` or `lib/lightning/config/bootstrap.ex` maps an environment variable onto it, so dev/prod always take the `fetch()` branch (`start_link/1`'s `use_cache: true` default is never used because the supervisor always passes explicit opts). Cache location is likewise undocumented in `.env.example`.
- **Questions:** (1) What env var name and default (off, per the original AC) do you want? (2) Should the same var carry the cache path, or a second var for location?

## #644 — Refresh cache on application start up
- **Verdict:** New
- **Type:** Improvement
- **Priority:** P4
- **Complexity:** Low
- **Quality:** Medium
- **Stale?:** No, but it depends on #643 — it is the follow-up that issue names.
- **Summary:** Current cache logic is read-through-once and never refreshed: `read_from_cache(cache_path) || write_to_cache(cache_path, fetch())` in `Lightning.AdaptorRegistry.handle_continue/2` writes the file only when no cache exists, so a cached instance keeps a stale adaptor list indefinitely across restarts. The issue asks for a refresh attempt at boot that degrades to a warning when the network is unavailable (offline installs), plus docs for overriding the cache path — neither the warning path nor the docs exist today, and `write_to_cache/2` only emits a `Logger.debug`. Note the refresh has to stay non-blocking or the registry GenServer delays boot.
- **Questions:** (1) Should boot serve the stale cache immediately and refresh in the background, or block until the fetch resolves/fails? (2) Is this worth doing before #643 lands an env var to enable caching at all?

## #693 — Spike: Find better solution for Process.sleep() for FailureAlert tests
- **Verdict:** New
- **Type:** Improvement
- **Priority:** P4
- **Complexity:** Medium
- **Quality:** Medium
- **Stale?:** No — the sleeps are still in the suite and have grown.
- **Summary:** `test/lightning/failure_alert_test.exs` still sleeps at lines 141 and 189, now 250ms each rather than the 100ms described, and line 140 carries an explicit `# TODO: remove this with .../issues/693`. The pattern is: call `FailureAlerter.alert_on_failure/1` several times, `Oban.drain_queue(Lightning.Oban, queue: :workflow_failures)`, sleep, then `assert_receive {:email, ...}`. The race is between Oban's drain returning and the rate-limiter/mail delivery side effects settling, so the fix is about getting a deterministic signal (rate-limiter state, telemetry, or the Swoosh test adapter) rather than a timer. Stuart's follow-up comment notes the test flaked again even with the sleep in place, so the sleep may be masking rather than fixing.
- **Questions:** (1) Is the flake in the Hammer/rate-limit bucket state or in mail delivery ordering? (2) Is a telemetry-based sync point acceptable, or should the alerter expose a synchronous test seam?

## #703 — Better performance profiling/stress-testing
- **Verdict:** Not an issue
- **Type:** —
- **Priority:** —
- **Complexity:** —
- **Quality:** —
- **Stale?:** Yes — the k6 setup the thread was built around is no longer in the repo (no benchmarking/k6 files anywhere in the tree, no matching git history), so the premise is gone.
- **Summary:** Open-ended brainstorm ("thoughts on how we could make this better?", labelled `question`) listing test categories and a blog link, with no defined scope, owner, or done-state. Nothing here is actionable as written; if performance testing is wanted again it needs a fresh issue stating what is measured and against what thresholds.
- **Questions:** None

## #715 — Improve API error codes
- **Verdict:** Already fixed
- **Type:** —
- **Priority:** —
- **Complexity:** —
- **Quality:** —
- **Stale?:** Yes — the 500-on-bad-token behaviour is gone.
- **Summary:** The JSON API pipeline now pipes through `:authenticate_bearer` then `:require_authenticated_api_resource` (`lib/lightning_web/router.ex:79-82`). `authenticate_bearer/2` (lib/lightning_web/controllers/user_auth.ex:241) assigns nothing on a missing or invalid token, and `require_authenticated_api_resource/2` (same file, line 357) then calls `render_unauthorized/1`, which halts with a 401 and the `ErrorView` `401` template — covering both the "no token" and "invalid token" cases from the issue and Taylor's comment. `LightningWeb.FallbackController` maps `:bad_request` to 400, `:not_found` to 404, `:forbidden` to 403 and changeset errors to 422, so the requested code set is in place.
- **Questions:** None

# Triage batch 05 — openfn/lightning

## #720 — Use html templates for emailing
- **Verdict:** New
- **Type:** Improvement
- **Priority:** P4
- **Complexity:** Medium
- **Quality:** Low
- **Stale?:** No — every outbound email is still plain text in 2026.
- **Summary:** All notification mail is built in `lib/lightning/accounts/user_notifier.ex` through a single private `deliver/3` (line 48) that sets only `text_body`; there is no `html_body` anywhere in `lib/` and no email template directory. Roughly 20 messages (confirmation, password reset, project invites, scheduled deletion, credential transfer, digest) are heredoc strings with bare URLs, which is what the reporter means by "users have to copy-paste from their emails" — some clients do not autolink. Related closed issue #732 (broken links in failure alert email) was a symptom of the same plain-text pipeline. Work would touch the shared `deliver/3` seam plus Swoosh/Mailer config, so it is one refactor point but ~20 message bodies.
- **Questions:** Should multipart (text + HTML) be required for deliverability, or is HTML-only acceptable? Is there existing OpenFn brand/email design to follow, or does this need design input first?

## #724 — Improve UI for roles and permissions
- **Verdict:** New
- **Type:** Improvement
- **Priority:** P4
- **Complexity:** Medium
- **Quality:** Low
- **Stale?:** Partly — the workflow editor now solves it; LiveView settings pages do not.
- **Summary:** The collaborative editor already implements this pattern: `useWorkflowReadOnly` in `assets/js/collaborative-editor/hooks/useWorkflow.tsx` (~line 985) returns an `isReadOnly` flag plus a specific `tooltipMessage` ("You do not have permission to edit this workflow", deleted, pinned version, unsaved new workflow), surfaced by `components/ReadOnlyWarning.tsx`, `WorkflowDiagram.tsx` and the inspector footers. The gap is the LiveView surfaces: `lib/lightning_web/live/project_live/settings.html.heex` has ~15 controls gated on `@can_edit_project` / `@can_create_project_credential` with only 6 tooltips in the whole file, and permission-explaining tooltips appear in only one other place (`channel_live/index.ex:63`). Related closed work: #3683, #3949, #707, #709. As written the issue has no scope boundary.
- **Questions:** Which surfaces are in scope now that the editor is done — project settings, credentials, run history, collections? Should this become a shared component/helper so disabled + reason is one call site?

## #749 — Clear runs queue for a project
- **Verdict:** Already fixed
- **Type:** —
- **Priority:** —
- **Complexity:** —
- **Quality:** —
- **Stale?:** Yes — delivered by the bulk-cancel work.
- **Summary:** Both asks now exist. Run history (`lib/lightning_web/live/run_live/index.ex`) has an "Enqueued" status filter (line 98) so a project admin can see the pending backlog, and bulk cancel is implemented end to end: `bulk_cancel_modal/1` in `run_live/components.ex:616` offers both "cancel selected" and "cancel all matching" (the current filter), handled at `run_live/index.ex:549` and backed by `Lightning.WorkOrders.cancel_many/2` and `Lightning.Runs.cancel_available_for_work_orders/3`. Tracked and closed as #1622 "Cancel runs individually or in bulk"; #4635 fixed a follow-up. Recommend closing as done.
- **Questions:** None

## #751 — Adaptors should not be installed as latest
- **Verdict:** Already fixed
- **Type:** —
- **Priority:** —
- **Complexity:** —
- **Quality:** —
- **Stale?:** Yes — the run path resolves `@latest` to a concrete version.
- **Summary:** The requested mapping now exists: `Lightning.AdaptorRegistry.resolve_adaptor/1` (`lib/lightning/adaptor_registry.ex:456`) rewrites `name@latest` to `name@<latest_for(name)>`, and the worker payload goes through it in `lib/lightning_web/channels/run_with_options.ex:44`, so a run is never dispatched with a frozen `_latest` alias. Two residues: the registry has no self-refresh timer (no `handle_info`/`send_after` in `adaptor_registry.ex`), which is tracked by #2209 and #1996, and `Lightning.AdaptorService` — now only used by `MetadataService.get_adaptor_path/1` — still maps `"latest"` to `"> 0.0.0"` (`adaptor_service.ex:270`) and installs a `-latest` yarn alias (line 378), overlapping #5059. The strategic rethink lives in #2844.
- **Questions:** None

## #772 — Benchmark data sent between page loads
- **Verdict:** Not an issue
- **Type:** —
- **Priority:** —
- **Complexity:** —
- **Quality:** —
- **Stale?:** Yes
- **Summary:** A one-off measurement spike with no acceptance criteria, no owner and no product change attached; it is also pre-dated by the LiveView-to-React/Y.js rearchitecture, so any 2023 numbers would be meaningless. Nothing to implement.
- **Questions:** None

## #780 — Warn before closing a form with unsaved changes
- **Verdict:** New
- **Type:** Improvement
- **Priority:** P3
- **Complexity:** Medium
- **Quality:** Medium
- **Stale?:** No — reconfirmed April 2025 and again January 2026.
- **Summary:** The problem has narrowed but not gone. The 2023 blocker (no way to intercept LiveView navigation, see the ElixirForum thread in the comments and the abandoned PR #1044) no longer applies: the collaborative editor keeps edits in the Y.Doc, and `assets/js/collaborative-editor/hooks/useUnsavedChanges.ts` already computes a reliable dirty flag by deep-diffing the Y.Doc-backed workflow against the session-context baseline, consumed by `components/Header.tsx:219` for the unsaved indicator. What is missing is any interception: there is no `beforeunload` listener anywhere in `assets/js`, so refresh/back/navigate still leaves without prompting. The Jan 2026 comments scope it to a browser-native alert after PR #4289, with the caveat that browsers do not allow custom wording.
- **Questions:** Is scope now just a `beforeunload` guard on the collaborative editor, or also in-app route changes? Should it prompt at all given Y.Doc edits survive a reload, or only when the doc diverges from the saved snapshot?

## #789 — Handle session token expiry
- **Verdict:** Already fixed
- **Type:** —
- **Priority:** —
- **Complexity:** —
- **Quality:** —
- **Stale?:** Yes — the crashing code path is guarded.
- **Summary:** The Sentry crash was `Lightning.Policies.Users.authorize/3` receiving a nil user when `AuditLive.Index.mount/3` ran with an expired session. `lib/lightning_web/live/audit_live/index.ex` now goes through `on_mount {LightningWeb.Hooks, :ensure_admin}`, and `lib/lightning_web/hooks.ex:32` has a dedicated clause matching `%{assigns: %{current_user: nil}}` that halts and redirects to `/users/log_in` before any policy call. `authorize(:access_admin_space, %User{role: role}, _)` still only matches a `%User{}`, but it is unreachable with nil. The reporter's own conclusion (comment of 2023-04-14) was that the redirect was already correct and only the noise mattered.
- **Questions:** None

## #795 — Provide count of work orders that had failed but have been fixed in the last week
- **Verdict:** New
- **Type:** Feature
- **Priority:** P4
- **Complexity:** Medium
- **Quality:** Medium
- **Stale?:** No — the digest still omits this figure.
- **Summary:** `Lightning.DigestEmailWorker.get_digest_data/3` (`lib/lightning/digest_email_worker.ex:159`) returns only `successful_workorders` and `failed_workorders`, both computed by running the run-history search (`count_workorders/2`) over the digest window; its own docstring still promises a "rerun" count that the map does not contain, and there is no `rerun_workorders` field in the codebase. Delivering the requested line needs a query that identifies work orders whose earlier run in the window failed but whose latest run succeeded, i.e. reasoning across multiple `runs` per work order rather than the terminal work-order state the search filter exposes. Related: closed #3616 broadened which failure states the digest counts; open #2920 wants the same "failed attempt, now green" signal in the history UI.
- **Questions:** Does "fixed in the last week" mean the retry succeeded inside the window regardless of when the original failure happened, or both events inside the window? Should manually cancelled/discarded work orders count as fixed?

## #808 — Add confirmation modal to project deletion (superuser)
- **Verdict:** Already fixed
- **Type:** —
- **Priority:** —
- **Complexity:** —
- **Quality:** —
- **Stale?:** Yes
- **Summary:** `lib/lightning_web/live/components/project_deletion_modal.ex` implements the spec: a modal titled "Delete project" that asks the user to type the project name, validated on change via `Projects.validate_for_deletion/2` into a `name_confirmation` field, the warning text including the grace period from `Lightning.Config.purge_deleted_after_days()`, and a danger-themed submit button with `disabled={!@deletion_changeset.valid?}` — which is the grey-out the 2023 follow-up comment said was missing. The same comment's second point (Enter key only closing the modal) is also addressed, since the input sits inside a `phx-submit="delete"` form so Enter submits and is re-validated server side.
- **Questions:** None

## #815 — Handle final status for parallel runs
- **Verdict:** Already fixed
- **Type:** —
- **Priority:** —
- **Complexity:** —
- **Quality:** —
- **Stale?:** Yes — the data model in the screenshots no longer exists.
- **Summary:** The report predates the v2 execution model. In 2023 a "run" was per job and the parent attempt's status was rolled up in the UI, which is how a work order could read success while a parallel branch failed. Today one `Run` is a whole workflow execution with per-job `Step` records; the worker reports a single exit reason, and `Lightning.WorkOrders.update_state/1` derives work-order state through `Lightning.WorkOrders.Query.state_for/1` (`lib/lightning/workorders/query.ex:45`), which unions all runs on the work order and orders unfinished states deterministically. `Runs.Handlers.CompleteRun` explicitly documents multiple-leaf completion (`final_state` for several leaves), so parallel branches are a first-class case. No open issue tracks the described mismatch; recommend closing and re-filing with a current repro if it still occurs.
- **Questions:** None

# Triage batch 06 — openfn/lightning

## #843 — Workflow Diagram: Keyboard control
- **Verdict:** New
- **Type:** Feature
- **Priority:** P4
- **Complexity:** Medium
- **Quality:** Medium
- **Stale?:** Partly — the diagram was rewritten into the collaborative editor, and #3807 (closed Nov 2025) delivered Ctrl+S / Ctrl+Shift+S / Ctrl+Return / Esc bindings, but node traversal from the keyboard was never built.
- **Summary:** The request is to drive the canvas itself from the keyboard: arrow keys to move selection along parent/child/sibling edges, Enter/Escape to open and close the inspector, `a` to add a child node. In the current code the only diagram-level key handling is the undo/redo listener at `assets/js/collaborative-editor/components/diagram/WorkflowDiagram.tsx:886-907`; selection still flows through mouse events (`handleNodeClick`, `updateSelection`) with no focus model or tab order on nodes. Graph structure needed for parent/sibling traversal already lives in WorkflowStore (jobs, triggers, edges), so the work is mostly focus management, a visible focus ring distinct from selection, and handing focus off between canvas, inspector and Monaco.
- **Questions:** Is keyboard canvas navigation in scope for accessibility commitments, or purely a power-user nicety? Should keyboard selection open the inspector, or select without opening?

## #844 — Notify users when a deletion is cancelled
- **Verdict:** New
- **Type:** Improvement
- **Priority:** P3
- **Complexity:** Low
- **Quality:** Medium
- **Stale?:** No — the gap is still present in current code.
- **Summary:** Scheduling a project deletion disables every trigger in the project (`lib/lightning/projects.ex:1597-1615`, inside `scheduled_project_deletion_changes/2`), but `Projects.cancel_scheduled_deletion/1` (`lib/lightning/projects.ex:1670`) only nulls `scheduled_deletion` — triggers stay disabled and nobody is told. The same asymmetry exists for users (`Lightning.Accounts.cancel_scheduled_deletion/1`, `lib/lightning/accounts.ex:567`). `UserNotifier` has `send_deletion_notification_email/1` but no cancellation counterpart (`lib/lightning/accounts/user_notifier.ex`). Adjacent open work: #4673 (let project owners cancel their own scheduled deletion) would make this path much more user-visible.
- **Questions:** Should cancellation re-enable the triggers automatically, or only notify and let the user re-enable? Does this cover user deletions and credential deletions too, or projects only?

## #849 — Refactor delete user
- **Verdict:** New
- **Type:** Improvement
- **Priority:** P4
- **Complexity:** Low
- **Quality:** Low
- **Stale?:** Mostly — it points at a 2023 PR (#847) as the pattern of record, and both modals have since drifted, so "the pattern" needs re-deriving.
- **Summary:** Asks that the user-deletion flow adopt the project-deletion pattern. Today `LightningWeb.Components.ProjectDeletionModal` validates through a dedicated `Projects.validate_for_deletion/2` changeset (name confirmation) while `LightningWeb.Components.UserDeletionModal` still branches on `delete_now?`, `has_activity_in_projects?` and `Accounts.change_scheduled_deletion/2` with flash-message error handling rather than changeset errors. The divergence is real but cosmetic: both flows work, and the referenced PR predates the current policies layer.
- **Questions:** Is this still worth doing, or should the two modals be unified into one generic scheduled-deletion component instead? Who deletes users today — superusers only?

## #876 — Consider blocking project update via API once its been marked for deletion
- **Verdict:** New
- **Type:** Improvement
- **Priority:** P4
- **Complexity:** Low
- **Quality:** Medium
- **Stale?:** No — no such guard exists in current code.
- **Summary:** A project with `scheduled_deletion` set can still be modified through the provisioning API. `Lightning.Projects.Provisioner` has no reference to `scheduled_deletion` and `Projects.update_project/3` (`lib/lightning/projects.ex:588`) does not check it either, so a CLI `openfn deploy` against a project pending deletion succeeds silently. The router exposes read-only REST project endpoints (`lib/lightning_web/router.ex:87`), so the write path in question is the provisioning controller. Note that scheduling deletion already disables triggers, so a successful deploy leaves the project in a confusing half-live state.
- **Questions:** Should a deploy to a project pending deletion be rejected outright with 403, or implicitly cancel the deletion? Does the same rule apply to workflow/dataclip/run API writes?

## #894 — Improve pattern for conditionally render things based on permissions
- **Verdict:** Not an issue
- **Type:** —
- **Priority:** —
- **Complexity:** —
- **Quality:** Low
- **Stale?:** Yes — body is entirely empty template headings, and the permissions layer has been consolidated since (documented `Permissions.can/4` + `can?/4` interface with atom shortcuts over per-domain policy modules in `lib/lightning/policies/`). Roughly 33 ad-hoc `can_*` assigns remain in LiveViews, but there is no stated problem to act on.
- **Summary:** Title-only issue with no user story, details, or acceptance criteria. Not actionable without a fresh problem statement.
- **Questions:** None

## #896 — UI tweaks on bulk rerun modal
- **Verdict:** New
- **Type:** Improvement
- **Priority:** P4
- **Complexity:** Low
- **Quality:** Low
- **Stale?:** Partly — item 1 is done (struck through, and the `@pages > 1` guards are in place at `lib/lightning_web/live/run_live/components.ex:655,700,788,836`); item 2's reference design is "v1", a product that no longer exists.
- **Summary:** Three cosmetic tweaks to the bulk-rerun confirmation modal on the History page. The remaining actionable item is item 2: the modal still renders a long prose sentence built by `humanize_search_params/2` (`lib/lightning_web/live/run_live/components.ex:777`, helpers at 868-930) which stacks humanized date, workflow, run-date, search-term and status clauses into one unwieldy line. Item 3 (sticky table header transparency letting workflow names show through the "Workflow" heading) cannot be confirmed from source and needs a visual re-check against the current History page.
- **Questions:** Is the v1 modal design still available as a reference, or should a new compact filter summary be designed? Does item 3 still reproduce on the current History page?

## #913 — Export projects as .zip (yaml, state, config)
- **Verdict:** Already fixed
- **Type:** —
- **Priority:** —
- **Complexity:** —
- **Quality:** —
- **Stale?:** Yes — superseded by the in-app GitHub sync feature.
- **Summary:** The user story (bootstrap a git repo for an existing project without hand-assembling files) is now served end-to-end by version control rather than a zip download. `Lightning.VersionControl` pushes `deploy.yml` and `pull.yml` workflow files into the connected repo and writes the per-project config file (`lib/lightning/version_control/version_control.ex:517,568,611`; path built in `lib/lightning/version_control/project_repo_connection.ex:132`), and generates the `OPENFN_<project>_API_KEY` secret name for the GitHub secret rather than embedding a token. The YAML-only export from #249 still exists at `lib/lightning_web/controllers/downloads_controller.ex:10` for portability. No open issue tracks the zip variant separately.
- **Questions:** None

## #934 — `googlehealthcare` credential setup
- **Verdict:** Already fixed
- **Type:** —
- **Priority:** —
- **Complexity:** —
- **Quality:** —
- **Stale?:** Yes.
- **Summary:** The ask was to abstract the Google-specific OAuth module into a generic `OAuth2` module and expose a form for client id, well-known path, etc. That generic path shipped via #1919 ("Add a generic Oauth client", closed) and later refactors (#1796, #2908): there is now an `oauth_clients` schema with configurable authorization/token/revocation/userinfo/introspection endpoints and mandatory/optional scopes (`lib/lightning/credentials/oauth_client.ex:21-33`), a client form and a generic credential form (`lib/lightning_web/live/credential_live/oauth_client_form_component.ex`, `generic_oauth_component.ex`), well-known discovery under `lib/lightning/auth_providers/well_known.ex`, and a shared OAuth HTTP client. Google Healthcare can be configured as a generic OAuth client with no adaptor-specific code.
- **Questions:** None

## #946 — Add a flag to stop sensitive state being logged
- **Verdict:** Already fixed
- **Type:** —
- **Priority:** —
- **Complexity:** —
- **Quality:** —
- **Stale?:** Yes.
- **Summary:** Lightning now carries a per-workflow logging flag end-to-end: `enable_job_logs` on the workflow schema (`lib/lightning/workflows/workflow.ex:45`), surfaced as a toggle in the collaborative editor (`assets/js/collaborative-editor/types/workflow.ts`), carried in `Lightning.Runs.RunOptions` (`lib/lightning/runs/run_options.ex:25`) and translated into the worker's `job_log_level` when the run is claimed (`lib/lightning_web/channels/run_with_options.ex:106`). That covers the issue's core request; the only unbuilt part of the sketched UX is a project-level default that workflows inherit (`Lightning.Projects.Project` has no such field), which would be a small new issue rather than this one.
- **Questions:** None

## #981 — Improve performance of the History page queries
- **Verdict:** Already tracked
- **Type:** —
- **Priority:** —
- **Complexity:** —
- **Quality:** —
- **Stale?:** Yes — the schema this describes no longer exists.
- **Summary:** Both concrete complaints are gone. The varchar casting on `log_lines` and `dataclips` searches has been replaced by tsvector `search_vector` columns with dedicated indexes (`lib/lightning/invocation.ex:756,775`; migrations `20260530091126_add_log_lines_pending_search_index.exs`, `20260530184653_add_dataclips_pending_search_index.exs`), and the `finished_at` join for "last run" was replaced by a denormalized `work_orders.last_activity` column plus index (`lib/lightning/invocation.ex:702-710,1147-1162`, migration `20241004145159_create_work_order_last_activity_index.exs`). The `attempt_runs` table named in the third checkbox was renamed away in `20240129200950_rename_attempts_to_runs.exs`. Remaining index work is tracked in the still-open child #1899; #1898 is done.
- **Questions:** None

# Triage batch 07 — openfn/lightning

## #1000 — Refactor runtime handler and taskworker for dialyzer
- **Verdict:** New
- **Type:** Improvement
- **Priority:** P4
- **Complexity:** Low
- **Quality:** Low
- **Stale?:** Mostly — the "runtime handler" half is moot; only a single dialyzer suppression survives.
- **Summary:** The issue asked to revert a dialyzer-silencing commit and fix the underlying typing problems in the runtime handler and the task worker, conditional on those functions surviving the (then-pending) run/attempt refactor. The referenced commit SHA is no longer resolvable in this repo's history, and no runtime-handler module remains (`Lightning.Pipeline` is gone; only `lib/lightning/runtime/runtime_manager.ex` exists). What does survive is `lib/lightning/task_worker.ex` plus its entry in `.dialyzer_ignore.exs` (`{"lib/lightning/task_worker.ex", :call_with_opaque}`), which comes from wrapping `Task.Supervisor` and passing the supervisor reference around. So the actionable residue is one small suppression on a rarely-touched GenServer used only by `MetadataService`.
- **Questions:** 1) Is clearing the remaining `task_worker.ex` dialyzer ignore worth doing at all, or should this be closed as obsolete? 2) Is `TaskWorker` still expected to survive, given it now serves only adaptor metadata generation?

## #1055 — Adaptor docs: common `http` namespace is wrongly listed
- **Verdict:** New
- **Type:** Bug
- **Priority:** P3
- **Complexity:** Medium
- **Quality:** Medium
- **Stale?:** No — reporter reconfirmed in July 2025 and the rendering code is unchanged.
- **Summary:** The adaptor docs panel flattens every exported operation into one alphabetical list. `assets/js/adaptor-docs/components/DocsPanel.tsx` destructures `pkg.functions` and maps each entry straight to `<Function>`, with no notion of a parent object, so namespaced helpers such as `http.get`/`http.post` in `common` render as bare `get`/`post` and the inserted snippet/examples are wrong. The author's 2025 comment generalises the report: namespaced functions are not rendered properly at all, and namespacing is now widespread across adaptors. The upstream dependency is openfn/kit#363 (what `describePackage` emits); `dateFns` and `axios` re-exports are still absent from the panel. Related but distinct: #3355 (markdown not rendered), #3045, #1758.
- **Questions:** 1) Has openfn/kit#363 landed, i.e. does `describePackage` now emit namespace/parent metadata Lightning can consume? 2) Should namespaced ops be grouped under collapsible headings, or just displayed with fully-qualified names?

## #1081 — Show read-only view to non-admins in Project Settings section
- **Verdict:** Already fixed
- **Type:** —
- **Priority:** —
- **Complexity:** —
- **Quality:** —
- **Stale?:** Yes — the page was rebuilt as a single sectioned LiveView after this was filed.
- **Summary:** All three requests are satisfied by the current `lib/lightning_web/live/project_live/settings.html.heex`. Project description is now a `.input type="textarea"` with `disabled={!@can_edit_project}`, matching project name and env. The security/MFA section and the "Sync to GitHub" section both render for non-admins via the `layout_components.ex` section wrapper, which takes `can_perform_action` plus a `permissions_message` and shows a read-only explanatory banner (`permissions_message/1`, `layout_components.ex:588`) instead of an empty page; the MFA toggle gets `cursor-not-allowed opacity-50` plus a "You do not have permission to perform this action" tooltip, and GitHub install controls are gated on `can_install_github` / `can_initiate_github_sync`. Nick's comment suggesting an "access needed" screen instead is effectively what shipped. Broader role/permission UX remains tracked in #724.
- **Questions:** None

## #1138 — Add an "End of automation" node to the workflow
- **Verdict:** New
- **Type:** Feature
- **Priority:** P4
- **Complexity:** Medium
- **Quality:** Medium
- **Stale?:** Partly — never built, and the design predates the collaborative editor, so the Figma reference is likely obsolete.
- **Summary:** Purely cosmetic terminal node marking where a workflow's graph ends. Nothing like it exists today: `assets/js/workflow-diagram/nodes/index.ts` registers only `Job`, `PlaceholderJob` and `Trigger`, and the collaborative editor reuses that same `nodeTypes` map through `components/WorkflowPreview.tsx`. The issue itself defers the key decision: represent the end node in the persisted workflow (Y.Doc/JSON payload and YAML export) versus deriving leaf nodes client-side from the edge list. Since workflows are DAGs with potentially several leaves, "the end" is plural, and the workflow now has a snapshot/version-hash and YAML round-trip surface that a persisted synthetic node would touch.
- **Questions:** 1) Is the 2023 Figma still the intended design, or should this be re-specified against the collaborative editor? 2) One end node per leaf job, or a single shared terminal node all leaves point at?

## #1207 — Allow user to have multiple triggers on a workflow
- **Verdict:** New
- **Type:** Feature
- **Priority:** P3
- **Complexity:** High
- **Quality:** Low
- **Stale?:** No — still a real product gap, and it survived the 2026 "Better trigger flow" epic (#4787) untouched.
- **Summary:** Users want e.g. a cron trigger and a webhook trigger driving the same DAG. The schema already permits it (`has_many :triggers` in `lib/lightning/workflows/workflow.ex:52`, cast via `cast_assoc`), but everything above it assumes exactly one: the editor reads `workflow.triggers[0]` (`collaborative-editor/components/WorkflowEditor.tsx:144`, `components/Header.tsx:239` for manual run/retry), base templates seed a single webhook trigger, and there is no add-trigger affordance in the diagram. Real work would span trigger creation UI, edge validation (which trigger connects to which entry job), snapshots/version hashing, YAML import/export and the run/work-order provenance display. Related: #1877 (should triggers point to multiple jobs), #2357.
- **Questions:** 1) Must all triggers enter at the same job, or may each trigger have its own entry point? 2) How should history and work-order views attribute a run to the trigger that started it?

## #1226 — Make it easier to see how to select all work orders
- **Verdict:** New
- **Type:** Improvement
- **Priority:** P4
- **Complexity:** Medium
- **Quality:** Low
- **Stale?:** No — the behaviour described is unchanged in the current history page.
- **Summary:** On the history page, selecting the header checkbox selects only the current page ("toggle_all_selections", `lib/lightning_web/live/run_live/index.ex:473`, with `all_selected?/2` at :810 comparing page rows to entries). The ability to act on every work order matching the current query is exposed only inside the rerun/cancel modals, where copy such as "You've selected all N work orders from page X of Y. There are a total of Z that match your current query" appears (`run_live/components.ex:655-847`, plus `rerun_job_component.ex`), gated on `all_selected? and total_entries > 1 and pages > 1`. So the capability is discoverable only after committing to a destructive action. No design or acceptance criteria were ever added; the issue still carries `needs detail`.
- **Questions:** 1) What is the desired affordance — an inline "select all N matching" banner above the table, or a split-button on the header checkbox? 2) Should "all matching" selection also drive non-rerun actions (cancel, future bulk delete)?

## #1254 — Partition tables by week and setup maintenance code
- **Verdict:** Already fixed
- **Type:** —
- **Priority:** —
- **Complexity:** —
- **Quality:** —
- **Stale?:** Yes — the plan was deliberately narrowed in Dec 2023 and the rest mothballed.
- **Summary:** The requested scope was weekly partitioning of `work_orders`, `attempts`, `runs` and `log_lines` plus partition-maintenance code. What shipped is `log_lines` only, and by hash rather than by week: `priv/repo/migrations/20231110102231_partition_log_lines_by_week.exs` renames the old table to `log_lines_monolith` and recreates `log_lines` as `PARTITION BY HASH(attempt_id)` across 100 partitions, with follow-ups `20240122112158` and `20240129204657` renaming constraints and FKs. No partition-maintenance module exists in `lib/`. The issue's own comments record the decision to start with `log_lines` and measure before doing more, and a "mothballing" note listing the open PRs (#1392, #1453, #1522) and the remaining `attempts`/`runs` work. It should be closed or re-filed against today's schema (`runs`, `steps`, `work_orders`) with fresh performance evidence.
- **Questions:** None

## #1300 — Port `crash_test` to `janitor_test`
- **Verdict:** New
- **Type:** Improvement
- **Priority:** P4
- **Complexity:** Low
- **Quality:** Medium
- **Stale?:** Partly — Janitor is now well covered, but the dead file the issue exists to retire is still in the tree.
- **Summary:** `test/lightning/crash_test.exs` is still present and still entirely commented out (128 of 153 lines are comments), headed by a pointer back to this issue; it exercised the old `Pipeline`/`ObanManager`/`RunStep` era including `max_run_duration` handling. Meanwhile `test/lightning/janitor_test.exs` now has ~378 lines covering `find_and_update_lost/0`: lost runs and their steps, unfinished steps under a finished run, `started_at` vs `claimed_at` timeout bases, already-completed runs, and per-run failure isolation. The remaining work is the audit the issue asks for — confirm each commented case is covered, covered elsewhere, or genuinely obsolete, then delete the file. Note the guidance in `.claude/guidelines/testable-supervision-trees.md` if any of it needs re-homing around the Janitor process.
- **Questions:** 1) Is anyone still relying on `crash_test.exs` as a record of intended crash semantics, or can it simply be deleted once the audit is written up?

## #1314 — In password inputs only show the eye/mask icon when the field is active
- **Verdict:** New
- **Type:** Improvement
- **Priority:** P4
- **Complexity:** Low
- **Quality:** Medium
- **Stale?:** No — the icon is still rendered unconditionally.
- **Summary:** The password input branch of `lib/lightning_web/components/new_inputs.ex` (~line 660-700) always renders a `hero-eye-slash` icon in an absolutely positioned container, with a `phx-click` that toggles the icon classes and flips the target input's `type` between `password` and `text` via `JS.toggle_attribute` scoped by `data-reveal-id`. The request is to reveal that control only when the field is focused or non-empty, which is a CSS/`JS`-level change on this one component (no server round-trip needed) but affects every password and token field in the app, including credential forms. The `data-reveal-id` scoping that fixed the closely related #2611 is already in place and would need to keep working.
- **Questions:** 1) Should the icon persist while the value is revealed even after blur, so users can re-mask it? 2) Does this apply to token/secret fields in credential forms too, or only auth-flow passwords?

## #1349 — Add `error_type` granularity to pills displaying run state
- **Verdict:** New
- **Type:** Improvement
- **Priority:** P3
- **Complexity:** Medium
- **Quality:** Medium
- **Stale?:** No — run pills still show only the bare state.
- **Summary:** Steps already get error-type-aware visuals: `step_icon/1` in `lib/lightning_web/live/run_live/components.ex:547` switches on `{reason, error_type}` and distinguishes `SecurityError`/`ImportError` (shield) from `TimeoutError`/`OOMError` (circle-ex), with a Sentry warning for unknown kill types. Run and work-order pills do not: `state_pill/1` (same file, ~line 110) takes only `:state` and maps it to a chip colour, so every kill renders as "Killed" regardless of cause. The data is available on runs (`field :error_type, :string` in `lib/lightning/runs/run.ex:120`) but not on work orders (`workorders/workorder.ex` has `state` only), which is the same modelling question raised in the companion issue #1350 (filtering history by error_type). Stuart flagged in Nov 2023 that more detail is needed before pickup; the `needs detail` label still stands.
- **Questions:** 1) What exactly should the pill show — "Killed: Timeout" text, a distinct colour/icon per error type, or a tooltip? 2) Do work-order-level pills need this too, which implies denormalising `error_type` onto `work_orders`?

# Triage batch 08 — openfn/lightning

## #1350 — Adjust history filters to allow sub-selection of error_type under "state"
- **Verdict:** New
- **Type:** Improvement
- **Priority:** P3
- **Complexity:** Medium
- **Quality:** Medium
- **Stale?:** No — the gap is unchanged in the current code.
- **Summary:** The history page filters on work order state only. `Lightning.WorkOrders.SearchParams` (`lib/lightning/workorders/search_params.ex`) exposes `status`, search fields/term, workflow/workorder id, date ranges and sort, and `RunLive.Index`'s `@filters_types` (`lib/lightning_web/live/run_live/index.ex:30-50`) is a flat set of per-state booleans (`killed`, `lost`, `exception`, …). `error_type` lives on `Run` (`lib/lightning/runs/run.ex:120`) and `Step` (`lib/lightning/invocation/step.ex:53`), not on `WorkOrder` (`lib/lightning/workorders/workorder.ex` has only `state` and `last_activity`), so the original design question — denormalise onto the work order versus join to the run — is still open. Values are producer-defined strings (e.g. `"LostAfterClaim"`, `"LostAfterStart"` from `Runs.mark_run_lost/1`, plus worker-supplied kinds), so there is no enumerated vocabulary to build a filter UI from. Related open umbrellas: #1791 (better history filters), #1792 (step sub-selection), #3238. A Canny request is linked to it.
- **Questions:** (1) Is there a fixed, documented set of `error_type` values Lightning and the worker agree on, or must the filter be free-text? (2) Should the filter match any run in the work order, or only the last one?

## #1360 — Consider Re-ordering the activity history page when a work order is re-run
- **Verdict:** New
- **Type:** Improvement
- **Priority:** P4
- **Complexity:** Low
- **Quality:** Low
- **Stale?:** Partly — the behaviour described still holds, but the issue is an unanswered design question, not a defined change.
- **Summary:** The behaviour is unchanged: history defaults to sorting by `last_activity` desc (`RunLive.Index` default filters, `Invocation` order clauses) and a re-run does bump `last_activity` (`lib/lightning/work_orders.ex:786`), but the LiveView's `handle_info` for `RunCreated`/`RunUpdated`/`WorkOrderUpdated` calls `update_page/2`, which replaces the row in place; only `WorkOrderCreated` inserts at the page position. So a re-run row updates but does not move, and the page only re-sorts on reload. The issue itself is a question posed to the PM with no agreed target behaviour, and the sole comment says to defer it to a holistic history-page epic. Note that later open issues push the opposite way — #3487 (jumpy/glitchy history table) and #2345 (limit refresh rate / load new work orders in background) — so live reordering may be actively undesirable.
- **Questions:** (1) Is the desired behaviour "move to top on re-run", or leave order stable and only highlight the changed row? (2) Given #3487 and #2345, should this be closed and folded into #1791?

## #1410 — Call a run "lost" if the socket is closed for N minutes
- **Verdict:** New
- **Type:** Improvement
- **Priority:** P3
- **Complexity:** High
- **Quality:** High
- **Stale?:** Partly — the per-run timeout complaint has been addressed; the socket-based proposal has not been implemented.
- **Summary:** Lost detection is still time-based, not connection-based. `Lightning.Janitor` runs on Oban cron and streams `Runs.Query.lost/0` (`lib/lightning/runs/query.ex:20-59`), which selects unfinished, non-final runs whose `COALESCE(started_at, claimed_at)` plus the run's own `options.run_timeout_ms` plus `Config.grace_period()` has passed (with a legacy fallback to `default_max_run_duration`), then calls `Runs.mark_run_lost/1` (sets `LostAfterClaim`/`LostAfterStart`) and fires a failure alert. Since 2023 the query does honour each run's configured timeout, so runs are no longer cut off by a single global absolute timeout — but nothing observes the worker's run-channel presence, and there is no cluster-wide process lookup as suggested in the last comment. Related open reports of the same class: #3565 (runs marked lost that should be re-enqueued), #3622, #4088.
- **Questions:** (1) Should socket-loss detection replace the duration-based janitor sweep, or run alongside it as a second trigger? (2) With multiple Lightning nodes, is Presence/`:pg`-based tracking acceptable, or must detection stay DB-driven?

## #1413 — Unsubscribe from Workflow emails via a link
- **Verdict:** New
- **Type:** Feature
- **Priority:** P4
- **Complexity:** Medium
- **Quality:** Medium
- **Stale?:** No — no unsubscribe path exists in the code today.
- **Summary:** Failure alerts are rendered from `lib/lightning_web/templates/failure_notifier/failure_alert.html.heex` via `Lightning.FailureEmail.deliver_failure_email/2`, and the template contains only work-order/run links and logs — no unsubscribe link or `List-Unsubscribe` header. Opting out today requires logging in and toggling `failure_alert` on the project's collaborator row (`Lightning.Projects.ProjectUser`, surfaced in `lib/lightning_web/live/components/data_tables.ex`), which is also where `digest` is set. Implementing this needs an authenticated-but-loginless mechanism (signed, scoped token) plus a public endpoint, since the preference is per project-user rather than global. Related open issue: #1467 (improve email failure alerts) — overlapping scope but not the same ask.
- **Questions:** (1) Should one link unsubscribe from that workflow, that project, or all notifications for the user? (2) Is a one-click unsubscribe (no confirmation page, RFC 8058 headers) acceptable given the link may be forwarded?

## #1422 — Add ability to edit a stored dataclip
- **Verdict:** New
- **Type:** Feature
- **Priority:** P4
- **Complexity:** High
- **Quality:** Low
- **Stale?:** Partly — a custom-dataclip path now covers much of the underlying need.
- **Summary:** Dataclip bodies remain immutable in the product. `Lightning.Invocation.update_dataclip/2` exists but is unused outside tests; the only user-facing mutation is `update_dataclip_name/3`, exposed by the collaborative editor's `SelectedDataclipView.tsx` (rename only). Dataclips are shared, referenced as inputs/outputs by steps and runs, subject to retention wiping, and audited, which is the source of the reporter's own caveat about changing existing ones. In the meantime the manual-run panel lets a user supply a custom body for a new run, which is the practical workaround for "I want to tweak this input and re-run". Adjacent open issues touch custom dataclip handling (#3237, #3218, #3241) but none covers editing a stored one.
- **Questions:** (1) Should editing create a new dataclip version/copy rather than mutate in place, given steps already reference it? (2) Which dataclip types are in scope — only user-created/custom ones, or run inputs/outputs too?

## #1437 — Improve UX for adding/removing auth methods to webhooks
- **Verdict:** Already fixed
- **Type:** Improvement
- **Priority:** —
- **Complexity:** —
- **Quality:** —
- **Stale?:** Yes — the table UI it complains about no longer exists.
- **Summary:** The 2023 flow (a table for attaching/detaching auth methods on a webhook trigger) has been replaced. Attaching now happens in the collaborative editor's trigger inspector (`assets/js/collaborative-editor/components/inspector/trigger/WebhookConfigureStep.tsx`), which holds a draft auth-method id set, commits on finish, gates on `can_write_webhook_auth_method`, and opens a server-rendered create-modal via `open_webhook_auth_modal`. Creation/editing/deletion moved to modal components (`webhook_auth_method_form_component.ex`, `webhook_auth_method_delete_modal.ex`) with an auth-type chooser step and reauthentication before revealing secrets, plus a managed table with linked-usage links in project settings. That rework was tracked as #3887 ("Add webhook authentication management to collaborative editor", closed Nov 2025); remaining work on this surface is #3970 ("Port Webhook Authentication To React"). No further action on #1437 without a fresh, specific complaint.
- **Questions:** None

## #1444 — Need to create an empty state for the webhook auth methods settings page when no auth methods exist
- **Verdict:** Already fixed
- **Type:** Improvement
- **Priority:** —
- **Complexity:** —
- **Quality:** —
- **Stale?:** Yes — the empty state exists.
- **Summary:** `LightningWeb.WorkflowLive.Components.webhook_auth_methods_table` renders an `:empty_state` slot when `Enum.empty?(@auth_methods)`, and the project settings "Webhook security" section supplies it (`lib/lightning_web/live/project_live/settings.html.heex:467-489`): an `.empty_state` with a `hero-plus-circle` icon, "No auth methods found.", and a "Create a new auth method" button wired to the new-auth-method modal and disabled without write permission. The issue's only content was a now-inaccessible private Zenhub screenshot, so the exact intended design cannot be compared, but the functional gap is closed.
- **Questions:** None

## #1445 — Improve validation handling when changing email
- **Verdict:** Already tracked
- **Type:** Improvement
- **Priority:** —
- **Complexity:** —
- **Quality:** —
- **Stale?:** Yes as written — the same ground is covered by a newer, legible issue.
- **Summary:** Superseded by open issue #2546 ("UX issues with updating email", ux/ui improvement + good first issue, last touched June 2026), which describes the same area with working screenshots and concrete asks: clear the "cannot be empty" password error as the user types, and only validate the password on submit. #1445's own body is a private Zenhub image that no longer resolves, so its specific complaint is unrecoverable. For context, the form (`lib/lightning_web/live/profile_live/form_component.html.heex:57-100`) is now driven by an `email_changeset` from `Accounts.validate_change_user_email/2` with `phx-change="validate_email"`, `phx-debounce="blur"`, and a submit button disabled while the changeset is invalid — the residual complaints in #2546 are about when validation fires, not whether it exists. Recommend closing #1445 in favour of #2546.
- **Questions:** None

## #1447 — Update UI for personal access token copy field
- **Verdict:** Already fixed
- **Type:** Improvement
- **Priority:** —
- **Complexity:** —
- **Quality:** —
- **Stale?:** Yes — the copy field's known defects were fixed in 2026 and this issue's own content is unrecoverable.
- **Summary:** The issue body is only a private Zenhub image that no longer resolves, so its specific ask can't be read. The same UI was re-reported in detail as #2463 ("UI inconsistency when copying user API token" — clipped "Copied" tooltip, copy icon disappearing on click), which was closed as completed on 2026-05-13 by PR #4590 ("Fix copy token tooltip clipping and icon flicker"). The current markup (`lib/lightning_web/live/tokens_live/index.html.heex`) renders the new token in a highlighted panel with a disabled `<input id="new_token">` plus a tooltipped `phx-hook="Copy"` button. Recommend closing as superseded by #2463/#4590; re-raise with a current screenshot if something still looks wrong.
- **Questions:** None

## #1460 — Redirect to desired page after login
- **Verdict:** New
- **Type:** Improvement
- **Priority:** P3
- **Complexity:** Medium
- **Quality:** High
- **Stale?:** No — the controller half is done, the LiveView half described in the issue is not.
- **Summary:** The dead-request path works: `require_authenticated_user` calls `maybe_store_return_to/1` (stores `current_path` in `:user_return_to` for GET requests) before redirecting to the login page, and every login entry point — session, registration, OIDC, TOTP — finishes through `UserAuth.redirect_with_return_to/2` (`lib/lightning_web/controllers/user_auth.ex:63-69, 490-508`). The gap is exactly the case the issue's second scenario describes: `LightningWeb.InitAssigns.on_mount/4` halts an expired LiveView mount with `{:halt, redirect(socket, to: ~p"/users/log_in")}` and captures no return path, so a user whose session dies while sitting on a page lands on login and then on the default signed-in path. Redirects from a LiveView mount can't write the session, so the return path has to travel some other way (query param, for instance).
- **Questions:** (1) Is a `?return_to=` query param on the login redirect acceptable, given it must be validated as a local path? (2) Should live navigation within a `live_session` after expiry be covered too, or only fresh mounts?

# Triage batch 09 — openfn/lightning

## #1467 — Improve Email Failure Alerts
- **Verdict:** New
- **Type:** Improvement
- **Priority:** P4
- **Complexity:** Low
- **Quality:** Low
- **Stale?:** Partly — the failure-alert email is still a thin template, but the only specification is a 2023 Slack permalink that cannot be read from the issue, so the requested improvements are unknown.
- **Summary:** The body is a bare Slack link (`p1701069851378409`) with a `needs detail` label and no comments. The current alert is `Lightning.FailureAlerter` (`lib/lightning/pipeline/failure_alerter.ex`) plus `Lightning.FailureEmail` (`lib/lightning/pipeline/failure_email.ex`) rendering `failure_alert.html.heex`: greeting, workflow/project name, work-order and run links, a rate-limit note, and a raw dump of `run.log_lines` in a `<pre>`. Recipients come from `Accounts.get_users_to_alert_for_project/1`, are filtered by `Projects.MailRecipients.may_receive?/2`, and delivery is rate-limited per workflow via `ProjectLimiter.limit_failure_alert/1`. Adjacent asks have since shipped separately (#2974 project name in subject, #3517 alerts off by default, #3602 lost-run notifications), so whatever remains from the Slack thread is unclear.
- **Questions:** (1) What specifically was asked for in that Slack thread — subject line, log excerpting, error summary, digest/grouping? (2) Is any of it already covered by #2974/#3517/#3602?

## #1478 — Introduce Node Authentication Audit information for ATNA compliance
- **Verdict:** New
- **Type:** Feature
- **Priority:** P3
- **Complexity:** High
- **Quality:** Low
- **Stale?:** Unclear — no ATNA-specific work exists in the codebase, so nothing has superseded it; whether ATNA is still a target is a product question (Brandon's team owns that call).
- **Summary:** The issue transcribes the ATNA requirement list (mutually authenticated TLS, X.509 node certificates, revocation, clock sync, tamper-evident audit logs, logging of failed authentication attempts, policy enforcement) without scoping any of it to Lightning. Today Lightning has a general audit subsystem (`lib/lightning/auditing.ex`, `lib/lightning/auditing/audit.ex`, with per-context modules for credentials, projects, workflows, webhook auth methods, channels, dataclips, version control) whose rows are plain DB records with no signing or integrity chain. Node-to-node authentication is JWT-based, not certificate-based: workers join over `lib/lightning_web/channels/worker_socket.ex` via `Workers.verify_worker_token/1`, and there is no per-node certificate, revocation, or failed-authentication audit event. Earlier ATNA tickets (#73 spike, #271 refactor/expand) were closed without producing this. Effectively an epic-sized compliance program, not a single work item.
- **Questions:** (1) Is ATNA certification still a committed requirement, and for which deployments? (2) Which subset (audit-log integrity vs. certificate-based node auth) should be scoped first?

## #1535 — Allow input and output dataclips to be optional for runs
- **Verdict:** Already fixed
- **Type:** —
- **Priority:** —
- **Complexity:** —
- **Quality:** —
- **Stale?:** Yes — the rejections described no longer happen; the event names in the issue predate the attempt/run→run/step rename.
- **Summary:** The 2023 `run:start`/`run:complete` events are today's `step:start`/`step:complete`. Neither now requires a dataclip. `Handlers.StartStep.new/2` (`lib/lightning/runs/handlers.ex:254`) validates only `job_id`, `run_id`, `snapshot_id`, `timestamp`, `step_id`; `input_dataclip_id` is merely existence- and project-scope-checked when present, and migration `priv/repo/migrations/20240124054202_add_wiped_to_dataclips.exs` made `steps.input_dataclip_id` nullable. `Handlers.CompleteStep.new/2` skips the dataclip validation entirely when both `output_dataclip` and `output_dataclip_id` are nil (and when `save_dataclips: false`), and `Handlers.CompleteRun.new/1` requires only `state` and `timestamp` — `final_state`/`final_dataclip_id` are optional. Leaf jobs returning no state are therefore accepted end to end.
- **Questions:** None

## #1544 — Relax log event restrictions for runs
- **Verdict:** Already fixed
- **Type:** —
- **Priority:** —
- **Complexity:** —
- **Quality:** —
- **Stale?:** Yes for the log half; the residual idea (once-only credential/dataclip fetches) was never implemented and would be a fresh, separate ticket.
- **Summary:** The ask was that Lightning stop gating worker→Lightning data on websocket receipt order. Current `run:log` / `run:batch_logs` handling (`lib/lightning_web/channels/run_channel.ex:226`, `Runs.append_run_log/3` and `Runs.append_run_logs_batch/3` in `lib/lightning/runs.ex:292`) applies no run-state or ordering condition at all — the only validation is that a supplied `step_id` belongs to the run via `RunStep`. Logs are accepted after `run:complete`. Batching later landed under #4123. The second half of the issue — capping `fetch:credential` and `fetch:dataclip` to once per run — is still absent: both handlers can be called repeatedly for as long as the socket is authorised, and the issue framed that as an open question to @stuartc rather than a decision.
- **Questions:** None

## #1579 — Either Password or 2FA for accessing Webhook Auth info, not both
- **Verdict:** New
- **Type:** Bug
- **Priority:** P3
- **Complexity:** Low
- **Quality:** High
- **Stale?:** No — reproduces on current `main`, unchanged since 2023.
- **Summary:** Revealing a webhook auth method's password or API key goes through a re-auth step inside `lib/lightning_web/live/workflow_live/webhook_auth_method_form_component.ex`. `authenticate_user_form/1` (line ~264) unconditionally renders a Password field, an "OR" divider, and a "2FA Code" field, and `valid_user_input?/2` (line 208) accepts either: `valid_password?(...) || valid_user_totp?(...)`. It never consults `current_user.mfa_enabled`, so a user with 2FA on can still bypass their second factor with a password alone, and a user without 2FA is shown a code field that can never succeed. The standalone re-auth LiveView (`lib/lightning_web/live/re_authenticate_live/new.ex` + `.html.heex`) already models this correctly: password by default, with the authenticator option offered only `:if={... @current_user.mfa_enabled}`. So the desired behaviour exists in one path and not the other.
- **Questions:** (1) Should backup codes count as a valid second factor here, as they do at login? (2) Should this modal reuse the sudo-token flow (`Accounts.generate_sudo_session_token/1`) instead of its own `sudo_mode?` assign?

## #1582 — Improve UX around "disabling" first edge
- **Verdict:** Already fixed
- **Type:** —
- **Priority:** —
- **Complexity:** —
- **Quality:** —
- **Stale?:** Yes — the confusing dual toggle no longer exists.
- **Summary:** Edges whose source is a trigger can no longer be disabled independently. `Lightning.Workflows.Edge.enable_if_source_trigger/1` (`lib/lightning/workflows/edge.ex:84`) force-sets `enabled: true` whenever `source_trigger_id` is present, and the React inspector reflects that: `EdgeInspector.tsx` renders the enabled toggle only `!edge.source_trigger_id`, while `EdgeForm.tsx` shows trigger edges the explanatory line "This path will be active if its trigger is enabled". Enable/disable for the first hop is now expressed solely through the trigger. Tracked and closed elsewhere as #3008 ("Do not allow edges with `source_trigger` to be disabled") and #1505 (toggle UX), with #3705 covering the edge toggle itself.
- **Questions:** None

## #1583 — Handle different scenarios when user doesn't have access to page/feature
- **Verdict:** New
- **Type:** Improvement
- **Priority:** P3
- **Complexity:** High
- **Quality:** Low
- **Stale?:** No — the underlying inconsistency persists, and role-gating work is still landing, but the issue is a policy question rather than a scoped change.
- **Summary:** The issue asks for a decided convention across three treatments (visible-but-disabled, visible-but-blocked with tooltip, fully hidden with 404). Lightning has the enforcement machinery but no uniform surfacing rule: policies live in `lib/lightning/policies/` (`permissions.ex` plus `users`, `project_users`, `workflows`, `credentials`, `collections`, `dataclips`, `exports`, `provisioning`, `sandboxes`), and LiveView entry points gate via `LightningWeb.Hooks` `:ensure_admin` / `:project_scope`, which redirect to `/projects` with a `:nav` flash of `:no_access`, `:no_access_no_back`, or `:not_found` rendered in `lib/lightning_web/live/live_helpers.ex:81-97`. Individual pages independently choose to hide, disable, or tooltip controls (~16 LiveViews call `Permissions.can?`). Recent commits ("Gate privileged fields and admin actions by role", "Enforce a project's MFA requirement in the authorisation layer") tightened enforcement without settling presentation. #1477 fixed one instance (project security settings) in Jan 2024.
- **Questions:** (1) Which of the three treatments is the default, and which features are exceptions? (2) Is the goal a written convention plus an audit of existing pages, or a shared component/hook that enforces it?

## #1590 — Harmonize different uses of new inputs
- **Verdict:** Already fixed
- **Type:** —
- **Priority:** —
- **Complexity:** —
- **Quality:** —
- **Stale?:** Yes — both repro paths are gone and the four inconsistencies were resolved generically.
- **Summary:** All four complaints were about `LightningWeb.Components.NewInputs` circa v0.12.0. Current `lib/lightning_web/components/new_inputs.ex` has a single `label/1` with one weight (`text-sm/6 font-medium text-slate-800`, line 1194), a shared `errors/1`+`error/1` pair emitting a consistent `error-space` wrapper and icon (lines 1211-1249), error visibility gated generically by `Phoenix.Component.used_input?/1` (lines 433, 1213) rather than per-form hacks, and uniform invalid-border styling (`border-danger-400 focus:border-danger-400`) applied at lines 680, 772, 1047, 1090. The JS-expression edge form that prompted the report no longer exists in HEEx — edge editing moved to the React collaborative editor (`assets/js/collaborative-editor/components/inspector/EdgeForm.tsx`). #3696 ("Create validation error display component") closed Oct 2025 covering the error-display half.
- **Questions:** None

## #1594 — Rename MFA to 2FA
- **Verdict:** New
- **Type:** Improvement
- **Priority:** P4
- **Complexity:** Medium
- **Quality:** Medium
- **Stale?:** Partly — the user-facing renaming was largely done by #1228/#1446; what remains is the internal/database rename plus two stray strings.
- **Summary:** Most visible copy already reads "two-factor"/"2FA" (`profile_live/mfa_component`, `user_totp_html/new`, `backup_codes_live`, `re_authenticate_live`, `user_auth`), but "multi-factor" survives in `lib/lightning_web/live/project_live/settings.html.heex` and `lib/lightning_web/live/project_live/mfa_required.html.heex`. The internal surface is still MFA throughout: `users.mfa_enabled` (`lib/lightning/accounts/user.ex:34`), `projects.requires_mfa` (`lib/lightning/projects/project.ex:26`, added by `20230727160506_add_require_mfa_to_projects_table.exs`), plus module/route/file names (`MFAComponent`, `ProjectLive.MFARequired`, hooks, `usage_limiting`). A rename therefore means two column renames with backfilled schema and provisioning/export payload references, not just find-and-replace. The issue itself carries an unresolved `question` label about whether to churn the database at all.
- **Questions:** (1) Do the database columns and provisioning/YAML field names have to change, or is UI-only copy sufficient? (2) Does renaming `requires_mfa` break the project provisioning/export API contract for existing consumers?

## #1597 — Support smaller screens on inspector
- **Verdict:** Already fixed
- **Type:** —
- **Priority:** —
- **Complexity:** —
- **Quality:** —
- **Stale?:** Yes — superseded by later small-screen and inspector-redesign work.
- **Summary:** Later tickets covered this ground and closed: #1908 "Fix usability issues for small screens" (Mar 2024), #2278 "Make panels responsive on the editor/inspector" (Oct 2024), #1840 "[DMP 2024] UX Redesign for Inspector" (Nov 2024), and #1962 inspector scroll bugs. The inspector has since been rebuilt in React under `assets/js/collaborative-editor/`, and `assets/package.json` depends on `react-resizable-panels@^3.0.6`, with resizable/collapsible panels used across `inspector/CodeViewPanel.tsx`, `run-viewer/RunViewerPanel.tsx`, `AIAssistantPanel.tsx` and `diagram/WorkflowDiagram.tsx` — i.e. the "resizable panes" ask from the issue. Any residual small-screen complaint should be filed fresh against the current React inspector with a specific viewport.
- **Questions:** None

# Batch 10 triage — openfn/lightning

## #1637 — Metadata Service (and docs service?)
- **Verdict:** New
- **Type:** Improvement
- **Priority:** P3
- **Complexity:** High
- **Quality:** Medium
- **Stale?:** No — `lib/lightning/metadata_service.ex` still shells out via `Lightning.CLI` on a `TaskWorker`, exactly as described.
- **Summary:** Adaptor metadata (used by the credential "magic" / metadata panel) is still produced by spawning the OpenFn CLI as an OS process: `MetadataService.fetch/3` wraps `Lightning.CLI` calls in `Lightning.TaskWorker.start_task(:cli_task_worker, ...)` and depends on `Lightning.AdaptorService` having the adaptor installed in a local repo dir. The metadata logic itself is unavoidably JS (adaptors export a `metadata()` function), so the ask is architectural: replace process-shelling with a long-lived JS service (possibly worker-hosted) that Lightning calls over an endpoint, which would also let adaptor docs be generated and cached server-side instead of in the browser. Note the reporter's own comment pointing at #492, which covers only the docs half (a `/docs/:adaptor/:version` endpoint) and is also still open; this issue is the broader one and the two should be reconciled rather than triaged independently.
- **Questions:** Should this be folded into #492 (or #492 closed into this) so there's one owning issue? Is the ws-worker the intended host for a Lightning-initiated JS service, given Lightning currently has no outbound address for workers?

## #1651 — Investigate UX and tech limitations of deleting Jobs in the middle of workflow
- **Verdict:** New
- **Type:** Improvement
- **Priority:** P3
- **Complexity:** Medium
- **Quality:** Low
- **Stale?:** No — the restriction survived the whole editor rewrite and is still enforced in the collaborative editor.
- **Summary:** Deleting a job that has downstream steps is still flatly disallowed rather than offered as a choice. `assets/js/collaborative-editor/hooks/useJobDeleteValidation.ts` disables the delete action with "Cannot delete: other jobs depend on this step" whenever `getOutgoingJobEdges` returns any non-ghost edge (and separately blocks the first job), and `createWorkflowStore.removeJob` only ever deletes the job plus its *incoming* edges, so it has no cascade or re-stitch path. The reporter wants the Hubspot-style prompt: delete just this step or this step and everything after it. Because the workflow lives in a Y.Doc and edges are reconciled by `reconcileDanglingReferences`, a cascade or reconnect operation has to be a single transaction that stays consistent for other collaborators, and it interacts with snapshots/`lock_version`.
- **Questions:** Is the desired third option "reconnect parent to child" as well as cascade-delete, or only the two Hubspot options? Should this remain an investigation/spike or be rewritten as an implementation issue against the collaborative editor?

## #1666 — Allow endpoint to be configured the same in dev as in prod
- **Verdict:** New
- **Type:** Improvement
- **Priority:** P4
- **Complexity:** Low
- **Quality:** High
- **Stale?:** No — the condition described is unchanged in the current tree.
- **Summary:** `LISTEN_ADDRESS` is still prod-only. `lib/lightning/config/bootstrap.ex` reads it (defaulting to `{127,0,0,1}`) and applies it as `http: [ip: listen_address, ...]`, but that whole block sits inside `if config_env() == :prod`. In dev, `config/dev.exs` hardcodes `http: [ip: {0,0,0,0}, port: 4000, compress: true]` with no env override, so a dev server always binds every interface and the documented variable silently does nothing. The requested end state is unchanged: honour `LISTEN_ADDRESS` in dev too, default it to `127.0.0.1`, and set `0.0.0.0` in the Docker container env instead of in the dev config. Acceptance criteria are already spelled out in the issue.
- **Questions:** Is there anything in the dev/docker-compose setup that relies on the dev server binding `0.0.0.0` today (container port mapping, device testing) that would break with a loopback default?

## #1670 — Un-mark workflow deletion
- **Verdict:** Already tracked
- **Type:** —
- **Priority:** —
- **Complexity:** —
- **Quality:** —
- **Stale?:** Partly — the problem is real and still present, but a newer, better-scoped issue owns it.
- **Summary:** Both halves of this report still hold: `Workflow.validate/1` applies `unique_constraint([:name, :project_id])` across soft-deleted rows (its message even admits "possibly pending deletion"), and while `cancel_deletion` exists for users, projects and sandboxes, there is no workflow equivalent — `Lightning.Workflows` only offers `request_deletion` setting `deleted_at`. However #4847 (open, Jun 2026, "Soft-deleted workflows: never purged, and the name-uniqueness constraint that traps us") covers the same ground with current context, and #3050 covers the adjacent archive-workflow request. Treat this as a +1 to #4847 and close as a duplicate; the reporter's own last comment already links #4163 and #511.
- **Questions:** None

## #1693 — Solve the `other_params` problem (UberAuth/OAuth2 library)
- **Verdict:** Already fixed
- **Type:** —
- **Priority:** —
- **Complexity:** —
- **Quality:** —
- **Stale?:** Yes — the credential OAuth stack was rewritten away from the `oauth2` library entirely.
- **Summary:** The flatten/unflatten gymnastics are gone. Credential OAuth now runs through `lib/lightning/auth_providers/oauth_http_client.ex`, which posts to the provider's token endpoint with Tesla and returns the decoded response body verbatim (`fetch_token/2`, `refresh_token/2`, `handle_response/2`), so the provider's token body lands in the credential body as-is — exactly what the issue asked for. The only surviving `other_params` reference in the tree is `lib/lightning/auth_providers/handler.ex:187`, which uses `%OAuth2.AccessToken{other_params: %{"id_token" => ...}}` for SSO/OIDC *user login*, a separate concern from credential storage and not what the issue is about. Recommend closing.
- **Questions:** None

## #1697 — Sql to clean duplicate dataclips
- **Verdict:** Not an issue
- **Type:** —
- **Priority:** —
- **Complexity:** —
- **Quality:** —
- **Stale?:** Yes — obsolete one-off remediation for deployments running pre-Feb-2024 Lightning.
- **Summary:** This asked for a hand-run SQL script to consolidate workorder/run dataclips duplicated by the bug in #1695, which was fixed by PR #1696 and closed 2 Feb 2024. The script was only ever needed by operators upgrading across that boundary; no such script exists in the repo (nothing dataclip-dedup-shaped under `priv/repo/migrations` or as a `.sql` file), and two and a half years of releases later there is no realistic population still carrying the duplicates. The linked Metabase question (analytics.openfn.org/question/526) that held the dedup concept is the only artefact. Recommend closing rather than triaging.
- **Questions:** None

## #1713 — Set names via exmachina sequences
- **Verdict:** Already fixed
- **Type:** —
- **Priority:** —
- **Complexity:** —
- **Quality:** —
- **Stale?:** Yes — a 2024 test-hygiene nit from a PR review comment, since absorbed.
- **Summary:** The ask (from a review comment on PR #1708) was to generate factory names via ExMachina sequences instead of hardcoding them. `test/support/factories.ex` now does this pervasively — `sequence(:project_name, ...)`, `sequence(:workflow_name, ...)`, `sequence(:job_name, ...)`, plus sequences for credentials, oauth clients, snapshots, log lines, emails and session titles. The only remaining literal names are deliberate fixtures (the `"main"`/`"staging"` environment names, whose values are semantically meaningful, and a couple of user first/last-name literals). Nothing actionable remains and there is no way to recover which specific line the review comment meant. Recommend closing.
- **Questions:** None

## #1717 — Can't load workflow on Safari 15.3
- **Verdict:** Not an issue
- **Type:** —
- **Priority:** —
- **Complexity:** —
- **Quality:** —
- **Stale?:** Yes — unreproducible in 2024, and the reported target is long EOL.
- **Summary:** A LiveView crash while loading a workflow was reported once on `2.0.0-rc8` in Safari 15.3, and nobody could reproduce it: the reporter failed on Safari 17.2 / rc9, a colleague noted Apple never even published 15.3 release notes, and the follow-up asking for a repro on `v2.0.2` went unanswered for two and a half years. Since then the workflow editor has been rewritten from the LiveView canvas to the React/Yjs collaborative editor (`assets/js/collaborative-editor/`), the toolchain moved to Vite with an `es2020` esbuild target, and `assets/package.json` declares a `defaults` browserslist — Safari 15 (Jan 2022) is outside supported baselines and none of the reported code path survives. Recommend closing as stale/unreproducible.
- **Questions:** None

## #1739 — Selecting a job node with a slow internet causes a `:timeout` error
- **Verdict:** New
- **Type:** Bug
- **Priority:** P3
- **Complexity:** Low
- **Quality:** Medium
- **Stale?:** Partly — the exact HTTPoison stacktrace is obsolete, but the unguarded-failure shape it exposed is still in the code.
- **Summary:** The reported trace is gone: `Lightning.AdaptorRegistry.Npm` no longer uses HTTPoison, it uses Tesla. The underlying fragility remains, though — `Npm.package_detail/1` calls `Tesla.get!/2`, which raises on any transport failure (timeout, DNS, TLS), and `fetch_npm_details/1` does nothing to catch it. Only `Npm.user_packages/1` degrades gracefully, and it handles just `{:error, :nxdomain}`. The results are consumed by `Task.async_stream(..., timeout: @timeout) |> Stream.map(fn {:ok, detail} -> detail end)`, so an `:exit` tuple from a timed-out task raises a `CaseClauseError` in the registry process rather than being logged and skipped. The registry is read on editor entry via `Lightning.AdaptorRegistry.all/0` in `lib/lightning_web/channels/workflow_channel.ex:113,133`. The 2024-11 follow-up comment also flags a distinct symptom — endless reconnect/reload loops and per-job-selection refetching on a poor connection — which is arguably the more user-visible half.
- **Questions:** Should the scope be just "AdaptorRegistry degrades gracefully offline and logs", or also the reconnect-loop / caching behaviour raised in the second comment (which reads like a separate issue)? Is offline/poor-connectivity operation a supported mode, or dev-only convenience?

## #1755 — Control log outputs (Epic)
- **Verdict:** Already fixed
- **Type:** —
- **Priority:** —
- **Complexity:** —
- **Quality:** —
- **Stale?:** Yes — every child is closed and shipped; the epic was just never closed.
- **Summary:** This epic's checklist is fully ticked and all three referenced children (#2205, #2206, #1863) are closed as completed by merged PRs. In the current tree, per-workflow console.log suppression exists as `Workflow.enable_job_logs` (`lib/lightning/workflows/workflow.ex:45`), plumbed through `Lightning.Runs.RunOptions` and translated for the worker in `lib/lightning_web/channels/run_with_options.ex:106-112` as `job_log_level: "none"`; it also flows through sandboxes, project merge and the Y.Doc serializer, so it's editable in the collaborative editor. Log-level selection shipped in a different shape than originally specified: #2206 was rewritten mid-flight and delivered as a per-user viewer filter (`current_user.preferences["desired_log_level"]` in `lib/lightning_web/components/viewers.ex`) rather than an admin-set per-workflow config with read-only visibility for editors/viewers. If the original admin-governance framing still matters, that gap needs a fresh issue rather than keeping this epic open.
- **Questions:** Was dropping admin-enforced per-workflow log levels in favour of a per-user filter an accepted product decision, or an unclosed gap worth a new issue? Can this epic be closed?


## Method and caveats

- Issues were fetched with `mcp__github__issue_read` (body plus comments), researched against the code in this checkout, and duplicate-checked with `mcp__github__search_issues` across open and closed issues.
- **The local checkout is shallow** (111 commits, since 2026-06-18), so `git log --grep` was not usable for confirming 2022–2023 fixes. Every "Already fixed" verdict rests on the *current state of the code* plus the linked issue or PR, not on commit archaeology. That is the right basis for the call, but it means the specific commit that fixed a thing is often not cited.
- GitHub search was rate-limited during the run (roughly one query per minute at times), so duplicate checks were paced rather than exhaustive. A handful of "New" verdicts could still turn out to have a duplicate that search did not surface.
- No GitHub state was modified and no repo files outside this report were touched. Labels were not applied and no comments were posted.
