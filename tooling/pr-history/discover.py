#!/usr/bin/env python3
#
# discover.py — derive the structure of the review corpus FROM the corpus.
#
# This exists because the alternative is worse. Writing down a list of categories
# you expect reviewers to care about, then counting matches, tells you only how
# good your guess was: the frame decides the finding. With thousands of review
# comments in hand the categories should be induced, so this script does three
# things and asserts nothing:
#
#   1. VOCABULARY  -- what words and phrases actually occur, by frequency.
#   2. CONTRAST    -- which terms distinguish one slice of the corpus from
#                     another (change requests vs approvals; inline code comments
#                     vs conversation; contested threads vs one-and-done), using
#                     a log-odds ratio with an informative Dirichlet prior
#                     (Monroe, Colaresi & Quinn 2008). Raw frequency would just
#                     hand back the most common English words in both slices;
#                     this hands back what is DISTINCTIVE, with a z-score.
#   3. STRUCTURE   -- emergent groupings from term co-occurrence, so clusters
#                     form by how reviewers actually pair concepts.
#
# It then exports a stratified sample for a human to read. The categories get
# written down AFTER that read, as an output of the analysis rather than an input
# to it, and the report says which pass produced them.
#
# Usage:
#   tooling/pr-history/discover.py                      # full discovery report
#   tooling/pr-history/discover.py --top 60
#   tooling/pr-history/discover.py --sample 300 --sample-out sample.json
#   tooling/pr-history/discover.py --input .scratch/pr-history/openfn-lightning/smoke
#
# Output: markdown to stdout; the reading sample to --sample-out if given.

import argparse
import json
import math
import os
import random
import re
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import textutil as T

MIN_DF = 5          # a term must appear in this many comments to be considered
PRIOR_MASS = 1000.0  # a0 in the informative-Dirichlet prior


# ---------------------------------------------------------------------- loading

def read_ndjson(path):
    if not os.path.exists(path):
        return []
    with open(path) as fh:
        return [json.loads(l) for l in fh if l.strip()]


def repo_root():
    try:
        return subprocess.check_output(["git", "rev-parse", "--show-toplevel"],
                                       stderr=subprocess.DEVNULL).decode().strip()
    except (subprocess.CalledProcessError, OSError):
        return os.getcwd()


def load(input_dir):
    return {
        "pulls": read_ndjson(os.path.join(input_dir, "pulls.ndjson")),
        "reviews": read_ndjson(os.path.join(input_dir, "reviews.ndjson")),
        "rcs": read_ndjson(os.path.join(input_dir, "review_comments.ndjson")),
        "ics": read_ndjson(os.path.join(input_dir, "issue_comments.ndjson")),
    }


def is_bot(login, type_):
    return type_ == "Bot" or (login or "").endswith("[bot]")


