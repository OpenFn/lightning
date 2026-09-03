#!/usr/bin/env python3
#
# analyze.py — the quantitative shape of the review process, as markdown.
#
# Deliberately separate from discover.py and from the scrape: this reads only the
# on-disk dataset, imports no network code, and writes to stdout, so the report
# can be regenerated any number of times without touching the API or the
# rate-limit window. Redirecting into a file stays a human step.
#
# What this does NOT do is categorise review feedback. What reviewers ask for is
# induced in discover.py and named by reading; imposing categories here would put
# the conclusion in the tool.
#
# Every table that can mislead carries its caveat inline, in the output, where a
# reader will actually see it -- not in an appendix nobody reaches. Two that
# matter most:
#   * additions/deletions include mix.lock and package-lock.json churn, so "XL"
#     is often a dependency bump. The per-PR files endpoint is out of scope, so
#     this CANNOT be corrected -- only disclosed.
#   * `draft` is CURRENT state. A PR opened as a draft and marked ready reads as
#     never-draft. Only the timeline API can fix that, so draft is reported only
#     as "open PRs currently in draft" and never as adoption over time.
#
# Usage:
#   tooling/pr-history/analyze.py > report.md
#   tooling/pr-history/analyze.py --named          # add per-person tables
#   tooling/pr-history/analyze.py --include-bots
#   tooling/pr-history/analyze.py --input .scratch/pr-history/openfn-lightning/smoke

import argparse
import csv
import json
import os
import statistics
import subprocess
import sys
from datetime import datetime

MIN_SAMPLE = 5   # below this, percentiles are fabrication


def repo_root():
    try:
        return subprocess.check_output(["git", "rev-parse", "--show-toplevel"],
                                       stderr=subprocess.DEVNULL).decode().strip()
    except (subprocess.CalledProcessError, OSError):
        return os.getcwd()


def read_csv(path):
    with open(path, newline="") as fh:
        rows = list(csv.DictReader(fh))
    for r in rows:
        for k in ("number", "additions", "deletions", "churn", "changed_files",
                  "commits", "n_reviews", "n_review_rounds", "n_approvals",
                  "n_change_requests", "n_review_comments", "n_issue_comments",
                  "n_comments_total", "n_reviewers"):
            r[k] = int(r[k]) if r.get(k) not in (None, "") else None
        for k in ("hours_to_first_review", "hours_to_merge", "hours_to_close",
                  "hours_open_total"):
            r[k] = float(r[k]) if r.get(k) not in (None, "") else None
        for k in ("merged", "still_open", "closed_unmerged", "self_merged",
                  "draft_now", "bot_authored", "from_fork", "touches_backend",
                  "touches_frontend", "touches_tests"):
            r[k] = r.get(k) == "True"
    return rows


def read_ndjson(path):
    if not os.path.exists(path):
        return []
    with open(path) as fh:
        return [json.loads(l) for l in fh if l.strip()]


# ------------------------------------------------------------------- formatting

def md_table(headers, rows):
    out = ["| " + " | ".join(headers) + " |",
           "|" + "|".join("---" for _ in headers) + "|"]
    for r in rows:
        out.append("| " + " | ".join("" if c is None else str(c) for c in r) + " |")
    return "\n".join(out)


def pct(values, q):
    """Percentile with a small-n guard: None rather than an invented number.

    This bites on the early-2022 quarters, which is exactly when it should.
    """
    vals = [v for v in values if v is not None]
    if len(vals) < MIN_SAMPLE:
        return None
    if len(vals) == 1:
        return vals[0]
    cuts = statistics.quantiles(vals, n=100, method="inclusive")
    return round(cuts[min(q, 99) - 1], 1)


def fmt_h(v):
    """Hours, rendered at human resolution."""
    if v is None:
        return "-"
    if v < 48:
        return "%.0fh" % v
    return "%.1fd" % (v / 24.0)


def bar(v, vmax, width=28):
    if not vmax:
        return ""
    return "█" * max(1, int(round(width * v / vmax))) if v else ""


