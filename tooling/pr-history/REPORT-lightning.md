# What our reviewers actually ask for

An analysis of every pull request in `OpenFn/lightning`: 2,235 PRs opened between
2022-02-09 and 2026-09-02, carrying 4,312 reviews and 4,282 units of human review
feedback. Snapshot taken 2026-09-03.

Regenerate with `tooling/pr-history/scrape.py` then `analyze.py`, `discover.py`
and `categories.py`. See [README](README.md) for method and limits.

**This measures process, not people.** Review counts track team composition, role
and tenure in each period. Nothing here supports a judgement about anyone's
diligence, and it should not be used in a performance conversation.

---

## The five things worth knowing

1. **Formal change requests are mostly acceptance testing, not code critique.**
   The largest identifiable register in `CHANGES_REQUESTED` bodies is a reviewer
   running the feature and reporting what they saw. Code-level craft feedback
   lives somewhere else entirely: inline comments.
2. **The asks people comply with silently are exactly the ones a machine could
   make.** Changelog and missing-test asks draw a reply 18-19% of the time
   against a 43% baseline. Naming, abstraction and diff-hygiene asks draw one
   62-85% of the time.
3. **Review coverage regressed sharply in 2026.** Merged-without-any-review held
   at 11-17% through 2024 and 2025, then roughly doubled to 30% in 2026-Q2 and
   33% in Q3. Time to first review and time to merge moved the same way.
4. **PR size predicts how hard review will be, but not whether it happens.**
   An XL PR takes 3.1 review rounds and 5.3 days to merge against 1.5 rounds and
   10 hours for an XS. Yet 25% of XL PRs get no review at all, statistically
   indistinguishable from the 30% of XS PRs.
5. **Three reviewers carry 62% of all review.** Twenty-two people have reviewed
   something; five of them account for 80%.

---

## How these categories were arrived at

This matters for how much to trust the rest, so it goes near the top.

The first version of this analysis pre-specified about fifteen plausible
categories (tests, naming, error handling, Ecto, authorization, performance...)
and counted keyword matches. That approach was abandoned, because it only
measures how good the initial guess was. The frame decides the finding, and
running it here would have produced a tidy table while missing the actual
headline in point 1 above.

What replaced it: `discover.py` induces structure from the corpus three ways.
Vocabulary frequency over 4,282 units; a log-odds ratio with an informative
Dirichlet prior contrasting structural slices of the corpus against each other;
and term co-occurrence clustering. Then a manual read of ~110 units from a
sample stratified by *structure* (feedback kind, review state, comment length,
year) and deliberately not by topic, since topic was the thing being discovered.

The categories in `categories.py` were written down after that read, as an output.
Every count below is a **lower bound**: a reviewer writing *"this'll blow up on
nil"* is making a failure-mode request that no pattern catches. Comments are
multi-label, so shares do not sum to 100%.

---

## Finding 1: two registers, and they don't overlap

The corpus contains two kinds of feedback that barely share a vocabulary.

Contrasting `CHANGES_REQUESTED` review bodies against `APPROVED` ones, the terms
most distinctive of change requests are: *button, image, input, run, github, user,
link, panel, step, error, retry, email, trigger, page, silently, select, edit,
hover, settings*. That is not the vocabulary of code review. It is the vocabulary
of someone clicking through a feature.

Reading them confirms it. Change request bodies are full of things like *"I'm
getting this if I attempt to change my email but don't get my current password
right"*, *"when you enter the security tab URL it renders this blank page"*,
*"the save button still doesn't disable"*, *"I found this UI surprisingly
difficult to understand at first, even knowing the platform well"*.

Contrast inline code comments against PR conversation comments instead and the
vocabulary flips entirely: *function, call, module, avoid, functions, instead,
remove, calling, changeset, query, move, pattern, name, variable, struct, return*.
That is code review.

| category | in change requests | share of 483 | in inline comments | share of 1,721 | drew a reply |
|---|---|---|---|---|---|
| Data model, migrations, queries | 35 | 7% | 157 | 9% | 53% |
| Acceptance testing | 84 | **17%** | 86 | 5% | 57% |
| Naming | 26 | 5% | 68 | 4% | 62% |
| Abstraction pushback | 12 | 2% | 62 | 4% | **69%** |
| Correctness and failure modes | 25 | 5% | 59 | 3% | 56% |
| Missing tests and coverage | 20 | 4% | 32 | 2% | **19%** |
| Diff hygiene | 6 | 1% | 13 | 1% | **85%** |
| Changelog | 29 | 6% | 11 | 1% | **18%** |
| Scope and ownership | 6 | 1% | 11 | 1% | 45% |
| Logging and observability | 4 | 1% | 10 | 1% | 40% |
| Routing only ("see my comments below") | 26 | 5% | 10 | 1% | 30% |
| Test design (level, not presence) | 3 | 1% | 9 | 1% | 56% |