def build_units(data):
    """One record per piece of human review feedback, with its provenance.

    A 'unit' is whatever a reviewer wrote: an inline code comment, a review
    summary body, or a conversation comment. Kept together so contrasts can be
    drawn between them rather than assumed away.
    """
    pulls = {p["number"]: p for p in data["pulls"]}
    units = []

    for r in data["reviews"]:
        if is_bot(r["reviewer"], r.get("reviewer_type")):
            continue
        body = (r.get("body") or "").strip()
        if not body:
            continue
        pr = pulls.get(r["pr_number"]) or {}
        if r["reviewer"] == pr.get("author"):
            continue  # self-review is not feedback
        units.append({
            "kind": "review_body", "state": r["state"], "author": r["reviewer"],
            "pr": r["pr_number"], "created_at": r.get("submitted_at") or "",
            "path": "", "thread_root": None, "in_reply": False,
            "body": body, "url": r.get("html_url") or "",
        })

    reply_targets = {c["in_reply_to_id"] for c in data["rcs"] if c.get("in_reply_to_id")}
    for c in data["rcs"]:
        if is_bot(c["author"], c.get("author_type")):
            continue
        body = (c.get("body") or "").strip()
        if not body:
            continue
        pr = pulls.get(c["pr_number"]) or {}
        if c["author"] == pr.get("author"):
            continue
        units.append({
            "kind": "inline", "state": "", "author": c["author"],
            "pr": c["pr_number"], "created_at": c.get("created_at") or "",
            "path": c.get("path") or "", "thread_root": c.get("in_reply_to_id"),
            "in_reply": bool(c.get("in_reply_to_id")),
            "got_reply": c["id"] in reply_targets,
            "body": body, "url": c.get("html_url") or "",
        })

    for c in data["ics"]:
        if is_bot(c["author"], c.get("author_type")) or c.get("via_github_app"):
            continue
        body = (c.get("body") or "").strip()
        if not body:
            continue
        pr = pulls.get(c["pr_number"]) or {}
        if c["author"] == pr.get("author"):
            continue
        units.append({
            "kind": "conversation", "state": "", "author": c["author"],
            "pr": c["pr_number"], "created_at": c.get("created_at") or "",
            "path": "", "thread_root": None, "in_reply": False,
            "body": body, "url": c.get("html_url") or "",
        })

    for u in units:
        u["prose"] = T.prose_of(u["body"]).strip()
        u["tokens"] = T.tokenize(u["prose"])
        u["has_suggestion"] = T.has_suggestion_block(u["body"])
        u["flags"] = T.screen(u["body"])
    return units


# ------------------------------------------------------------------- vocabulary

def count_terms(units, n=1):
    df, tf = {}, {}
    for u in units:
        grams = set(T.ngrams(u["tokens"], n)) if n > 1 else set(u["tokens"])
        for g in grams:
            df[g] = df.get(g, 0) + 1
        for g in (T.ngrams(u["tokens"], n) if n > 1 else u["tokens"]):
            tf[g] = tf.get(g, 0) + 1
    return tf, df


# --------------------------------------------------------------------- contrast

def log_odds(units_a, units_b, n=1, min_df=MIN_DF, prior_mass=PRIOR_MASS):
    """Log-odds ratio with an informative Dirichlet prior; returns [(term, z)].

    Raw frequency comparison is useless here -- 'should' is common in every
    slice. This weights each term by how surprising its imbalance is given the
    combined corpus, and the z-score makes rare-term noise fall away.
    """
    tf_a, df_a = count_terms(units_a, n)
    tf_b, df_b = count_terms(units_b, n)
    vocab = {t for t in set(tf_a) | set(tf_b)
             if (df_a.get(t, 0) + df_b.get(t, 0)) >= min_df}
    if not vocab:
        return []
    combined = {t: tf_a.get(t, 0) + tf_b.get(t, 0) for t in vocab}
    total_combined = sum(combined.values()) or 1
    n_a = sum(tf_a.get(t, 0) for t in vocab) or 1
    n_b = sum(tf_b.get(t, 0) for t in vocab) or 1

    out = []
    for t in vocab:
        a_i = prior_mass * combined[t] / total_combined
        y_a, y_b = tf_a.get(t, 0), tf_b.get(t, 0)
        num_a = y_a + a_i
        num_b = y_b + a_i
        den_a = n_a + prior_mass - num_a
        den_b = n_b + prior_mass - num_b
        if num_a <= 0 or num_b <= 0 or den_a <= 0 or den_b <= 0:
            continue
        delta = math.log(num_a / den_a) - math.log(num_b / den_b)
        var = 1.0 / num_a + 1.0 / num_b
        out.append((t, delta / math.sqrt(var), y_a, y_b))
    out.sort(key=lambda r: -r[1])
    return out


# -------------------------------------------------------------------- structure

