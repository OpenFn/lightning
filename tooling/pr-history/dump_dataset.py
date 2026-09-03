#!/usr/bin/env python3
#
# dump_dataset.py — emit the corpus as raw aggregate tables in markdown, for
# someone else to analyse independently.
#
# The point of this file is to NOT be an analysis. REPORT-lightning.md argues a
# case; this dumps the distributions, time series, term lists and cross-tabs
# behind it so a reader can reach different conclusions without re-scraping
# 2,235 PRs or trusting our framing. Where a choice had to be made (a filter, a
# denominator, a cut-off) it is stated inline next to the table it affects.
#
# Reviewers are pseudonymised R01..Rnn. Real logins are in the .scratch/ dataset
# for anyone who needs them; this file is committed, and per-person review counts
# in a committed artifact read as a performance table whatever the caveat says.
#
# Usage:
#   tooling/pr-history/dump_dataset.py > tooling/pr-history/DATASET-lightning.md
#   tooling/pr-history/dump_dataset.py --top 80        # longer term lists
#   tooling/pr-history/dump_dataset.py --named         # real logins (local only)

import argparse
import collections
import csv
import json
import os
import statistics
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import textutil as T
import discover as D
import categories as C

SIZE_ORDER = ["XS", "S", "M", "L", "XL"]


def num(x):
    return float(x) if x not in ("", None) else None


def tbl(headers, rows):
    print("| " + " | ".join(headers) + " |")
    print("|" + "|".join("---" for _ in headers) + "|")
    for r in rows:
        print("| " + " | ".join("" if c is None else str(c) for c in r) + " |")
    print()