Two practical consequences. First, any measurement of review quality built only
on review states would conclude this team mostly does manual QA, which is false.
Second, 5% of change request bodies are *pure routing*, saying only "I've left
some comments below" with no content of their own, so review-body text alone is a
poor proxy for review substance.

### The most distinctive thing about how this team reviews

The dominant inline register is not "do X". It is "justify why you did X":

> Do we really need the icon to be dynamic like this? It feels like a slippery
> slope going this route.

> What was the rationale behind moving this into a different function? Function
> components are functions as well, and since nothing else is calling directly
> besides this component I don't see it as a good reason to abstract it.

> Not sure this level of abstraction is necessary, but not gonna fight it.

This category has the highest contest rate of any substantive one (69%), and no
guideline anywhere in the repo speaks to it. It is worth naming because it is
mostly healthy: it is a team defending against speculative indirection. But it is
also the feedback most likely to arrive *after* the work is done, when it is
expensive to act on.

---

## Finding 2: compliance and contest are cleanly separated

The baseline reply rate on an inline comment is 43% (743 of 1,721 drew a reply).
Sorting categories against that baseline splits them neatly:

**Complied with silently** (well below baseline)
- Changelog, 18%
- Missing tests and coverage, 19%

**Argued about** (well above baseline)
- Diff hygiene, 85%
- Abstraction pushback, 69%
- Naming, 62%
- Acceptance findings, 57%; correctness, 56%; test design, 56%; data model, 53%

The independent log-odds contrast agrees without being asked to. Terms
distinctive of threads that drew *no* reply: *coverage, refactor, method, note,
changelog, edge, validation, test, mix*. Terms distinctive of threads that *did*:
*rename, naming, cast, ecto, index, row, hash, structure, nil, map*.

This is the most useful result in the report. The feedback people accept without
discussion is mechanical and rule-shaped. The feedback people argue about is
judgement about design and data modelling, which is what senior review time is
actually for. Right now both are delivered the same way, by a person, after the
work is finished.

---

## Finding 3: review coverage regressed in 2026

27% of the 2,151 human-authored PRs received no review at all: no approval, no
change request, not one inline comment from anybody but the author. 384 of those
were merged anyway.

The headline number is less interesting than the trend, and the trend needed one
check before it could be trusted. A recent PR might simply not have been reviewed
*yet*, which would manufacture a fake regression. So the table below counts only
**merged** PRs, which are settled: an unreviewed merged PR will never be reviewed.

| quarter | merged PRs | merged with zero review | share |
|---|---|---|---|
| 2024-Q4 | 120 | 20 | 17% |
| 2025-Q1 | 104 | 6 | 6% |
| 2025-Q2 | 109 | 18 | 17% |
| 2025-Q3 | 77 | 13 | 17% |
| 2025-Q4 | 217 | 24 | 11% |
| 2026-Q1 | 110 | 18 | 16% |
| 2026-Q2 | 120 | 36 | **30%** |
| 2026-Q3 (partial) | 45 | 15 | **33%** |

The regression is real, not an artifact. Latency moved the same way in the same
period: median time to first review had sat between 6 and 20 hours since 2023,
and is 32h in 2026-Q1 and 39h in Q2. Median time to merge went from 18-27 hours
to 2.6 and 2.8 days, with a 2026-Q2 p90 of 30 days.

Throughput did not collapse to explain it, so the most likely reading is review
capacity under strain rather than fewer changes. Worth noting alongside: 32% of
all merged PRs were merged by their own author.

---

## Finding 4: size predicts effort, not coverage

| size | PRs | mean rounds | p90 rounds | share drawing a change request | median to merge |
|---|---|---|---|---|---|
| XS (≤10 lines) | 194 | 1.5 | 2.0 | 6% | 10h |
| S (≤50) | 308 | 1.6 | 3.0 | 14% | 19h |
| M (≤250) | 482 | 1.9 | 4.0 | 22% | 28h |
| L (≤1000) | 364 | 2.6 | 5.0 | 39% | 3.6d |
| XL (>1000) | 218 | 3.1 | 7.0 | 44% | 5.3d |

Every column moves monotonically with size. An XL PR is seven times more likely
to draw a change request than an XS one and takes thirteen times longer to merge.

But the share receiving *no review at all* is flat: 30% for XS, 30% for S, 25% for
M, 27% for L, 25% for XL. Whatever decides that a PR gets looked at, it is not
how much of the system it changes.

One caveat that cannot be corrected here: size is `additions + deletions`, which
includes `mix.lock` and `package-lock.json` churn, so some XL rows are dependency
bumps rather than large human changes. The per-PR files endpoint was out of scope.

---

## Finding 5: where review attention lands

| path prefix | inline comments |
|---|---|
| `lib/lightning` | 548 |
| `lib/lightning_web` | 506 |
| `assets/js` | 272 |
| `test/lightning` | 136 |
| `test/lightning_web` | 57 |
| `priv/repo` | 40 |
| `CHANGELOG.md` | 28 |
| `config/runtime.exs` | 22 |

