# PR history

Tools for looking at our own code review process in aggregate: scrape the full
pull-request history of a GitHub repo, induce the structure of the review
feedback in it, and render the quantitative shape of the process as markdown.

Built to answer one question — *what do our reviewers keep asking for, and which
of those asks are preventable?* — with the throughput numbers as context rather
than as the point.

Nothing here is needed for everyday development.

## Requirements

`python3` 3.9 or newer and a `GITHUB_TOKEN` (or `GH_TOKEN`) with read access to
the repo. **No `pip install`, no virtualenv, no `requirements.txt`** — everything
is standard library. Python is deliberately *not* added to `.tool-versions` or
`bin/bootstrap`: one analysis tool doesn't justify making every Lightning
developer provision a Python toolchain.

## The scripts

| | |
|---|---|
| `scrape.py` | fetch → newline-delimited JSON + CSV in `.scratch/pr-history/` |
| `textutil.py` | code-stripping and credential screening. Imported, not run. |
| `discover.py` | induce structure from the corpus: vocabulary, contrasts, clusters |
| `categories.py` | the taxonomy **derived** from that induction, plus its counts |
| `analyze.py` | the quantitative process report, markdown to stdout |
| `REPORT-lightning.md` | the written findings, 2026-09 |

```bash
tooling/pr-history/scrape.py --limit 25      # smoke run: ~53 requests, ~10s
tooling/pr-history/scrape.py                 # full run: ~4,600 requests, ~10min
tooling/pr-history/scrape.py --verify        # re-check a dataset, no fetching
tooling/pr-history/scrape.py --spot-check 5111,5100

tooling/pr-history/discover.py                          # the inductive pass
tooling/pr-history/discover.py --sample 300 --sample-out /tmp/sample.json
tooling/pr-history/categories.py --examples 3           # derived taxonomy + counts
tooling/pr-history/categories.py --probe "please rename this"
tooling/pr-history/analyze.py > /tmp/analysis.md        # process metrics
tooling/pr-history/analyze.py --named        # adds per-person tables (local only)
```

**Start with `--limit 25`.** See the rate limit section — you get roughly one
full run per hour, so iterate against the smoke set.

## Output

Everything lands in `.scratch/pr-history/<owner>-<repo>/`, which is already
gitignored via `.scratch/` (`.gitignore:98`). The dataset is **never committed** —
see PII below. `--limit` writes to a `smoke/` subdirectory so it can't clobber a
real dataset.

```
pulls.ndjson            one trimmed PR per line
reviews.ndjson          one review per line, carrying pr_number
review_comments.ndjson  inline code comments, with path + truncated diff_hunk
issue_comments.ndjson   conversation comments, filtered to PRs
pulls.csv               one row per PR, flattened + derived metrics
state.json              watermark + completed numbers (the resume point)
manifest.json           run metadata + verification results
cache/                  one file per URL: ETag + body
```

## The rate limit, which shapes everything

`GET /rate_limit` reports a limit of 15,000/hr. **It is lying** — every real
response header reports `X-RateLimit-Limit: 5550`, and the headers are what gets
enforced. A cold full run is ~4,600 requests, so it consumes ~83% of a single
window.

Consequences worth internalising before you run anything:

- Iterate with `--limit 25`, never against the full set.
- The on-disk cache and ETag revalidation are load-bearing, not an optimisation.
  A `304 Not Modified` costs **zero** rate-limit budget, so a warm re-run is
  nearly free. ETag stability is high on merged PRs and low on actively-updating
  open ones, which is exactly the right way round.
- A killed run resumes from the cache at no budget cost. Just re-run it.

Two environment quirks are handled in the code and documented there, because both
cost real debugging time:

- GitHub's `Link` headers hand back **numeric repo-ID URLs**
  (`/repositories/454419290/pulls?...`). Claude Code web sessions serve only the
  `/repos/{owner}/{repo}/...` form and 403 the numeric one, so every crawl dies on
  page 2 unless the URL is rewritten. `normalize_url()` does that.
- GraphQL and `/search/*` are both blocked in those sessions. That is why reviews
  are fetched per PR (no repo-wide reviews endpoint exists) and why the PR count
  is verified by parsing `Link rel="last"` rather than reading a search
  `total_count`.

## Method: the categories are induced, not assumed

The obvious way to analyse review feedback is to write down the categories you
expect — tests, naming, error handling, and so on — and count keyword matches.
**Don't.** That only measures how good your guess was; the frame decides the
finding, and anything genuinely distinctive about how this team reviews stays
invisible.