def quarter(iso_date):
    if not iso_date:
        return ""
    y, m = int(iso_date[:4]), int(iso_date[5:7])
    return "%d-Q%d" % (y, (m - 1) // 3 + 1)


def half(iso_date):
    if not iso_date:
        return ""
    y, m = int(iso_date[:4]), int(iso_date[5:7])
    return "%d-H%d" % (y, 1 if m <= 6 else 2)


def share(n, d):
    return "%.0f%%" % (100.0 * n / d) if d else "-"


# ---------------------------------------------------------------------- sections

def section_scope(rows, all_rows, data, input_dir):
    bots = [r for r in all_rows if r["bot_authored"]]
    dates = sorted(r["created_at"][:10] for r in all_rows if r["created_at"])
    out = ["## Scope and method\n"]
    out.append(
        "Every PR in the repository, scraped from the GitHub REST API. "
        "%d pull requests opened between %s and %s. "
        "Bot-authored PRs (%d, %s of the total) are **excluded** from everything "
        "below unless a table says otherwise, because they merge on different "
        "rules and would distort every review metric.\n"
        % (len(all_rows), dates[0] if dates else "?", dates[-1] if dates else "?",
           len(bots), share(len(bots), len(all_rows))))
    out.append(
        "**This measures process, not people and not code quality.** Review counts "
        "reflect team composition, role and tenure in each period. Nothing here "
        "supports a judgement about an individual's diligence or output, and it "
        "should not be used in a performance conversation.\n")
    manifest = os.path.join(input_dir, "manifest.json")
    if os.path.exists(manifest):
        m = json.load(open(manifest))
        out.append(
            "Snapshot taken %s. Phases run at different instants, so an "
            "actively-updating open PR can be marginally inconsistent across "
            "files; %d PRs are still open and their metrics are live.\n"
            % (m.get("finished_at", "?"), sum(1 for r in all_rows if r["still_open"])))
    return "\n".join(out)


def section_review_coverage(rows):
    """The loudest number in the dataset, so it gets decomposed before it is used."""
    out = ["## How much review actually happens\n"]
    total = len(rows)
    unreviewed = [r for r in rows if r["n_reviews"] == 0]
    merged_unreviewed = [r for r in unreviewed if r["merged"]]
    out.append(
        "Of %d human-authored PRs, **%d (%s) received no review at all** — no "
        "approval, no change request, not one inline comment from anybody but the "
        "author. %d of those were merged anyway.\n"
        % (total, len(unreviewed), share(len(unreviewed), total), len(merged_unreviewed)))

    rows_by_q = {}
    for r in rows:
        rows_by_q.setdefault(quarter(r["created_at"]), []).append(r)
    trend = []
    for q in sorted(k for k in rows_by_q if k):
        g = rows_by_q[q]
        nr = sum(1 for r in g if r["n_reviews"] == 0)
        trend.append([q, len(g), nr, share(nr, len(g)),
                      bar(nr / len(g) if g else 0, 1.0, 20)])
    out.append("\n" + md_table(["quarter", "PRs", "unreviewed", "share", ""], trend))
    out.append(
        "\n_The trend matters more than the headline: a high unreviewed share in "
        "2022, when the team was small, means something different from the same "
        "share today._\n")

    sizes = {}
    for r in rows:
        if r["n_reviews"] == 0 and r["size_bucket"]:
            sizes[r["size_bucket"]] = sizes.get(r["size_bucket"], 0) + 1
    allsizes = {}
    for r in rows:
        if r["size_bucket"]:
            allsizes[r["size_bucket"]] = allsizes.get(r["size_bucket"], 0) + 1
    order = ["XS", "S", "M", "L", "XL"]
    out.append("\nUnreviewed PRs by size — the question is whether big changes slip through too:\n")
    out.append(md_table(["size", "PRs", "unreviewed", "share"],
                        [[s, allsizes.get(s, 0), sizes.get(s, 0),
                          share(sizes.get(s, 0), allsizes.get(s, 0))] for s in order
                         if allsizes.get(s)]))
    return "\n".join(out)


def section_change_requests(rows):
    out = ["## Change requests\n"]
    total = len(rows)
    reviewed = [r for r in rows if r["n_reviews"] > 0]
    withcr = [r for r in rows if r["n_change_requests"] > 0]
    out.append(
        "%d of %d reviewed PRs (%s) drew at least one formal CHANGES_REQUESTED "
        "review; %s of all human PRs. Formal change requests are a floor, not a "
        "count of asks — most feedback in this repo arrives as inline comments on "
        "a COMMENTED review, which carries no state.\n"
        % (len(withcr), len(reviewed), share(len(withcr), len(reviewed)),
           share(len(withcr), total)))

    by_q = {}
    for r in reviewed:
        by_q.setdefault(quarter(r["created_at"]), []).append(r)
    rows_out = []
    for q in sorted(k for k in by_q if k):
        g = by_q[q]
        n = sum(1 for r in g if r["n_change_requests"] > 0)
        rows_out.append([q, len(g), n, share(n, len(g))])
    out.append("\n" + md_table(["quarter", "reviewed PRs", "with change request", "share"], rows_out))

    out.append("\n### Review rounds against PR size\n")
    out.append("Does this team find big PRs harder to converge? Rounds = distinct "
               "non-author review submissions.\n")
    buckets = {}
    for r in reviewed:
        if r["size_bucket"]:
            buckets.setdefault(r["size_bucket"], []).append(r)
    order = ["XS", "S", "M", "L", "XL"]
    rows_out = []
    for s in order:
        g = buckets.get(s)
        if not g:
            continue
        rounds = [r["n_review_rounds"] for r in g]
        crs = sum(1 for r in g if r["n_change_requests"] > 0)
        rows_out.append([s, len(g), "%.1f" % (sum(rounds) / len(rounds)),
                         pct([float(x) for x in rounds], 90) or "-",
                         share(crs, len(g)),
                         fmt_h(pct([r["hours_to_merge"] for r in g], 50))])
    out.append(md_table(["size", "PRs", "mean rounds", "p90 rounds",
                         "share with change request", "median time to merge"], rows_out))
    out.append("\n_Size here is `additions + deletions`, which includes lockfile and "
               "generated-file churn. An XL row is sometimes a dependency bump rather "
               "than a large human change, and the dataset cannot separate them._\n")
    return "\n".join(out)


def section_latency(rows):
    out = ["## Time to first review, and to merge\n"]
    out.append("First review = the earliest review submission or inline comment "
               "from anyone other than the author. Self-review does not start the clock.\n")
    by_q = {}
    for r in rows:
        by_q.setdefault(quarter(r["created_at"]), []).append(r)
    rows_out = []
    for q in sorted(k for k in by_q if k):
        g = by_q[q]
        ttfr = [r["hours_to_first_review"] for r in g if r["hours_to_first_review"] is not None]
        ttm = [r["hours_to_merge"] for r in g if r["hours_to_merge"] is not None]
        rows_out.append([q, len(g), len(ttfr),
                         fmt_h(pct(ttfr, 50)), fmt_h(pct(ttfr, 90)),
                         fmt_h(pct(ttm, 50)), fmt_h(pct(ttm, 90))])
    out.append(md_table(["quarter", "PRs", "reviewed", "p50 to review", "p90 to review",
                         "p50 to merge", "p90 to merge"], rows_out))
    out.append("\n_Blank cells mean fewer than %d samples in that quarter — reported as "
               "absent rather than as a number. Two biases cannot be corrected from this "
               "dataset: a PR opened as a draft starts its clock at creation even though "
               "nobody was asked to look yet, which inflates the tail; and a review left "
               "pending (written, never submitted) is invisible._\n" % MIN_SAMPLE)
    return "\n".join(out)


def section_reviewers(rows, named):
    out = ["## Who reviews\n"]
    load = {}
    for r in rows:
        for rev in (r["reviewers"] or "").split("|"):
            if rev:
                load[rev] = load.get(rev, 0) + 1
    if not load:
        return "\n".join(out + ["_No reviewer data._\n"])
    ranked = sorted(load.items(), key=lambda kv: -kv[1])
    total_reviews = sum(load.values())
    out.append("%d distinct people reviewed at least one PR. Concentration:\n" % len(ranked))
    cum, marks = 0, []
    for i, (_who, n) in enumerate(ranked, 1):
        cum += n
        if i in (1, 3, 5, 10) or i == len(ranked):
            marks.append(["top %d" % i, share(cum, total_reviews)])
    out.append(md_table(["reviewers", "share of all PR-review relationships"], marks))
    out.append("\n_Reported as a distribution rather than a leaderboard on purpose. "
               "The dataset in `.scratch/` keeps logins if you need to slice it; "
               "`--named` prints per-person tables locally._\n")
    if named:
        out.append("\n### Per-reviewer load (local only — not for publication)\n")
        out.append(md_table(["reviewer", "PRs reviewed"],
                            [[w, n] for w, n in ranked[:40]]))
    return "\n".join(out)


def section_paths(rows, rcs, pulls):
    out = ["## Where the comments land\n"]
    counts, prs_touching = {}, {}
    for c in rcs:
        p = c.get("path") or ""
        if not p:
            continue
        key = "/".join(p.split("/")[:2]) if "/" in p else p
        counts[key] = counts.get(key, 0) + 1
        prs_touching.setdefault(key, set()).add(c["pr_number"])
    ranked = sorted(counts.items(), key=lambda kv: -kv[1])[:20]
    vmax = ranked[0][1] if ranked else 0
    out.append(md_table(["path prefix", "inline comments", "PRs", "comments per PR", ""],
                        [[k, n, len(prs_touching[k]),
                          "%.1f" % (n / len(prs_touching[k])),
                          bar(n, vmax)] for k, n in ranked]))
    out.append("\n_This is where review **attention** goes, which is not the same as "
               "where change goes: it is normalised by PRs commented on, not by PRs that "
               "touched the area, because the per-PR files endpoint is out of scope. A "
               "large area with few comments may be well-understood or may be unwatched — "
               "this table cannot tell you which._\n")
    return "\n".join(out)


def section_outcomes(rows):
    out = ["## Outcomes\n"]
    total = len(rows)
    merged = sum(1 for r in rows if r["merged"])
    closed_unmerged = sum(1 for r in rows if r["closed_unmerged"])
    still_open = sum(1 for r in rows if r["still_open"])
    decided = merged + closed_unmerged
    out.append(md_table(["outcome", "PRs", "share of all", "share of decided"], [
        ["merged", merged, share(merged, total), share(merged, decided)],
        ["closed unmerged", closed_unmerged, share(closed_unmerged, total),
         share(closed_unmerged, decided)],
        ["still open", still_open, share(still_open, total), "-"],
    ]))
    selfm = sum(1 for r in rows if r["self_merged"])
    out.append("\n%s of merged PRs were merged by their own author.\n"
               % share(selfm, merged))
    out.append("\n_Closed-unmerged mixes superseded, spiked and abandoned work, which "
               "this dataset cannot distinguish. Read the rate, not the individual PRs._\n")

    out.append("\n### Longest-lived PRs\n")
    for label, pool in (("merged", [r for r in rows if r["merged"]]),
                        ("closed without merging", [r for r in rows if r["closed_unmerged"]])):
        top = sorted(pool, key=lambda r: -(r["hours_open_total"] or 0))[:10]
        out.append("\n**%s**\n" % label)
        out.append(md_table(["PR", "title", "open for", "reviews", "size"],
                            [["#%d" % r["number"], r["title"][:58],
                              fmt_h(r["hours_open_total"]), r["n_reviews"],
                              r["size_bucket"]] for r in top]))
    return "\n".join(out)


def section_drafts(rows):
    open_rows = [r for r in rows if r["still_open"]]
    drafts = [r for r in open_rows if r["draft_now"]]
    out = ["## Open drafts\n"]
    out.append("%d of %d currently-open PRs are in draft.\n"
               % (len(drafts), len(open_rows)))
    out.append("\n_Reported only as a snapshot of open PRs. `draft` is current state, "
               "so a PR opened as a draft and later marked ready is indistinguishable "
               "from one never drafted — which makes any claim about draft adoption over "
               "time unsupportable from this dataset. It would need the timeline API._\n")
    return "\n".join(out)


def section_volume(rows, named):
    out = ["## Discussion volume\n"]
    by_q = {}
    for r in rows:
        by_q.setdefault(quarter(r["created_at"]), []).append(r)
    rows_out = []
    for q in sorted(k for k in by_q if k):
        g = by_q[q]
        rc = [float(r["n_review_comments"]) for r in g]
        ic = [float(r["n_issue_comments"]) for r in g]
        rows_out.append([q, len(g), "%.1f" % (sum(rc) / len(g)), pct(rc, 90) or "-",
                         "%.1f" % (sum(ic) / len(g))])
    out.append(md_table(["quarter", "PRs", "mean inline comments",
                         "p90 inline", "mean conversation comments"], rows_out))
    out.append("\n_Bot and GitHub-App comments are already excluded from the "
               "conversation column; CI and coverage bots otherwise dominate it._\n")
    return "\n".join(out)


def section_throughput(rows, all_rows):
    out = ["## Throughput\n"]
    opened, merged = {}, {}
    for r in rows:
        q = quarter(r["created_at"])
        if q:
            opened[q] = opened.get(q, 0) + 1
        if r["merged_at"]:
            mq = quarter(r["merged_at"])
            merged[mq] = merged.get(mq, 0) + 1
    quarters = sorted(set(opened) | set(merged))
    vmax = max(list(opened.values()) + [1])
    rows_out = [[q, opened.get(q, 0), merged.get(q, 0), bar(opened.get(q, 0), vmax)]
                for q in quarters]
    out.append(md_table(["quarter", "opened", "merged", ""], rows_out))
    now_q = quarter(datetime.utcnow().strftime("%Y-%m-%d"))
    if quarters and quarters[-1] == now_q:
        out.append("\n_%s is incomplete — it is the quarter this snapshot was taken in._\n" % now_q)
    return "\n".join(out)


def section_definitions():
    return """## Appendix: how each number is computed

Every figure traces to `derive_row()` in `scrape.py`; this is that function in prose.

- **churn** = `additions + deletions`. Size buckets: XS ≤10, S ≤50, M ≤250, L ≤1000, XL >1000.
- **first review** = earliest of any non-author review submission or non-author inline
  comment. Self-review is excluded throughout.
- **hours to first review** is null, not zero, when a PR was never reviewed.
- **review rounds** = distinct non-author review submissions in {APPROVED,
  CHANGES_REQUESTED, COMMENTED}. This over-counts relative to intuition: each batch of
  inline comments submits one review object, so a reviewer leaving eight comments in one
  pass counts as one round, but a reviewer returning three times counts as three.
- **reviewers** = the set of non-author logins who submitted a review or an inline comment.
- **bot-authored** = author type `Bot`, or a login ending in `[bot]`.
- **self-merged** = `merged_by` equals the author.
- **percentiles** return nothing below %d samples rather than an invented value.
- **path attribution** comes from the `path` on inline review comments, so it describes
  reviewed areas, not changed areas. The per-PR files endpoint was out of scope.
""" % MIN_SAMPLE


def main(argv=None):
    ap = argparse.ArgumentParser(description="Render the PR-history analysis as markdown.")
    ap.add_argument("--input", default=None)
    ap.add_argument("--named", action="store_true",
                    help="include per-person tables (local use; not for the committed report)")
    ap.add_argument("--include-bots", action="store_true")
    args = ap.parse_args(argv)

    input_dir = args.input or os.path.join(
        repo_root(), ".scratch", "pr-history", "openfn-lightning")
    csv_path = os.path.join(input_dir, "pulls.csv")
    if not os.path.exists(csv_path):
        sys.stderr.write("no dataset at %s -- run scrape.py first\n" % input_dir)
        return 2

    all_rows = read_csv(csv_path)
    rows = all_rows if args.include_bots else [r for r in all_rows if not r["bot_authored"]]
    data = {"rcs": read_ndjson(os.path.join(input_dir, "review_comments.ndjson")),
            "pulls": read_ndjson(os.path.join(input_dir, "pulls.ndjson"))}

    print("# OpenFn Lightning: how code review actually works here\n")
    for part in (
        section_scope(rows, all_rows, data, input_dir),
        section_review_coverage(rows),
        section_change_requests(rows),
        section_latency(rows),
        section_volume(rows, args.named),
        section_paths(rows, data["rcs"], data["pulls"]),
        section_reviewers(rows, args.named),
        section_throughput(rows, all_rows),
        section_outcomes(rows),
        section_drafts(rows),
        section_definitions(),
    ):
        print(part)
        print()
    return 0


if __name__ == "__main__":
    sys.exit(main())