Backend and web get near-identical attention; the frontend gets about half.
Tests do get reviewed: 221 inline comments land on paths under `test/`, 13% of
all inline comments, which is worth knowing given how often "add a test" appears
as an ask. (The table lists only the largest prefixes; `test/support`,
`test/integration` and `test/mix` make up the remainder.)

This is where attention *goes*, not where change goes: it is not normalised by how
often each area is modified. A quiet area may be well understood or may be
unwatched, and this table cannot tell you which.

---

## Which of these asks are preventable

Mapping the induced categories against what the repo already documents. The
guideline inventory is real: 12 files in `.claude/guidelines/` and 2 in
`.claude/rules/`, covering testing, E2E, store structure, Yjs/Yex, supervision
trees, toasts, logging and UI patterns.

| recurring ask | already written down? | verdict |
|---|---|---|
| Changelog | PR template checkbox, **no CI check** | Automate. See below. |
| Diff hygiene (unrelated files, formatter noise, leftovers) | no | Partly automatable |
| Missing tests / coverage | yes, `testing-essentials.md` + 5 more | Compliance, not documentation |
| Data model, migrations, queries | **nothing at all** | Biggest documentation gap |
| Naming | no | Judgement; a principle might help |
| Abstraction pushback | no | Judgement; irreducible, and mostly healthy |
| Test design (level and placement) | partly; guidelines cover *how*, not *which level* | Real gap |
| Correctness and failure modes | only via the `security-reviewer` agent's remit | Invisible when the agent doesn't run |
| Acceptance findings | `e2e-testing.md` + 3 E2E guides exist | Not a docs problem at all |

Three things stand out.

**The changelog ask is fully mechanical and completely unautomated.** It appears
29 times in change requests across all five years. The PR template already has
*"I have updated the changelog"* as a checkbox, and there is no CI check behind
it. One review comment in the corpus reads, in full: *"Please update the
changelog, you marked it as done on the checklist."* A CI job that fails when a
PR touches `lib/` without touching `CHANGELOG.md` would end this category, and
its 18% reply rate says nobody would argue.

**Data modelling is the largest inline category and has no guideline.** 157
inline comments and 35 change requests concern Ecto schemas, migration structure
and query shape, more than any other category, and there is nothing written down
about any of it. The specific asks recur: collapse several migrations touching one
table into one, don't do inserts one at a time inside something shaped like a
batch, move validation inside the `Multi` so check-and-insert share a transaction.
That last one caught a real race condition. This is the highest-value thing to
write down.

**Acceptance findings are not a documentation gap, and shouldn't be treated as
one.** 17% of change requests are a reviewer discovering behaviour by using the
feature. More prose will not fix that. Either the author tests their own change
before requesting review, or the E2E suite covers the path. The E2E guidance
already exists, so the gap is in what gets written, not in knowing how.

---

## What I'd actually do

In order of return on effort:

1. **Add a changelog CI check.** Smallest change here with a guaranteed effect,
   and the data says it will not be resisted.
2. **Write the missing Ecto/migrations guideline.** Largest category, zero
   coverage, and the recurring asks are specific enough to write down today.
   Source material is in the corpus.
3. **Work out what happened to review coverage in 2026.** Merged-without-review
   doubled and latency rose together. That is a capacity or routing question,
   and it is the finding most likely to matter beyond code review.
4. **Decide deliberately whether large PRs should get guaranteed review.** Right
   now an XL PR is as likely to go unreviewed as a one-line one, while costing 3x
   the rounds when it is reviewed. That looks unintentional rather than chosen.
5. **Leave abstraction pushback and naming alone.** They are 62-69% contested
   because they are genuine judgement, and they read as a healthy team norm. The
   only thing worth changing is *when* they arrive: earlier, on the approach,
   rather than after the implementation.

---

## What this analysis cannot tell you

- **Nothing about code quality.** It measures what reviewers said, not whether
  they were right, and not whether the code was good.
- **AI-assisted reviews are invisible.** Reviewer identities are essentially all
  human accounts (only `copilot-pull-request-reviewer[bot]`, with 5 reviews, and
  `Copilot`, with 8 comments, are agent identities), but a review drafted with AI
  assistance and posted under a person's account cannot be distinguished. Several
  sampled 2025-2026 review bodies read as AI-assisted. Any claim about *how
  review has changed recently* is weakened by this, which is why the 2026 finding
  above rests on coverage and latency rather than on comment style.
- **Review rounds over-count.** A reviewer leaving eight inline comments in one
  pass is one round; returning three times is three.
- **Pending reviews are invisible**, and deleted comments leave no trace.
- **Draft adoption is unmeasurable** from this data: `draft` is current state, so
  a PR opened as a draft and marked ready is indistinguishable from one never
  drafted. 10 of the 52 currently-open PRs are in draft, and that is all this
  dataset supports saying.
- **Categories are lower bounds**, per the method note. Treat every percentage as
  "at least this often".
