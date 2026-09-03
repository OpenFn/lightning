# OpenFn Lightning PR corpus: raw aggregates

Companion to [REPORT-lightning.md](REPORT-lightning.md). That file argues a case; **this one does not**. It dumps the distributions, time series, term lists and cross-tabs underneath it so you can reach your own conclusions without re-scraping or adopting our framing.

Regenerate: `tooling/pr-history/dump_dataset.py > tooling/pr-history/DATASET-lightning.md`. The row-level dataset (`pulls.csv`, four `.ndjson` files including every comment body) lives in gitignored `.scratch/pr-history/openfn-lightning/` after a scrape.

## 0. Provenance and filters

Read this before using any number below.

| item | value |
|---|---|
| repository | OpenFn/lightning |
| snapshot taken | 2026-09-03T16:30:40Z |
| PRs in repo (all authors) | 2235 |
| PRs, bot-authored | 84 |
| **PRs used below unless stated** | **2151 human-authored** |
| reviews (all, incl. bots + self) | 4312 |
| inline review comments (all) | 2709 |
| conversation comments on PRs (all) | 4409 |
| **feedback units used below** | **4282** |
| requests made by the scrape | 4594 |

The **feedback unit** is the analysis grain: one thing a reviewer wrote. Three filters build it, and each one changes the denominators:

1. bot and GitHub-App authors dropped (`codecov[bot]`, `github-actions[bot]`, `dependabot[bot]`, `copilot-pull-request-reviewer[bot]`);
2. **self-review dropped** — a comment by the PR's own author is not feedback;
3. empty bodies dropped (an approval with no text is a review, not a unit).

So `1721` inline units here vs `2709` raw inline comments in the dataset. Mixing the two denominators is the easiest mistake to make with this data.