def q_of(d):
    y, m = int(d[:4]), int(d[5:7])
    return "%d-Q%d" % (y, (m - 1) // 3 + 1)


def stats(vals):
    v = sorted(x for x in vals if x is not None)
    if not v:
        return dict.fromkeys(("n", "min", "p25", "p50", "p75", "p90", "p99", "max", "mean"))
    def pc(p):
        return round(v[min(len(v) - 1, int(len(v) * p / 100))], 1)
    return {"n": len(v), "min": round(v[0], 1), "p25": pc(25), "p50": pc(50),
            "p75": pc(75), "p90": pc(90), "p99": pc(99), "max": round(v[-1], 1),
            "mean": round(sum(v) / len(v), 1)}


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--input", default=None)
    ap.add_argument("--top", type=int, default=50)
    ap.add_argument("--named", action="store_true")
    args = ap.parse_args(argv)

    d = args.input or os.path.join(D.repo_root(), ".scratch", "pr-history", "openfn-lightning")
    rows_all = list(csv.DictReader(open(os.path.join(d, "pulls.csv"))))
    for r in rows_all:
        for k in ("additions", "deletions", "churn", "changed_files", "commits",
                  "n_reviews", "n_review_rounds", "n_approvals", "n_change_requests",
                  "n_review_comments", "n_issue_comments", "n_reviewers"):
            r[k] = int(r[k]) if r[k] not in ("", None) else None
        for k in ("hours_to_first_review", "hours_to_merge", "hours_open_total"):
            r[k] = num(r[k])
    rows = [r for r in rows_all if r["bot_authored"] != "True"]
    data = D.load(d)
    units = D.build_units(data)
    for u in units:
        u["cats"] = C.classify(u["body"])
    inline = [u for u in units if u["kind"] == "inline"]
    bodies = [u for u in units if u["kind"] == "review_body"]
    convo = [u for u in units if u["kind"] == "conversation"]
    cr = [u for u in bodies if u["state"] == "CHANGES_REQUESTED"]
    appr = [u for u in bodies if u["state"] == "APPROVED"]
    replied = [u for u in inline if u.get("got_reply")]
    manifest = {}
    mpath = os.path.join(d, "manifest.json")
    if os.path.exists(mpath):
        manifest = json.load(open(mpath))

    print("# OpenFn Lightning PR corpus: raw aggregates\n")
    print("Companion to [REPORT-lightning.md](REPORT-lightning.md). That file argues a "
          "case; **this one does not**. It dumps the distributions, time series, term "
          "lists and cross-tabs underneath it so you can reach your own conclusions "
          "without re-scraping or adopting our framing.\n")
    print("Regenerate: `tooling/pr-history/dump_dataset.py > "
          "tooling/pr-history/DATASET-lightning.md`. The row-level dataset "
          "(`pulls.csv`, four `.ndjson` files including every comment body) lives in "
          "gitignored `.scratch/pr-history/openfn-lightning/` after a scrape.\n")

    print("## 0. Provenance and filters\n")
    print("Read this before using any number below.\n")
    tbl(["item", "value"], [
        ["repository", "OpenFn/lightning"],
        ["snapshot taken", manifest.get("finished_at", "?")],
        ["PRs in repo (all authors)", len(rows_all)],
        ["PRs, bot-authored", sum(1 for r in rows_all if r["bot_authored"] == "True")],
        ["**PRs used below unless stated**", "**%d human-authored**" % len(rows)],
        ["reviews (all, incl. bots + self)", len(data["reviews"])],
        ["inline review comments (all)", len(data["rcs"])],
        ["conversation comments on PRs (all)", len(data["ics"])],
        ["**feedback units used below**", "**%d**" % len(units)],
        ["requests made by the scrape", manifest.get("requests_made", "?")],
    ])
    print("The **feedback unit** is the analysis grain: one thing a reviewer wrote. "
          "Three filters build it, and each one changes the denominators:\n")
    print("1. bot and GitHub-App authors dropped (`codecov[bot]`, `github-actions[bot]`, "
          "`dependabot[bot]`, `copilot-pull-request-reviewer[bot]`);\n"
          "2. **self-review dropped** — a comment by the PR's own author is not feedback;\n"
          "3. empty bodies dropped (an approval with no text is a review, not a unit).\n")
    print("So `%d` inline units here vs `%d` raw inline comments in the dataset. Mixing "
          "the two denominators is the easiest mistake to make with this data.\n"
          % (len(inline), len(data["rcs"])))
    tbl(["slice", "units", "median chars", "p90 chars", "has ```suggestion", "PII-screened"],
        [[n, len(g), stats([len(u["prose"]) for u in g])["p50"],
          stats([len(u["prose"]) for u in g])["p90"],
          sum(1 for u in g if u["has_suggestion"]), sum(1 for u in g if u["flags"])]
         for n, g in (("inline code comments", inline), ("review summary bodies", bodies),
                      ("— CHANGES_REQUESTED", cr), ("— APPROVED", appr),
                      ("— COMMENTED", [u for u in bodies if u["state"] == "COMMENTED"]),
                      ("conversation comments", convo), ("all units", units))])

    print("## 1. Per-quarter time series\n")
    print("Every quarter, every metric, human-authored PRs. `unrev` counts PRs with zero "
          "non-author reviews AND zero non-author inline comments. Percentiles are "
          "suppressed below 5 samples.\n")
    qs = sorted({q_of(r["created_at"]) for r in rows if r["created_at"]})
    out = []
    for qq in qs:
        g = [r for r in rows if q_of(r["created_at"]) == qq]
        mg = [r for r in g if r["merged"] == "True"]
        rev = [r for r in g if r["n_reviews"] > 0]
        ttfr = stats([r["hours_to_first_review"] for r in g])
        ttm = stats([r["hours_to_merge"] for r in g])
        out.append([qq, len(g), len(mg),
                    sum(1 for r in g if r["closed_unmerged"] == "True"),
                    sum(1 for r in g if r["still_open"] == "True"),
                    sum(1 for r in g if r["n_reviews"] == 0),
                    sum(1 for r in mg if r["n_reviews"] == 0),
                    sum(1 for r in rev if r["n_change_requests"] > 0),
                    ttfr["p50"], ttfr["p90"], ttm["p50"], ttm["p90"],
                    round(sum(r["n_review_comments"] for r in g) / len(g), 2),
                    round(statistics.median([r["churn"] for r in g if r["churn"] is not None]), 0)])
    tbl(["quarter", "opened", "merged", "closed unmerged", "still open", "unrev",
         "unrev+merged", "with change req", "ttfr p50 h", "ttfr p90 h",
         "ttm p50 h", "ttm p90 h", "inline/PR", "median churn"], out)
    print("`unrev+merged` is the censoring-free series: a merged PR that went unreviewed "
          "will never be reviewed, whereas a recent open one still might. Use it, not "
          "`unrev`, for any trend claim near the snapshot date.\n")

    print("## 2. Per-month opened/merged\n")
    print("Finer grain for anyone wanting to place a change against a release or a "
          "team change. The final month is partial.\n")
    op = collections.Counter(r["created_month"] for r in rows if r["created_month"])
    mg = collections.Counter(r["merged_month"] for r in rows if r["merged_month"])
    months = sorted(set(op) | set(mg))
    tbl(["month", "opened", "merged"], [[m, op.get(m, 0), mg.get(m, 0)] for m in months])

    print("## 3. Size\n")
    print("`churn = additions + deletions`, which **includes `mix.lock` and "
          "`package-lock.json`**, so some XL rows are dependency bumps rather than large "
          "human changes. The per-PR files endpoint was out of scope, so this cannot be "
          "corrected here. Buckets: XS ≤10, S ≤50, M ≤250, L ≤1000, XL >1000.\n")
    out = []
    for s in SIZE_ORDER:
        g = [r for r in rows if r["size_bucket"] == s]
        rev = [r for r in g if r["n_reviews"] > 0]
        if not g:
            continue
        out.append([s, len(g), sum(1 for r in g if r["n_reviews"] == 0),
                    round(100.0 * sum(1 for r in g if r["n_reviews"] == 0) / len(g), 1),
                    round(sum(r["n_review_rounds"] for r in rev) / len(rev), 2) if rev else None,
                    round(100.0 * sum(1 for r in rev if r["n_change_requests"] > 0) / len(rev), 1) if rev else None,
                    stats([r["hours_to_first_review"] for r in g])["p50"],
                    stats([r["hours_to_merge"] for r in g])["p50"],
                    round(sum(r["n_review_comments"] for r in g) / len(g), 2),
                    round(sum(r["changed_files"] or 0 for r in g) / len(g), 1)])
    tbl(["size", "PRs", "unrev", "unrev %", "mean rounds (reviewed)", "% change req",
         "ttfr p50 h", "ttm p50 h", "inline/PR", "mean files"], out)

    print("### Continuous distributions\n")
    tbl(["metric", "n", "min", "p25", "p50", "p75", "p90", "p99", "max", "mean"],
        [[lbl] + [stats([r[k] for r in rows])[x] for x in
                  ("n", "min", "p25", "p50", "p75", "p90", "p99", "max", "mean")]
         for lbl, k in (("churn (lines)", "churn"), ("changed files", "changed_files"),
                        ("commits", "commits"), ("hours to first review", "hours_to_first_review"),
                        ("hours to merge", "hours_to_merge"), ("hours open total", "hours_open_total"),
                        ("inline comments", "n_review_comments"),
                        ("conversation comments", "n_issue_comments"),
                        ("reviews", "n_reviews"), ("review rounds", "n_review_rounds"),
                        ("distinct reviewers", "n_reviewers"))])

    print("## 4. Review states\n")
    st = collections.Counter(r["state"] for r in data["reviews"])
    tbl(["state", "reviews", "share"],
        [[k, v, "%.1f%%" % (100.0 * v / len(data["reviews"]))] for k, v in st.most_common()])
    print("By quarter, non-author reviews only:\n")
    out = []
    for qq in qs:
        prs = {int(r["number"]) for r in rows if q_of(r["created_at"]) == qq}
        g = [u for u in bodies if u["pr"] in prs]
        c = collections.Counter(u["state"] for u in g)
        out.append([qq, len(g), c.get("APPROVED", 0), c.get("CHANGES_REQUESTED", 0),
                    c.get("COMMENTED", 0), c.get("DISMISSED", 0)])
    tbl(["quarter", "bodies", "APPROVED", "CHANGES_REQUESTED", "COMMENTED", "DISMISSED"], out)

    print("## 5. Category cross-tab\n")
    print("Categories are **derived** from the corpus, not pre-specified — provenance in "
          "the header of `categories.py`. Multi-label, so columns do not sum to 100%. "
          "Every count is a **lower bound**; patterns favour precision over recall.\n")
    print("The reply-rate column is against a baseline of **%.1f%%** (%d of %d inline "
          "comments drew a reply). Below baseline = complied with silently; above = "
          "argued about.\n" % (100.0 * len(replied) / len(inline), len(replied), len(inline)))
    out = []
    for k in C.KEYS:
        ncr = sum(1 for u in cr if k in u["cats"])
        nin = sum(1 for u in inline if k in u["cats"])
        nrep = sum(1 for u in replied if k in u["cats"])
        ncv = sum(1 for u in convo if k in u["cats"])
        out.append([C.LABELS[k].split(" — ")[0], ncr, round(100.0 * ncr / len(cr), 1),
                    nin, round(100.0 * nin / len(inline), 1), ncv,
                    round(100.0 * nrep / nin, 1) if nin else None])
    out.sort(key=lambda r: -r[3])
    tbl(["category", "in CHANGES_REQUESTED", "%% of %d" % len(cr), "in inline",
         "%% of %d" % len(inline), "in conversation", "% drew a reply"], out)

    print("### Category by year (inline comments)\n")
    years = sorted({u["created_at"][:4] for u in inline if u["created_at"]})
    out = []
    for k in C.KEYS:
        row = [C.LABELS[k].split(" — ")[0]]
        for y in years:
            g = [u for u in inline if u["created_at"][:4] == y]
            n = sum(1 for u in g if k in u["cats"])
            row.append("%d (%.0f%%)" % (n, 100.0 * n / len(g)) if g else "")
        out.append(row)
    tbl(["category"] + years, out)

    print("## 6. Where comments land\n")
    print("Full distribution over two-level path prefixes, from the `path` on inline "
          "comments. This is where review **attention** went, not where change went: it "
          "is not normalised by how often each area was modified.\n")
    pc = collections.Counter()
    prs_touch = collections.defaultdict(set)
    for u in inline:
        p = u["path"]
        if not p:
            continue
        key = "/".join(p.split("/")[:2]) if "/" in p else p
        pc[key] += 1
        prs_touch[key].add(u["pr"])
    tbl(["path prefix", "inline comments", "%% of %d" % len(inline), "distinct PRs", "comments/PR"],
        [[k, v, round(100.0 * v / len(inline), 1), len(prs_touch[k]),
          round(v / len(prs_touch[k]), 2)] for k, v in pc.most_common()])
    print("Top individual files:\n")
    fc = collections.Counter(u["path"] for u in inline if u["path"])
    tbl(["file", "inline comments"], [[k, v] for k, v in fc.most_common(30)])

    print("## 7. Vocabulary\n")
    print("Code fences, quoted lines, raw HTML, markdown links and URLs are stripped "
          "before counting (`textutil.prose_of`). Without that step pasted screenshots "
          "put `img width alt src` at the top of this list. Structural stopwords removed; "
          "no topic words removed.\n")
    for n, label in ((1, "words"), (2, "bigrams"), (3, "trigrams")):
        tf, df = D.count_terms(units, n)
        print("### Top %d %s\n" % (args.top, label))
        tbl(["term", "units containing", "total occurrences"],
            [[t, df[t], tf[t]] for t, _ in sorted(df.items(), key=lambda kv: -kv[1])[:args.top]
             if df[t] >= D.MIN_DF])

    print("## 8. Log-odds contrasts\n")
    print("Log-odds ratio with an informative Dirichlet prior (Monroe, Colaresi & Quinn "
          "2008), reported as a z-score. Raw frequency would return the commonest English "
          "words in both slices; this returns what is **distinctive**. Slices are "
          "structural — no topical assumption is made anywhere in this section.\n")
    print("Positive z = distinctive of the first slice. Minimum document frequency %d.\n"
          % D.MIN_DF)
    for label, a, b in (("CHANGES_REQUESTED vs APPROVED review bodies", cr, appr),
                        ("inline code comments vs conversation comments", inline, convo),
                        ("inline comments that drew a reply vs those that did not",
                         replied, [u for u in inline if not u.get("got_reply")])):
        if len(a) < 10 or len(b) < 10:
            continue
        scored = D.log_odds(a, b)
        print("### %s\n" % label)
        print("%d vs %d units.\n" % (len(a), len(b)))
        tbl(["distinctive of FIRST", "z", "n first", "n second"],
            [[t, "%.2f" % z, ya, yb] for t, z, ya, yb in scored[:args.top]])
        tbl(["distinctive of SECOND", "z", "n first", "n second"],
            [[t, "%.2f" % z, ya, yb] for t, z, ya, yb in scored[-args.top:][::-1]])

    print("## 9. Term co-occurrence clusters\n")
    print("Cosine similarity over binary term-document vectors, greedy expansion from the "
          "highest-degree unassigned term. Crude next to a topic model, but stdlib-only "
          "and deterministic, and its failure mode is obvious on reading. **These are "
          "co-occurrence groups, not named categories.**\n")
    clusters, _df = D.cooccurrence_clusters(units)
    tbl(["#", "weight", "co-occurring terms"],
        [[i + 1, w, ", ".join(m)] for i, (m, w) in enumerate(clusters)])

    print("## 10. Threads\n")
    print("Reply structure on inline comments, via `in_reply_to_id`.\n")
    roots = collections.Counter()
    for c in data["rcs"]:
        roots[c["in_reply_to_id"] or c["id"]] += 1
    depths = collections.Counter(roots.values())
    tbl(["comments in thread", "threads"],
        [[k, depths[k]] for k in sorted(depths)][:15])
    tbl(["measure", "value"], [
        ["inline units total", len(inline)],
        ["that are themselves replies", sum(1 for u in inline if u["in_reply"])],
        ["that drew a reply", len(replied)],
        ["reply rate", "%.1f%%" % (100.0 * len(replied) / len(inline))],
        ["distinct threads (all raw comments)", len(roots)],
        ["single-comment threads", depths.get(1, 0)],
    ])

    print("## 11. People\n")
    load = collections.Counter()
    for r in rows:
        for x in (r["reviewers"] or "").split("|"):
            if x:
                load[x] += 1
    authored = collections.Counter(r["author"] for r in rows)
    ranked = load.most_common()
    alias = {w: ("%s" % w) if args.named else ("R%02d" % i)
             for i, (w, _) in enumerate(ranked, 1)}
    print("%d people reviewed at least one PR; %d opened at least one.\n"
          % (len(ranked), len(authored)))
    if not args.named:
        print("**Pseudonymised.** Real logins are in the `.scratch/` dataset. Per-person "
              "counts in a committed file read as a performance table whatever caveat sits "
              "next to them, and these numbers track team composition, role and tenure per "
              "period rather than diligence. Run with `--named` locally if you need them.\n")
    tot = sum(load.values())
    cum = 0
    out = []
    for w, n in ranked:
        cum += n
        out.append([alias[w], n, round(100.0 * n / tot, 1), round(100.0 * cum / tot, 1),
                    authored.get(w, 0),
                    sum(1 for u in inline if u["author"] == w),
                    sum(1 for u in cr if u["author"] == w)])
    tbl(["reviewer", "PRs reviewed", "% of relationships", "cumulative %", "PRs opened",
         "inline comments", "CHANGES_REQUESTED given"], out)

    print("## 12. Labels, milestones, branches\n")
    lc = collections.Counter()
    for r in rows:
        for l in (r["labels"] or "").split("|"):
            if l:
                lc[l] += 1
    tbl(["label", "PRs"], [[k, v] for k, v in lc.most_common(25)] or [["(none used)", 0]])
    bc = collections.Counter(r["base_ref"] for r in rows)
    tbl(["base branch", "PRs"], [[k, v] for k, v in bc.most_common(12)])
    print("## 13. Outcomes\n")
    merged = [r for r in rows if r["merged"] == "True"]
    tbl(["measure", "value"], [
        ["merged", "%d (%.1f%%)" % (len(merged), 100.0 * len(merged) / len(rows))],
        ["closed unmerged", "%d (%.1f%%)" % (sum(1 for r in rows if r["closed_unmerged"] == "True"),
                                             100.0 * sum(1 for r in rows if r["closed_unmerged"] == "True") / len(rows))],
        ["still open", sum(1 for r in rows if r["still_open"] == "True")],
        ["open and in draft", sum(1 for r in rows if r["still_open"] == "True" and r["draft_now"] == "True")],
        ["self-merged (of merged)", "%.1f%%" % (100.0 * sum(1 for r in merged if r["self_merged"] == "True") / len(merged))],
        ["from a fork", sum(1 for r in rows if r["from_fork"] == "True")],
    ])

    print("## 14. Known limits\n")
    print("""Carried here so this file stands alone:

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
""")
    return 0


if __name__ == "__main__":
    sys.exit(main())