So `textutil.py` contains no categories, only what holds regardless of what the
corpus says. `discover.py` then induces structure three ways:

- **vocabulary** — the words, bigrams and trigrams that actually occur;
- **contrast** — log-odds ratio with an informative Dirichlet prior (Monroe,
  Colaresi & Quinn 2008) across *structural* slices: `CHANGES_REQUESTED` vs
  `APPROVED` review bodies, inline code comments vs conversation, comments that
  drew a reply vs those that didn't. Raw frequency would just return the commonest
  English words in both slices; this returns what is **distinctive**, with a
  z-score so rare-term noise falls away;
- **structure** — term co-occurrence clustering, so groups form from how reviewers
  actually pair concepts.

Plus a reading sample stratified **structurally** (kind, review state, length,
era) and never by topic — topic is the thing being discovered.

Categories get named by reading that output, and written down afterwards in
`categories.py` as a result. Its header records the provenance: which pass and
which sample produced them. Any count that follows naming is a directional lower
bound, since a reviewer writing *"this'll blow up on nil"* is making a
failure-mode request that no keyword list catches.

Read [REPORT-lightning.md](REPORT-lightning.md) for what this actually found. The
short version: formal change requests here are mostly acceptance testing rather
than code critique, and the asks people comply with silently are exactly the ones
a machine could make.

The single highest-leverage line in the whole pipeline is `prose_of()`, which
strips fenced code, quoted lines, inline code and URLs before any analysis.
Without it, every comment that merely quotes a `Repo.all/1` call scores as a
database comment and the output is noise.

## PII and secrets

- Only `login` is kept for people. Emails, avatars, gravatar IDs and user IDs are
  dropped.
- **No endpoint called here returns an email address**, so emails never enter the
  dataset by construction rather than by scrubbing. Don't add `/users/{login}` or
  the commits endpoints without revisiting that.
- Comment and review **bodies are retained** — a meta-analysis of what reviewers
  ask for is a content analysis, so dropping them would defeat the purpose. They
  stay in gitignored `.scratch/` and are never committed.
- `textutil.screen()` gates what may be **quoted**: any comment matching a
  credential, token, key, JWT or email pattern is excluded from quotation while
  still counting toward every total. People do paste stack traces, tokens and
  customer detail into review threads.
- `diff_hunk` is truncated to 400 characters — enough to tell what a comment is
  about, without mirroring the source tree into the dataset.
- The committed report stays **aggregate**: reviewer load appears as a
  distribution, never a named leaderboard. `analyze.py --named` prints per-person
  tables for local use only.

## Metric definitions

All computed in `derive_row()` in `scrape.py`. If you change one, change both.

- **churn** = `additions + deletions`. Buckets: XS ≤10, S ≤50, M ≤250, L ≤1000, XL >1000.
- **first review** = earliest non-author review submission or non-author inline
  comment. Self-review never starts the clock.
- **hours to first review** is null, not zero, when a PR was never reviewed.
- **review rounds** = distinct non-author review submissions in `{APPROVED,
  CHANGES_REQUESTED, COMMENTED}`. This over-counts against intuition: a reviewer
  leaving eight inline comments in one pass is one round, but returning three
  times is three.
- **bot-authored** = author type `Bot`, or a login ending in `[bot]`.
- **percentiles** return nothing below 5 samples rather than an invented number.
- **path attribution** comes from the `path` on inline review comments, so it
  describes *reviewed* areas, not *changed* areas.

## Known limits

Stated here rather than discovered later:

- **PR size includes generated churn.** `mix.lock` and `package-lock.json` count
  toward additions/deletions, so an XL PR is sometimes a dependency bump. The
  per-PR files endpoint is out of scope, so this cannot be corrected — only
  disclosed.
- **`draft` is current state.** A PR opened as a draft and marked ready is
  indistinguishable from one never drafted, so draft is reported only as a
  snapshot of currently-open PRs and never as adoption over time. Fixing it needs
  the timeline API.
- **Pending reviews are invisible.** A review written but never submitted does not
  appear.
- **Deleted comments and reviews leave no trace.** Incremental runs therefore
  drift upward on comment counts over time. `--full` is cheap thanks to ETags —
  run it monthly rather than trusting incremental forever.
- **The snapshot is not transactional.** Phases run at different instants, so an
  actively-updating open PR can be marginally inconsistent across files.
  `manifest.json` records this.
- **`closed_unmerged` mixes superseded, spiked and abandoned work**, which the
  dataset cannot separate. Read the rate, not individual PRs.