| slice | units | median chars | p90 chars | has ```suggestion | PII-screened |
|---|---|---|---|---|---|
| inline code comments | 1721 | 112 | 359 | 27 | 19 |
| review summary bodies | 1516 | 121 | 507 | 0 | 26 |
| — CHANGES_REQUESTED | 483 | 213 | 742 | 0 | 12 |
| — APPROVED | 833 | 54 | 317 | 0 | 9 |
| — COMMENTED | 193 | 172 | 632 | 0 | 5 |
| conversation comments | 1045 | 153 | 602 | 0 | 39 |
| all units | 4282 | 123 | 474 | 27 | 84 |

## 1. Per-quarter time series

Every quarter, every metric, human-authored PRs. `unrev` counts PRs with zero non-author reviews AND zero non-author inline comments. Percentiles are suppressed below 5 samples.

| quarter | opened | merged | closed unmerged | still open | unrev | unrev+merged | with change req | ttfr p50 h | ttfr p90 h | ttm p50 h | ttm p90 h | inline/PR | median churn |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 2022-Q1 | 12 | 10 | 2 | 0 | 8 | 6 | 1 | 30.4 | 30.6 | 17.3 | 98.1 | 0.08 | 165.0 |
| 2022-Q2 | 42 | 41 | 1 | 0 | 20 | 20 | 8 | 5.3 | 90.5 | 4.9 | 95.3 | 0.69 | 316.0 |
| 2022-Q3 | 75 | 66 | 9 | 0 | 28 | 20 | 13 | 13.2 | 147.1 | 16.0 | 195.5 | 1.0 | 132 |
| 2022-Q4 | 75 | 70 | 5 | 0 | 29 | 25 | 13 | 40.5 | 246.1 | 39.5 | 273.6 | 0.71 | 149 |
| 2023-Q1 | 106 | 92 | 14 | 0 | 46 | 35 | 19 | 39.9 | 182.0 | 29.7 | 286.0 | 0.9 | 82.0 |
| 2023-Q2 | 72 | 62 | 10 | 0 | 28 | 20 | 14 | 44.3 | 271.8 | 33.2 | 329.8 | 1.43 | 108.0 |
| 2023-Q3 | 99 | 85 | 14 | 0 | 28 | 19 | 20 | 16.6 | 114.7 | 21.0 | 162.3 | 0.66 | 77 |
| 2023-Q4 | 199 | 178 | 21 | 0 | 45 | 34 | 40 | 8.6 | 116.1 | 22.2 | 172.2 | 1.12 | 96 |
| 2024-Q1 | 138 | 124 | 14 | 0 | 35 | 24 | 30 | 12.5 | 145.5 | 21.4 | 256.7 | 1.8 | 137.0 |
| 2024-Q2 | 134 | 123 | 11 | 0 | 20 | 11 | 29 | 17.1 | 146.9 | 26.9 | 331.3 | 0.9 | 78.0 |
| 2024-Q3 | 134 | 115 | 18 | 1 | 32 | 20 | 26 | 19.7 | 116.6 | 26.8 | 184.6 | 1.1 | 110.0 |
| 2024-Q4 | 127 | 120 | 7 | 0 | 25 | 20 | 17 | 20.3 | 140.8 | 36.5 | 287.3 | 1.66 | 92 |
| 2025-Q1 | 115 | 104 | 10 | 1 | 14 | 6 | 19 | 19.4 | 143.3 | 43.3 | 189.6 | 1.83 | 88 |
| 2025-Q2 | 132 | 109 | 22 | 1 | 35 | 18 | 29 | 13.1 | 197.4 | 22.7 | 310.4 | 1.25 | 100.0 |
| 2025-Q3 | 86 | 77 | 9 | 0 | 17 | 13 | 21 | 6.4 | 147.0 | 25.3 | 271.4 | 3.28 | 105.0 |
| 2025-Q4 | 241 | 217 | 24 | 0 | 41 | 24 | 44 | 10.2 | 100.1 | 17.9 | 139.0 | 0.78 | 257 |
| 2026-Q1 | 129 | 110 | 14 | 5 | 31 | 18 | 27 | 31.7 | 185.2 | 62.5 | 332.5 | 1.84 | 219 |
| 2026-Q2 | 149 | 120 | 17 | 12 | 58 | 36 | 23 | 39.2 | 186.5 | 66.5 | 790.2 | 1.31 | 200 |
| 2026-Q3 | 86 | 45 | 9 | 32 | 45 | 15 | 7 | 26.7 | 216.3 | 18.6 | 243.7 | 0.71 | 203.0 |

`unrev+merged` is the censoring-free series: a merged PR that went unreviewed will never be reviewed, whereas a recent open one still might. Use it, not `unrev`, for any trend claim near the snapshot date.

## 2. Per-month opened/merged

Finer grain for anyone wanting to place a change against a release or a team change. The final month is partial.

| month | opened | merged |
|---|---|---|
| 2022-02 | 1 | 0 |
| 2022-03 | 11 | 10 |
| 2022-04 | 13 | 12 |
| 2022-05 | 14 | 15 |
| 2022-06 | 15 | 13 |
| 2022-07 | 27 | 23 |
| 2022-08 | 30 | 27 |
| 2022-09 | 18 | 14 |
| 2022-10 | 15 | 16 |
| 2022-11 | 32 | 27 |
| 2022-12 | 28 | 26 |
| 2023-01 | 43 | 41 |
| 2023-02 | 18 | 14 |
| 2023-03 | 45 | 37 |
| 2023-04 | 26 | 23 |
| 2023-05 | 20 | 20 |
| 2023-06 | 26 | 21 |
| 2023-07 | 34 | 31 |
| 2023-08 | 36 | 28 |
| 2023-09 | 29 | 27 |
| 2023-10 | 35 | 27 |
| 2023-11 | 119 | 104 |
| 2023-12 | 45 | 45 |
| 2024-01 | 51 | 41 |
| 2024-02 | 51 | 52 |
| 2024-03 | 36 | 29 |
| 2024-04 | 44 | 39 |
| 2024-05 | 58 | 52 |
| 2024-06 | 32 | 29 |
| 2024-07 | 53 | 51 |
| 2024-08 | 39 | 29 |
| 2024-09 | 42 | 37 |
| 2024-10 | 43 | 40 |
| 2024-11 | 50 | 45 |
| 2024-12 | 34 | 34 |
| 2025-01 | 42 | 42 |
| 2025-02 | 36 | 33 |
| 2025-03 | 37 | 29 |
| 2025-04 | 42 | 40 |
| 2025-05 | 46 | 33 |
| 2025-06 | 44 | 34 |
| 2025-07 | 25 | 26 |
| 2025-08 | 28 | 30 |
| 2025-09 | 33 | 25 |
| 2025-10 | 81 | 65 |
| 2025-11 | 76 | 74 |
| 2025-12 | 84 | 78 |
| 2026-01 | 37 | 33 |
| 2026-02 | 52 | 43 |
| 2026-03 | 40 | 34 |
| 2026-04 | 55 | 38 |
| 2026-05 | 51 | 47 |
| 2026-06 | 43 | 32 |
| 2026-07 | 36 | 27 |
| 2026-08 | 48 | 26 |
| 2026-09 | 2 | 0 |

## 3. Size

`churn = additions + deletions`, which **includes `mix.lock` and `package-lock.json`**, so some XL rows are dependency bumps rather than large human changes. The per-PR files endpoint was out of scope, so this cannot be corrected here. Buckets: XS ≤10, S ≤50, M ≤250, L ≤1000, XL >1000.

| size | PRs | unrev | unrev % | mean rounds (reviewed) | % change req | ttfr p50 h | ttm p50 h | inline/PR | mean files |
|---|---|---|---|---|---|---|---|---|---|
| XS | 279 | 85 | 30.5 | 1.47 | 6.2 | 2.6 | 5.2 | 0.06 | 1.7 |
| S | 437 | 129 | 29.5 | 1.63 | 14.3 | 4.4 | 9.1 | 0.3 | 2.9 |
| M | 644 | 162 | 25.2 | 1.9 | 22.0 | 15.6 | 22.9 | 0.79 | 5.7 |
| L | 501 | 137 | 27.3 | 2.57 | 39.0 | 25.2 | 59.4 | 2.16 | 11.8 |
| XL | 290 | 72 | 24.8 | 3.07 | 44.0 | 51.8 | 112.6 | 3.33 | 40.8 |

### Continuous distributions

| metric | n | min | p25 | p50 | p75 | p90 | p99 | max | mean |
|---|---|---|---|---|---|---|---|---|---|
| churn (lines) | 2151 | 0 | 29 | 122 | 469 | 1342 | 7676 | 137258 | 670.9 |
| changed files | 2151 | 0 | 3 | 5 | 11 | 21 | 70 | 1292 | 10.8 |
| commits | 2151 | 0 | 2 | 3 | 7 | 14 | 49 | 267 | 6.6 |
| hours to first review | 1566 | 0.0 | 2.0 | 17.1 | 60.9 | 151.8 | 790.1 | 2878.0 | 64.7 |
| hours to merge | 1868 | 0.0 | 2.8 | 24.6 | 110.3 | 250.4 | 1014.5 | 3714.9 | 99.9 |
| hours open total | 2151 | 0.0 | 3.4 | 29.0 | 136.7 | 363.4 | 3908.6 | 21020.0 | 238.8 |
| inline comments | 2151 | 0 | 0 | 0 | 0 | 4 | 18 | 50 | 1.3 |
| conversation comments | 2151 | 0 | 1 | 1 | 2 | 4 | 10 | 34 | 2.0 |
| reviews | 2151 | 0 | 0 | 1 | 2 | 4 | 8 | 14 | 1.5 |
| review rounds | 2151 | 0 | 0 | 1 | 2 | 4 | 8 | 14 | 1.5 |
| distinct reviewers | 2151 | 0 | 0 | 1 | 2 | 2 | 3 | 6 | 1.1 |

## 4. Review states

| state | reviews | share |
|---|---|---|
| APPROVED | 2061 | 47.8% |
| COMMENTED | 1712 | 39.7% |
| CHANGES_REQUESTED | 528 | 12.2% |
| DISMISSED | 11 | 0.3% |

By quarter, non-author reviews only:

| quarter | bodies | APPROVED | CHANGES_REQUESTED | COMMENTED | DISMISSED |
|---|---|---|---|---|---|
| 2022-Q1 | 2 | 1 | 1 | 0 | 0 |
| 2022-Q2 | 11 | 3 | 7 | 1 | 0 |
| 2022-Q3 | 33 | 13 | 17 | 3 | 0 |
| 2022-Q4 | 24 | 8 | 12 | 4 | 0 |
| 2023-Q1 | 49 | 14 | 25 | 10 | 0 |
| 2023-Q2 | 39 | 14 | 19 | 6 | 0 |
| 2023-Q3 | 52 | 25 | 20 | 7 | 0 |
| 2023-Q4 | 143 | 55 | 55 | 31 | 2 |
| 2024-Q1 | 112 | 51 | 39 | 22 | 0 |
| 2024-Q2 | 107 | 50 | 35 | 20 | 2 |
| 2024-Q3 | 104 | 55 | 33 | 15 | 1 |
| 2024-Q4 | 62 | 41 | 15 | 6 | 0 |
| 2025-Q1 | 100 | 64 | 22 | 14 | 0 |
| 2025-Q2 | 112 | 62 | 37 | 13 | 0 |
| 2025-Q3 | 89 | 52 | 28 | 8 | 1 |
| 2025-Q4 | 208 | 137 | 54 | 17 | 0 |
| 2026-Q1 | 119 | 82 | 31 | 5 | 1 |
| 2026-Q2 | 111 | 79 | 25 | 7 | 0 |
| 2026-Q3 | 38 | 26 | 8 | 4 | 0 |

## 5. Category cross-tab

Categories are **derived** from the corpus, not pre-specified — provenance in the header of `categories.py`. Multi-label, so columns do not sum to 100%. Every count is a **lower bound**; patterns favour precision over recall.

The reply-rate column is against a baseline of **43.2%** (743 of 1721 inline comments drew a reply). Below baseline = complied with silently; above = argued about.

| category | in CHANGES_REQUESTED | % of 483 | in inline | % of 1721 | in conversation | % drew a reply |
|---|---|---|---|---|---|---|
| Data model, migrations and queries | 35 | 7.2 | 157 | 9.1 | 47 | 52.9 |
| Acceptance testing | 84 | 17.4 | 86 | 5.0 | 95 | 57.0 |
| Naming | 26 | 5.4 | 68 | 4.0 | 12 | 61.8 |
| Abstraction pushback | 12 | 2.5 | 62 | 3.6 | 20 | 69.4 |
| Correctness and failure modes | 25 | 5.2 | 59 | 3.4 | 29 | 55.9 |
| Missing tests and coverage | 20 | 4.1 | 32 | 1.9 | 14 | 18.8 |
| Diff hygiene | 6 | 1.2 | 13 | 0.8 | 2 | 84.6 |
| Changelog | 29 | 6.0 | 11 | 0.6 | 24 | 18.2 |
| Scope and ownership | 6 | 1.2 | 11 | 0.6 | 1 | 45.5 |
| Logging and observability | 4 | 0.8 | 10 | 0.6 | 10 | 40.0 |
| Routing only | 26 | 5.4 | 10 | 0.6 | 2 | 30.0 |
| Test design | 3 | 0.6 | 9 | 0.5 | 0 | 55.6 |

### Category by year (inline comments)

| category | 2022 | 2023 | 2024 | 2025 | 2026 |
|---|---|---|---|---|---|
| Acceptance testing | 10 (11%) | 13 (4%) | 27 (6%) | 25 (4%) | 11 (4%) |
| Abstraction pushback | 2 (2%) | 20 (6%) | 11 (3%) | 19 (3%) | 10 (3%) |
| Correctness and failure modes | 3 (3%) | 4 (1%) | 7 (2%) | 24 (4%) | 21 (7%) |
| Naming | 1 (1%) | 12 (4%) | 23 (5%) | 23 (4%) | 9 (3%) |
| Test design | 0 (0%) | 3 (1%) | 1 (0%) | 4 (1%) | 1 (0%) |
| Missing tests and coverage | 5 (5%) | 2 (1%) | 2 (0%) | 21 (4%) | 2 (1%) |
| Data model, migrations and queries | 9 (10%) | 45 (13%) | 42 (10%) | 32 (6%) | 29 (10%) |
| Changelog | 0 (0%) | 3 (1%) | 2 (0%) | 3 (1%) | 3 (1%) |
| Diff hygiene | 4 (4%) | 2 (1%) | 1 (0%) | 5 (1%) | 1 (0%) |
| Scope and ownership | 2 (2%) | 0 (0%) | 1 (0%) | 5 (1%) | 3 (1%) |
| Logging and observability | 2 (2%) | 1 (0%) | 2 (0%) | 0 (0%) | 5 (2%) |
| Routing only | 0 (0%) | 2 (1%) | 2 (0%) | 4 (1%) | 2 (1%) |

## 6. Where comments land

Full distribution over two-level path prefixes, from the `path` on inline comments. This is where review **attention** went, not where change went: it is not normalised by how often each area was modified.

| path prefix | inline comments | % of 1721 | distinct PRs | comments/PR |
|---|---|---|---|---|
| lib/lightning | 548 | 31.8 | 195 | 2.81 |
| lib/lightning_web | 506 | 29.4 | 199 | 2.54 |
| assets/js | 272 | 15.8 | 94 | 2.89 |
| test/lightning | 136 | 7.9 | 59 | 2.31 |
| test/lightning_web | 57 | 3.3 | 43 | 1.33 |
| priv/repo | 40 | 2.3 | 23 | 1.74 |
| CHANGELOG.md | 28 | 1.6 | 24 | 1.17 |
| config/runtime.exs | 22 | 1.3 | 14 | 1.57 |
| test/support | 11 | 0.6 | 9 | 1.22 |
| lib/mix | 11 | 0.6 | 4 | 2.75 |
| config/config.exs | 10 | 0.6 | 7 | 1.43 |
| test/integration | 10 | 0.6 | 6 | 1.67 |
| config/dev.exs | 8 | 0.5 | 4 | 2.0 |
| assets/test | 8 | 0.5 | 5 | 1.6 |
| assets/vendor | 7 | 0.4 | 1 | 7.0 |
| .env.example | 5 | 0.3 | 5 | 1.0 |
| test/mix | 5 | 0.3 | 1 | 5.0 |
| README.md | 4 | 0.2 | 2 | 2.0 |
| DEPLOYMENT.md | 3 | 0.2 | 2 | 1.5 |
| config/test.exs | 3 | 0.2 | 3 | 1.0 |
| priv/gettext | 3 | 0.2 | 2 | 1.5 |
| bin/bootstrap | 3 | 0.2 | 1 | 3.0 |
| .github/pull_request_template.md | 3 | 0.2 | 1 | 3.0 |
| assets/package.json | 3 | 0.2 | 2 | 1.5 |
| assets/css | 2 | 0.1 | 1 | 2.0 |
| mix.exs | 2 | 0.1 | 1 | 2.0 |
| test/test_helper.exs | 2 | 0.1 | 1 | 2.0 |
| CLAUDE.md | 2 | 0.1 | 1 | 2.0 |
| assets/yarn.lock | 1 | 0.1 | 1 | 1.0 |
| Dockerfile-dev | 1 | 0.1 | 1 | 1.0 |
| .github/ISSUE_TEMPLATE | 1 | 0.1 | 1 | 1.0 |
| .circleci/config.yml | 1 | 0.1 | 1 | 1.0 |
| mix.lock | 1 | 0.1 | 1 | 1.0 |
| .vscode/settings.json | 1 | 0.1 | 1 | 1.0 |
| bin/format | 1 | 0.1 | 1 | 1.0 |

Top individual files:

| file | inline comments |
|---|---|
| lib/lightning_web/live/workflow_live/edit.ex | 47 |
| lib/lightning/projects.ex | 35 |
| lib/lightning/accounts.ex | 30 |
| CHANGELOG.md | 28 |
| lib/lightning/work_orders.ex | 26 |
| lib/lightning/projects/merge_projects.ex | 23 |
| config/runtime.exs | 22 |
| assets/js/workflow-diagram/WorkflowDiagram.tsx | 20 |
| lib/lightning_web/live/project_live/settings.ex | 17 |
| lib/lightning/workflows.ex | 17 |
| test/lightning/projects/merge_projects_test.exs | 17 |
| lib/lightning_web/channels/workflow_channel.ex | 17 |
| lib/lightning/credentials.ex | 16 |
| lib/lightning_web/channels/run_channel.ex | 15 |
| lib/lightning/version_control/version_control.ex | 15 |
| lib/lightning/config/bootstrap.ex | 15 |
| assets/js/collaborative-editor/components/Header.tsx | 14 |
| lib/lightning/accounts/user.ex | 13 |
| lib/lightning/invocation.ex | 12 |
| lib/lightning_web/components/new_inputs.ex | 12 |
| lib/lightning_web/live/sandbox_live/components.ex | 12 |
| lib/lightning_web/channels/attempt_channel.ex | 11 |
| lib/lightning_web/channels/worker_channel.ex | 11 |
| assets/js/collaborative-editor/components/MessageList.tsx | 11 |
| config/config.exs | 10 |
| lib/lightning_web/live/project_live/settings.html.heex | 10 |
| lib/lightning/runs/handlers.ex | 10 |
| assets/js/log-viewer/store.ts | 10 |
| assets/js/workflow-diagram/nodes/Node.tsx | 10 |
| lib/mix/tasks/merge_projects.ex | 10 |

## 7. Vocabulary

Code fences, quoted lines, raw HTML, markdown links and URLs are stripped before counting (`textutil.prose_of`). Without that step pasted screenshots put `img width alt src` at the top of this list. Structural stopwords removed; no topic words removed.

### Top 50 words

| term | units containing | total occurrences |
|---|---|---|
| please | 345 | 388 |
| work | 339 | 408 |
| test | 291 | 377 |
| hey | 284 | 284 |
| issue | 252 | 290 |
| run | 238 | 422 |
| add | 227 | 254 |
| something | 220 | 250 |
| function | 215 | 272 |
| know | 209 | 236 |
| workflow | 207 | 394 |
| tests | 204 | 261 |
| user | 202 | 299 |
| error | 202 | 278 |
| job | 201 | 280 |
| instead | 193 | 211 |
| case | 168 | 184 |
| since | 164 | 183 |
| fix | 159 | 182 |
| project | 158 | 256 |
| added | 152 | 168 |
| works | 146 | 155 |
| different | 144 | 169 |
| time | 143 | 166 |
| back | 141 | 179 |
| check | 140 | 161 |
| stuff | 139 | 163 |
| call | 137 | 152 |
| remove | 132 | 140 |
| nicely | 130 | 130 |
| set | 128 | 157 |
| happy | 124 | 131 |
| without | 122 | 130 |
| small | 121 | 128 |
| update | 121 | 132 |
| left | 120 | 125 |
| name | 118 | 159 |
| another | 117 | 122 |
| message | 115 | 152 |
| take | 114 | 119 |
| rather | 114 | 137 |
| button | 111 | 181 |
| users | 111 | 143 |
| component | 110 | 141 |
| try | 109 | 115 |
| around | 106 | 116 |
| much | 106 | 112 |
| default | 106 | 124 |
| made | 104 | 112 |
| either | 103 | 109 |

### Top 50 bigrams

| term | units containing | total occurrences |
|---|---|---|
| test coverage | 32 | 33 |
| update changelog | 27 | 28 |
| work order | 27 | 32 |
| please remove | 25 | 26 |
| feel free | 23 | 23 |
| please add | 23 | 25 |
| even though | 21 | 21 |
| please update | 20 | 20 |
| error message | 20 | 21 |
| hey work | 19 | 19 |
| come back | 19 | 19 |
| create workflow | 17 | 19 |
| hey job | 16 | 16 |
| collaborative editor | 16 | 18 |
| failing tests | 15 | 15 |
| project settings | 14 | 17 |
| error handling | 14 | 15 |
| please fix | 13 | 13 |
| env vars | 13 | 13 |
| work orders | 13 | 15 |
| everything else | 13 | 13 |
| workflow diagram | 13 | 13 |
| function call | 13 | 14 |
| save button | 12 | 16 |
| works expected | 12 | 12 |
| history page | 12 | 12 |
| changelog entry | 12 | 12 |
| tests failing | 12 | 12 |
| failing test | 11 | 13 |
| something else | 11 | 11 |
| job left | 11 | 11 |
| validation steps | 11 | 12 |
| test case | 11 | 13 |
| tested works | 11 | 11 |
| double check | 11 | 11 |
| run button | 11 | 20 |
| non blocking | 11 | 11 |
| env variable | 10 | 10 |
| please check | 10 | 10 |
| please address | 10 | 10 |
| made tweaks | 10 | 10 |
| made small | 10 | 10 |
| trigger job | 10 | 10 |
| please move | 10 | 10 |
| follow issue | 10 | 10 |
| billing app | 10 | 10 |
| every time | 10 | 10 |
| run workflow | 10 | 13 |
| project name | 9 | 11 |
| another user | 9 | 9 |

### Top 50 trigrams

| term | units containing | total occurrences |
|---|---|---|
| please update changelog | 10 | 10 |
| appear test coverage | 9 | 9 |
| please feel free | 7 | 7 |
| create work order | 7 | 7 |
| midigo frank wrote | 5 | 5 |
| wrote taylor downs | 5 | 5 |

## 8. Log-odds contrasts

Log-odds ratio with an informative Dirichlet prior (Monroe, Colaresi & Quinn 2008), reported as a z-score. Raw frequency would return the commonest English words in both slices; this returns what is **distinctive**. Slices are structural — no topical assumption is made anywhere in this section.

Positive z = distinctive of the first slice. Minimum document frequency 5.

### CHANGES_REQUESTED vs APPROVED review bodies

483 vs 833 units.

| distinctive of FIRST | z | n first | n second |
|---|---|---|---|
| button | 4.67 | 81 | 5 |
| please | 4.09 | 148 | 33 |
| image | 3.61 | 46 | 2 |
| input | 3.48 | 43 | 2 |
| run | 3.03 | 103 | 26 |
| github | 3.03 | 34 | 2 |
| user | 2.99 | 86 | 20 |
| link | 2.91 | 41 | 5 |
| panel | 2.78 | 45 | 7 |
| provider | 2.64 | 23 | 0 |
| step | 2.63 | 27 | 2 |
| error | 2.60 | 62 | 14 |
| retry | 2.56 | 26 | 2 |
| current | 2.55 | 23 | 1 |
| email | 2.54 | 35 | 5 |
| trigger | 2.50 | 25 | 2 |
| page | 2.42 | 45 | 9 |
| silently | 2.40 | 19 | 0 |
| select | 2.36 | 20 | 1 |
| rather | 2.34 | 38 | 7 |
| update | 2.34 | 35 | 6 |
| control | 2.29 | 19 | 1 |
| edit | 2.20 | 30 | 5 |
| requests | 2.14 | 17 | 1 |
| loom | 2.14 | 17 | 1 |
| callback | 2.14 | 17 | 1 |
| seeing | 2.14 | 20 | 2 |
| hover | 2.13 | 15 | 0 |
| create | 2.13 | 32 | 6 |
| settings | 2.06 | 16 | 1 |
| dataclip | 2.06 | 16 | 1 |
| enabled | 1.98 | 15 | 1 |
| edges | 1.98 | 13 | 0 |
| browser | 1.98 | 18 | 2 |
| header | 1.98 | 18 | 2 |
| selected | 1.97 | 21 | 3 |
| existing | 1.97 | 24 | 4 |
| workflow | 1.95 | 69 | 21 |
| users | 1.91 | 32 | 7 |
| mind | 1.91 | 12 | 0 |
| write | 1.91 | 12 | 0 |
| exists | 1.91 | 12 | 0 |
| specific | 1.90 | 14 | 1 |
| written | 1.90 | 14 | 1 |
| clickable | 1.90 | 14 | 1 |
| enter | 1.89 | 17 | 2 |
| spec | 1.82 | 11 | 0 |
| concerns | 1.82 | 11 | 0 |
| row | 1.82 | 11 | 0 |
| clicking | 1.80 | 16 | 2 |

| distinctive of SECOND | z | n first | n second |
|---|---|---|---|
| nicely | -9.01 | 19 | 96 |
| works | -7.23 | 17 | 66 |
| tested | -5.74 | 11 | 42 |
| added | -4.52 | 31 | 48 |
| issue | -4.38 | 41 | 55 |
| work | -4.26 | 105 | 101 |
| happy | -4.11 | 19 | 34 |
| perfect | -4.00 | 6 | 21 |
| man | -3.98 | 5 | 20 |
| approved | -3.79 | 0 | 20 |
| made | -3.74 | 26 | 37 |
| clean | -3.74 | 8 | 21 |
| fine | -3.62 | 10 | 22 |
| lgtm | -3.59 | 0 | 18 |
| catch | -3.39 | 3 | 14 |
| approving | -3.39 | 0 | 16 |
| tiny | -3.26 | 4 | 14 |
| stuff | -3.13 | 22 | 29 |
| query | -3.12 | 7 | 16 |
| frank | -3.08 | 3 | 12 |
| merging | -3.05 | 13 | 21 |
| improvement | -3.05 | 2 | 11 |
| side | -2.94 | 15 | 22 |
| end | -2.93 | 5 | 13 |
| expected | -2.77 | 7 | 14 |
| follow | -2.75 | 5 | 12 |
| locally | -2.75 | 5 | 12 |
| tweaks | -2.73 | 3 | 10 |
| love | -2.71 | 18 | 23 |
| extra | -2.71 | 2 | 9 |
| elias | -2.54 | 4 | 10 |
| lovely | -2.53 | 3 | 9 |
| apollo | -2.52 | 2 | 8 |
| appreciate | -2.52 | 2 | 8 |
| technical | -2.46 | 1 | 7 |
| charm | -2.40 | 0 | 8 |
| manual | -2.34 | 5 | 10 |
| question | -2.34 | 5 | 10 |
| important | -2.34 | 5 | 10 |
| perspective | -2.34 | 5 | 10 |
| huge | -2.32 | 3 | 8 |
| global | -2.30 | 2 | 7 |
| staging | -2.30 | 2 | 7 |
| load | -2.30 | 2 | 7 |
| unused | -2.26 | 1 | 6 |
| congratulations | -2.26 | 1 | 6 |
| helpful | -2.26 | 1 | 6 |
| fantastic | -2.24 | 9 | 13 |
| may | -2.20 | 8 | 12 |
| steps | -2.20 | 8 | 12 |

### inline code comments vs conversation comments

1721 vs 1045 units.

| distinctive of FIRST | z | n first | n second |
|---|---|---|---|
| function | 9.65 | 194 | 30 |
| call | 5.73 | 91 | 25 |
| module | 5.57 | 65 | 10 |
| avoid | 4.93 | 50 | 7 |
| functions | 4.79 | 49 | 8 |
| instead | 4.58 | 103 | 46 |
| remove | 4.57 | 69 | 23 |
| calling | 4.32 | 37 | 4 |
| changeset | 4.31 | 39 | 6 |
| since | 4.26 | 95 | 44 |
| inside | 4.20 | 42 | 9 |
| query | 4.15 | 46 | 12 |
| move | 4.09 | 50 | 15 |
| perhaps | 3.98 | 36 | 7 |
| given | 3.92 | 40 | 10 |
| pattern | 3.77 | 46 | 15 |
| called | 3.76 | 38 | 10 |
| name | 3.75 | 75 | 35 |
| case | 3.70 | 92 | 48 |
| default | 3.58 | 60 | 26 |
| adding | 3.53 | 37 | 11 |
| string | 3.47 | 44 | 16 |
| variable | 3.43 | 28 | 6 |
| wondering | 3.38 | 29 | 7 |
| set | 3.36 | 71 | 36 |
| match | 3.35 | 35 | 11 |
| part | 3.32 | 30 | 8 |
| component | 3.31 | 58 | 27 |
| struct | 3.28 | 22 | 3 |
| return | 3.20 | 35 | 12 |
| needed | 3.20 | 38 | 14 |
| schema | 3.16 | 33 | 11 |
| field | 3.15 | 36 | 13 |
| matching | 3.15 | 26 | 0 |
| value | 3.14 | 49 | 22 |
| params | 3.08 | 26 | 7 |
| map | 3.06 | 32 | 11 |
| reason | 3.01 | 39 | 16 |
| block | 3.01 | 30 | 10 |
| always | 2.98 | 50 | 24 |
| transaction | 2.89 | 18 | 3 |
| migration | 2.89 | 18 | 3 |
| single | 2.87 | 39 | 17 |
| test | 2.87 | 124 | 84 |
| sense | 2.85 | 33 | 13 |
| calls | 2.85 | 33 | 13 |
| queries | 2.84 | 19 | 4 |
| multi | 2.82 | 16 | 2 |
| moved | 2.78 | 17 | 3 |
| previous | 2.77 | 20 | 5 |

| distinctive of SECOND | z | n first | n second |
|---|---|---|---|
| issue | -5.32 | 52 | 130 |
| step | -5.30 | 12 | 66 |
| hey | -4.96 | 21 | 75 |
| workflow | -4.76 | 86 | 168 |
| apollo | -4.56 | 7 | 46 |
| button | -4.50 | 18 | 63 |
| closing | -4.28 | 1 | 41 |
| history | -4.26 | 14 | 53 |
| open | -4.08 | 18 | 57 |
| ready | -3.89 | 1 | 33 |
| edit | -3.86 | 13 | 46 |
| inspector | -3.77 | 2 | 29 |
| openfn | -3.70 | 2 | 28 |
| fixed | -3.70 | 10 | 39 |
| undo | -3.67 | 3 | 28 |
| click | -3.62 | 13 | 43 |
| icon | -3.59 | 9 | 36 |
| api | -3.56 | 8 | 34 |
| cli | -3.55 | 16 | 47 |
| prompt | -3.55 | 0 | 34 |
| session | -3.49 | 6 | 30 |
| patch | -3.43 | 2 | 24 |
| merging | -3.37 | 5 | 27 |
| panel | -3.37 | 20 | 51 |
| top | -3.35 | 7 | 30 |
| taylor | -3.33 | 4 | 25 |
| feedback | -3.28 | 5 | 26 |
| rag | -3.28 | 2 | 22 |
| chat | -3.23 | 9 | 32 |
| post | -3.19 | 3 | 22 |
| sync | -3.19 | 5 | 25 |
| fix | -3.17 | 25 | 56 |
| app | -3.16 | 19 | 47 |
| colour | -3.10 | 1 | 20 |
| tests | -3.06 | 49 | 88 |
| happy | -3.03 | 20 | 47 |
| release | -3.01 | 3 | 20 |
| today | -3.00 | 8 | 28 |
| adaptor | -2.90 | 8 | 27 |
| wrote | -2.87 | 1 | 17 |
| lightning | -2.86 | 37 | 69 |
| sort | -2.86 | 7 | 25 |
| back | -2.85 | 46 | 81 |
| page | -2.84 | 16 | 39 |
| run | -2.82 | 100 | 149 |
| edge | -2.81 | 11 | 31 |
| deploy | -2.75 | 2 | 16 |
| manual | -2.74 | 4 | 19 |
| left | -2.71 | 6 | 22 |
| show | -2.71 | 19 | 42 |

### inline comments that drew a reply vs those that did not

743 vs 978 units.

| distinctive of FIRST | z | n first | n second |
|---|---|---|---|
| rename | 2.82 | 15 | 1 |
| user | 2.75 | 56 | 30 |
| cast | 2.39 | 11 | 1 |
| workflows | 2.16 | 23 | 10 |
| naming | 2.14 | 9 | 0 |
| updating | 2.14 | 9 | 0 |
| fetch | 2.14 | 9 | 0 |
| steps | 2.13 | 9 | 1 |
| row | 2.11 | 12 | 3 |
| index | 2.11 | 12 | 3 |
| fails | 2.02 | 13 | 4 |
| different | 2.00 | 35 | 20 |
| channel | 1.99 | 8 | 1 |
| finished | 1.99 | 8 | 1 |
| hook | 1.96 | 11 | 3 |
| ecto | 1.94 | 14 | 5 |
| header | 1.88 | 7 | 0 |
| hash | 1.83 | 7 | 1 |
| allowed | 1.83 | 7 | 1 |
| jobs | 1.82 | 19 | 9 |
| owner | 1.79 | 10 | 3 |
| structure | 1.79 | 10 | 3 |
| process | 1.79 | 10 | 3 |
| future | 1.78 | 13 | 5 |
| entire | 1.74 | 6 | 0 |
| records | 1.74 | 6 | 0 |
| tooltip | 1.74 | 6 | 0 |
| map | 1.72 | 21 | 11 |
| purpose | 1.70 | 11 | 4 |
| nil | 1.70 | 11 | 4 |
| oban | 1.65 | 6 | 1 |
| sort | 1.65 | 6 | 1 |
| callback | 1.65 | 6 | 1 |
| admin | 1.65 | 6 | 1 |
| guard | 1.61 | 9 | 3 |
| todo | 1.61 | 9 | 3 |
| thoughts | 1.61 | 9 | 3 |
| needed | 1.61 | 24 | 14 |
| operation | 1.59 | 5 | 0 |
| enabled | 1.59 | 5 | 0 |
| free | 1.59 | 5 | 0 |
| tries | 1.59 | 5 | 0 |
| something | 1.58 | 57 | 42 |
| name | 1.55 | 44 | 31 |
| thinking | 1.54 | 13 | 6 |
| inside | 1.54 | 26 | 16 |
| shape | 1.53 | 7 | 2 |
| modal | 1.53 | 7 | 2 |
| big | 1.53 | 7 | 2 |
| operations | 1.52 | 10 | 4 |

| distinctive of SECOND | z | n first | n second |
|---|---|---|---|
| though | -3.48 | 3 | 26 |
| coverage | -2.55 | 4 | 18 |
| clear | -2.43 | 4 | 17 |
| may | -2.43 | 16 | 36 |
| method | -2.43 | 1 | 12 |
| refactor | -2.41 | 0 | 12 |
| failure | -2.27 | 3 | 14 |
| even | -2.22 | 12 | 28 |
| note | -2.14 | 3 | 13 |
| pray | -1.97 | 0 | 8 |
| mapping | -1.96 | 2 | 10 |
| thats | -1.96 | 2 | 10 |
| space | -1.96 | 2 | 10 |
| mix | -1.91 | 1 | 8 |
| idea | -1.86 | 6 | 16 |
| elixir | -1.85 | 3 | 11 |
| objects | -1.84 | 0 | 7 |
| scenarios | -1.84 | 0 | 7 |
| perfect | -1.84 | 0 | 7 |
| test | -1.83 | 50 | 74 |
| edge | -1.80 | 2 | 9 |
| changelog | -1.80 | 2 | 9 |
| validation | -1.79 | 9 | 20 |
| lovely | -1.76 | 1 | 7 |
| pretty | -1.76 | 1 | 7 |
| required | -1.76 | 1 | 7 |
| appear | -1.74 | 4 | 12 |
| question | -1.72 | 6 | 15 |
| fine | -1.72 | 8 | 18 |
| coming | -1.70 | 0 | 6 |
| resulting | -1.70 | 0 | 6 |
| vars | -1.70 | 0 | 6 |
| select | -1.70 | 0 | 6 |
| examples | -1.70 | 0 | 6 |
| edit | -1.68 | 3 | 10 |
| click | -1.68 | 3 | 10 |
| example | -1.64 | 7 | 16 |
| versions | -1.63 | 2 | 8 |
| factories | -1.63 | 2 | 8 |
| simpler | -1.63 | 2 | 8 |
| implemented | -1.58 | 1 | 6 |
| column | -1.58 | 1 | 6 |
| however | -1.58 | 1 | 6 |
| shows | -1.58 | 1 | 6 |
| points | -1.58 | 1 | 6 |
| date | -1.58 | 1 | 6 |
| easily | -1.58 | 1 | 6 |
| seen | -1.58 | 1 | 6 |
| task | -1.58 | 1 | 6 |
| fact | -1.58 | 1 | 6 |

## 9. Term co-occurrence clusters

Cosine similarity over binary term-document vectors, greedy expansion from the highest-degree unassigned term. Crude next to a topic model, but stdlib-only and deterministic, and its failure mode is obvious on reading. **These are co-occurrence groups, not named categories.**

| # | weight | co-occurring terms |
|---|---|---|
| 1 | 1763 | workflow, workflows, create, step, edit, save, project, run, click, job, trigger, user, button, page |
| 2 | 812 | work, order, hey, left |
| 3 | 688 | please, changelog, remove, update |
| 4 | 612 | test, coverage, tests, failing |
| 5 | 551 | different, url, error, path, runs |
| 6 | 472 | users, show, add, feature |
| 7 | 424 | panel, open, close, editor, canvas, input |
| 8 | 417 | function, call, functions |
| 9 | 346 | lightning, worker, send, set |
| 10 | 254 | never, state, read, string |
| 11 | 209 | current, approach, implementation |

## 10. Threads

Reply structure on inline comments, via `in_reply_to_id`.

| comments in thread | threads |
|---|---|
| 1 | 788 |
| 2 | 563 |
| 3 | 148 |
| 4 | 44 |
| 5 | 15 |
| 6 | 5 |
| 7 | 4 |
| 8 | 3 |
| 9 | 2 |

| measure | value |
|---|---|
| inline units total | 1721 |
| that are themselves replies | 300 |
| that drew a reply | 743 |
| reply rate | 43.2% |
| distinct threads (all raw comments) | 1572 |
| single-comment threads | 788 |

## 11. People

22 people reviewed at least one PR; 50 opened at least one.

**Pseudonymised.** Real logins are in the `.scratch/` dataset. Per-person counts in a committed file read as a performance table whatever caveat sits next to them, and these numbers track team composition, role and tenure per period rather than diligence. Run with `--named` locally if you need them.

| reviewer | PRs reviewed | % of relationships | cumulative % | PRs opened | inline comments | CHANGES_REQUESTED given |
|---|---|---|---|---|---|---|
| R01 | 611 | 26.3 | 26.3 | 239 | 511 | 83 |
| R02 | 554 | 23.8 | 50.2 | 416 | 84 | 200 |
| R03 | 281 | 12.1 | 62.2 | 450 | 261 | 40 |
| R04 | 277 | 11.9 | 74.2 | 285 | 163 | 70 |
| R05 | 144 | 6.2 | 80.4 | 137 | 272 | 37 |
| R06 | 132 | 5.7 | 86.1 | 128 | 189 | 6 |
| R07 | 78 | 3.4 | 89.4 | 0 | 4 | 11 |
| R08 | 68 | 2.9 | 92.3 | 0 | 2 | 2 |
| R09 | 63 | 2.7 | 95.0 | 87 | 71 | 11 |
| R10 | 32 | 1.4 | 96.4 | 21 | 11 | 7 |
| R11 | 27 | 1.2 | 97.6 | 77 | 51 | 10 |
| R12 | 25 | 1.1 | 98.7 | 130 | 92 | 5 |
| R13 | 7 | 0.3 | 99.0 | 6 | 1 | 0 |
| R14 | 5 | 0.2 | 99.2 | 12 | 5 | 0 |
| R15 | 5 | 0.2 | 99.4 | 0 | 0 | 0 |
| R16 | 4 | 0.2 | 99.6 | 0 | 0 | 0 |
| R17 | 3 | 0.1 | 99.7 | 1 | 0 | 0 |
| R18 | 2 | 0.1 | 99.8 | 35 | 0 | 0 |
| R19 | 2 | 0.1 | 99.9 | 9 | 0 | 0 |
| R20 | 1 | 0.0 | 99.9 | 3 | 2 | 1 |
| R21 | 1 | 0.0 | 100.0 | 0 | 2 | 0 |
| R22 | 1 | 0.0 | 100.0 | 0 | 0 | 0 |

## 12. Labels, milestones, branches

| label | PRs |
|---|---|
| Sandboxes v2 | 4 |
| bug | 3 |
| Community Contribution 🏅 | 3 |
| security | 2 |
| unplanned | 2 |
| AI-First Starting UX | 2 |
| performance | 1 |
| AI | 1 |
| Collab Editor | 1 |
| chore | 1 |
| v2.19.0 | 1 |

| base branch | PRs |
|---|---|
| main | 1911 |
| release-0.10.0 | 37 |
| nodes-and-edges-release | 22 |
| feature/collections | 10 |
| 4848-ai-first-starting-ux-parent | 9 |
| channels | 8 |
| farhan/manual-run-component-2 | 7 |
| 3123-free-node-positioning | 7 |
| webhook-security-feature | 6 |
| ai-assistant-for-all | 6 |
| sandbox-devx | 6 |
| release-2.18.0 | 6 |

## 13. Outcomes

| measure | value |
|---|---|
| merged | 1868 (86.8%) |
| closed unmerged | 231 (10.7%) |
| still open | 52 |
| open and in draft | 10 |
| self-merged (of merged) | 32.1% |
| from a fork | 56 |

## 14. Known limits

Carried here so this file stands alone:

- **Review rounds over-count.** A reviewer leaving eight inline comments in one pass
  is one round; returning three times is three.
- **Pending reviews are invisible** — written but never submitted.
- **Deleted comments and reviews leave no trace**, so counts drift upward over time
  relative to what a live reader sees. 3 of 2,235 PRs already disagree with their own
  `review_comments` counter by 1.
- **`draft` is current state.** A PR opened as a draft and later marked ready is
  indistinguishable from one never drafted, so draft adoption over time is not
  measurable here. Needs the timeline API.
- **AI-assisted reviews are invisible.** Reviewer identities are essentially all human
  accounts, but a review drafted with AI help and posted under a person's account
  cannot be separated. Several sampled 2025–2026 bodies read as AI-assisted. Weakens
  any claim about *how review style has changed recently*.
- **Size includes generated churn** (`mix.lock`, `package-lock.json`).
- **Path attribution is attention, not change** — not normalised by area modification
  rate.
- **`closed_unmerged` mixes superseded, spiked and abandoned work**, which the dataset
  cannot separate.
- **The snapshot is not transactional.** Phases ran at different instants, so an
  actively-updating open PR can be marginally inconsistent across files.