def cooccurrence_clusters(units, vocab_size=220, min_df=MIN_DF, sim_floor=0.16, max_cluster=14):
    """Group terms by how often reviewers use them together.

    Cosine similarity over binary term-document vectors, then greedy expansion
    from the highest-degree unassigned term. Crude next to a topic model, but it
    is stdlib-only, deterministic, and its failure mode is obvious on reading --
    which for an inductive step matters more than sophistication.
    """
    _tf, df = count_terms(units, 1)
    terms = [t for t, c in sorted(df.items(), key=lambda kv: -kv[1]) if c >= min_df][:vocab_size]
    tset = set(terms)
    docs = [set(t for t in u["tokens"] if t in tset) for u in units]
    docs = [d for d in docs if d]

    postings = {t: set() for t in terms}
    for i, d in enumerate(docs):
        for t in d:
            postings[t].add(i)

    sims = {}
    for i, a in enumerate(terms):
        for b in terms[i + 1:]:
            inter = len(postings[a] & postings[b])
            if not inter:
                continue
            s = inter / math.sqrt(len(postings[a]) * len(postings[b]))
            if s >= sim_floor:
                sims.setdefault(a, []).append((b, s))
                sims.setdefault(b, []).append((a, s))

    for t in sims:
        sims[t].sort(key=lambda kv: -kv[1])

    assigned, clusters = set(), []
    for t in sorted(terms, key=lambda x: -len(sims.get(x, []))):
        if t in assigned or not sims.get(t):
            continue
        members = [t]
        assigned.add(t)
        for nb, _s in sims[t]:
            if nb not in assigned and len(members) < max_cluster:
                members.append(nb)
                assigned.add(nb)
        if len(members) > 2:
            clusters.append((members, sum(df[m] for m in members)))
    clusters.sort(key=lambda c: -c[1])
    return clusters, df


# ----------------------------------------------------------------------- sample

def stratified_sample(units, size, seed=17):
    """Spread the reading sample across state, kind, length, era and outcome.

    Reading the longest comments alone would caricature the corpus; reading a
    flat random sample would drown the rare-but-important in nits. Strata are
    structural (where a comment sits), never topical (what it says) -- topic is
    the thing being discovered.
    """
    rnd = random.Random(seed)

    def era(u):
        return (u["created_at"] or "")[:4]

    def length_band(u):
        n = len(u["prose"])
        return "short" if n < 120 else ("medium" if n < 400 else "long")

    buckets = {}
    for u in units:
        key = (u["kind"], u.get("state") or "-", length_band(u), era(u))
        buckets.setdefault(key, []).append(u)

    keys = sorted(buckets)
    picked, i = [], 0
    # Round-robin across strata so no single bucket dominates.
    while len(picked) < min(size, len(units)) and keys:
        key = keys[i % len(keys)]
        pool = buckets[key]
        if pool:
            picked.append(pool.pop(rnd.randrange(len(pool))))
        else:
            keys.remove(key)
            continue
        i += 1
    return picked


# ------------------------------------------------------------------------ report

def md_table(headers, rows):
    out = ["| " + " | ".join(headers) + " |",
           "|" + "|".join("---" for _ in headers) + "|"]
    for r in rows:
        out.append("| " + " | ".join(str(c) for c in r) + " |")
    return "\n".join(out)


def main(argv=None):
    ap = argparse.ArgumentParser(description="Induce structure from the review corpus.")
    ap.add_argument("--input", default=None)
    ap.add_argument("--top", type=int, default=45)
    ap.add_argument("--sample", type=int, default=0)
    ap.add_argument("--sample-out", default=None)
    args = ap.parse_args(argv)

    input_dir = args.input or os.path.join(
        repo_root(), ".scratch", "pr-history", "openfn-lightning")
    data = load(input_dir)
    if not data["pulls"]:
        sys.stderr.write("no dataset at %s -- run scrape.py first\n" % input_dir)
        return 2

    units = build_units(data)
    inline = [u for u in units if u["kind"] == "inline"]
    bodies = [u for u in units if u["kind"] == "review_body"]
    convo = [u for u in units if u["kind"] == "conversation"]
    cr = [u for u in bodies if u["state"] == "CHANGES_REQUESTED"]
    ap_ = [u for u in bodies if u["state"] == "APPROVED"]

    print("# Review corpus: inductive pass\n")
    print("Structure derived from the corpus, not imposed on it. Nothing below "
          "assumes what reviewers care about.\n")

    print("## Corpus\n")
    print(md_table(["slice", "units", "median chars", "with ```suggestion", "PII-flagged"], [
        [name, len(g),
         sorted(len(u["prose"]) for u in g)[len(g) // 2] if g else 0,
         sum(1 for u in g if u["has_suggestion"]),
         sum(1 for u in g if u["flags"])]
        for name, g in (("inline code comments", inline),
                        ("review summary bodies", bodies),
                        ("  of which CHANGES_REQUESTED", cr),
                        ("  of which APPROVED", ap_),
                        ("conversation comments", convo),
                        ("all human feedback", units))]))
    print()

    print("## 1. Vocabulary — what is actually said\n")
    for n, label in ((1, "words"), (2, "bigrams"), (3, "trigrams")):
        tf, df = count_terms(units, n)
        rows = [[t, df[t], tf[t]] for t, _ in
                sorted(df.items(), key=lambda kv: -kv[1])[:args.top] if df[t] >= MIN_DF]
        print("### Top %s\n" % label)
        print(md_table(["term", "comments", "occurrences"], rows))
        print()

    print("## 2. Contrast — what distinguishes one slice from another\n")
    print("Log-odds ratio with an informative Dirichlet prior; z-score, so rare-term "
          "noise falls away. Positive = distinctive of the first slice.\n")
    for label, a, b in (
        ("CHANGES_REQUESTED vs APPROVED review bodies", cr, ap_),
        ("inline code comments vs conversation comments", inline, convo),
        ("inline comments that drew a reply vs those that did not",
         [u for u in inline if u.get("got_reply")], [u for u in inline if not u.get("got_reply")]),
    ):
        if len(a) < 10 or len(b) < 10:
            print("### %s\n\n_skipped: %d vs %d units, too few._\n" % (label, len(a), len(b)))
            continue
        scored = log_odds(a, b)
        top = scored[:args.top]
        bottom = scored[-args.top:][::-1]
        print("### %s\n" % label)
        print("**Distinctive of the first slice** (%d units)\n" % len(a))
        print(md_table(["term", "z", "n first", "n second"],
                       [[t, "%.2f" % z, ya, yb] for t, z, ya, yb in top]))
        print("\n**Distinctive of the second slice** (%d units)\n" % len(b))
        print(md_table(["term", "z", "n first", "n second"],
                       [[t, "%.2f" % z, ya, yb] for t, z, ya, yb in bottom]))
        print()

    print("## 3. Structure — emergent term groupings\n")
    print("Cosine similarity over binary term-document vectors, greedy expansion. "
          "These are co-occurrence groups, NOT named categories: naming them is the "
          "job of the manual read.\n")
    clusters, df = cooccurrence_clusters(units)
    print(md_table(["#", "weight", "co-occurring terms"],
                   [[i + 1, w, ", ".join(m)] for i, (m, w) in enumerate(clusters[:22])]))
    print()

    print("## 4. Where comments land\n")
    areas = {}
    for u in inline:
        p = u["path"]
        if not p:
            continue
        top2 = "/".join(p.split("/")[:2]) if "/" in p else p
        areas[top2] = areas.get(top2, 0) + 1
    print(md_table(["path prefix", "inline comments"],
                   sorted(areas.items(), key=lambda kv: -kv[1])[:25]))
    print()

    if args.sample:
        sample = stratified_sample(units, args.sample)
        payload = [{k: u[k] for k in
                    ("kind", "state", "author", "pr", "created_at", "path", "url",
                     "in_reply", "has_suggestion", "flags", "prose")} for u in sample]
        if args.sample_out:
            with open(args.sample_out, "w") as fh:
                json.dump(payload, fh, indent=1, ensure_ascii=False)
            sys.stderr.write("wrote %d sampled units to %s\n" % (len(payload), args.sample_out))
        else:
            print("## Reading sample\n")
            for u in payload:
                print("- [%s/%s] #%s %s\n  %s\n" % (
                    u["kind"], u["state"] or "-", u["pr"], u["path"] or "",
                    u["prose"][:400].replace("\n", " ")))
    return 0


if __name__ == "__main__":
    sys.exit(main())
