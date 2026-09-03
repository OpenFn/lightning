#!/usr/bin/env python3
#
# categories.py — the change-request taxonomy, DERIVED from the corpus.
#
# Provenance, because it decides how much to trust this file: these categories
# were not chosen in advance. They were read off the output of discover.py --
# vocabulary, log-odds contrasts and co-occurrence clusters -- plus a manual read
# of ~110 units from a structurally stratified sample of the 4,282-unit corpus
# (all five years, all three feedback kinds, all four review states), on
# 2026-09-03. The patterns below are the phrasings actually observed, not
# phrasings imagined.
#
# The single most important thing this file is NOT: it is not the input to the
# analysis. An earlier draft of this work pre-specified ~15 plausible categories
# and counted keyword matches, which measures only how good the guess was --
# the frame decides the finding. Running that against this corpus would have
# produced a tidy table and missed the actual headline, which is that formal
# change requests here are mostly acceptance testing rather than code critique.
#
# WHAT THE COUNTS ARE WORTH
#   * Lower bounds, always. "this'll blow up on nil" is a failure-mode request no
#     pattern catches. Expect real prevalence above every number here.
#   * Multi-label. One comment can be naming AND abstraction AND test design.
#     Shares do not sum to 100%.
#   * Precision over recall. Patterns are deliberately narrow: a category is more
#     useful as "at least this often" than as a fuzzy maximum.
#
# Usage:
#   tooling/pr-history/categories.py                    # counts, markdown
#   tooling/pr-history/categories.py --examples 3       # with quotable examples
#   tooling/pr-history/categories.py --probe "text"     # classify one string

import argparse
import json
import os
import re
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import textutil as T
import discover as D

# (key, label, what the read showed, patterns)
CATEGORIES = [
    ("acceptance_behaviour", "Acceptance testing — “I ran it and here's what I saw”",
     "The reviewer used the feature and reported observed behaviour. The single "
     "largest register in formal change requests, and invisible to any code-only "
     "reading of review data.",
     [r"\bi'?m (?:getting|seeing)\b", r"\bi (?:got|see|saw|noticed|observed)\b",
      r"\bwhen i \w+", r"\bdoesn'?t work\b", r"\bisn'?t working\b", r"\bnot working\b",
      r"\bstill (?:doesn'?t|isn'?t|not)\b", r"\bblank page\b", r"\bstrange behaviour\b",
      r"\bunable to\b", r"\bnot able to\b", r"\brenders?\b", r"\bi expect(?:ed)? to see\b",
      r"\bif i (?:attempt|try|click|enter)\b", r"\bi tried\b", r"\bno love\b",
      r"\bwasn'?t displayed\b", r"\bnot displayed\b", r"\bcan'?t (?:get|find)\b",
      r"\bsurprisingly difficult\b", r"\bwent through this\b", r"\bmanual tests?\b"]),

    ("abstraction_pushback", "Abstraction pushback — “justify this indirection”",
     "Not 'do X' but 'why did you do X'. The dominant inline register and the most "
     "distinctive thing about how this team reviews. No guideline covers it.",
     [r"\bdo we (?:really )?need\b", r"\bnot sure (?:this|that|it)\b",
      r"\bnot (?:100% )?sold\b", r"\bwhat was the rationale\b", r"\bwhy (?:did|do) you\b",
      r"\bis there a (?:specific )?reason\b", r"\bi (?:would|really) prefer\b",
      r"\bi'?d prefer\b", r"\bslippery slope\b", r"\blevel of abstraction\b",
      r"\bdon'?t see it as\b", r"\bwouldn'?t it (?:have been|be) better\b",
      r"\bi'?m wondering\b", r"\bfeels? (?:like )?(?:a )?(?:liability|confusing|strange|funky)\b",
      r"\bwhy not\b", r"\bnot gonna fight it\b", r"\bover-?engineer\w*\b",
      r"\bunnecessary\b", r"\bcan'?t (?:work out|find) how\b"]),

    ("correctness_failure_modes", "Correctness and failure modes",
     "Races, swallowed errors, unhandled clauses, nil paths, timeouts. Lower volume "
     "than the rest but the highest-severity findings in the corpus.",
     [r"\brace condition\b", r"\bconcurrent\w*\b", r"\bsilently\b", r"\bswallow\w*\b",
      r"\bwould raise\b", r"\bwill raise\b", r"\bno clause\b", r"\bnil\b",
      r"\bedge case\b", r"\bwhat happens if\b", r"\bwhat if\b", r"\bbounded timeout\b",
      r"\btimeout\b", r"\bbreak things\b", r"\bcrash\w*\b", r"\bfails? silently\b",
      r"\bnot discarded\b", r"\bdisappear\b", r"\bmissing mappings?\b",
      r"\bwe need to be (?:really )?careful\b", r"\bfoot ?gun\b"]),

    ("naming", "Naming",
     "Renames of functions, variables and env vars. The most ARGUED-ABOUT category: "
     "'rename' and 'naming' are strongly distinctive of threads that drew a reply.",
     [r"\bplease rename\b", r"\bcan we rename\b", r"\brenam\w+\b", r"\bnaming\b",
      r"\bcall (?:it|the variable|this)\b", r"\bname the variable\b",
      r"\bbetter name\b", r"\bterminology\b", r"\beasier to read\b",
      r"\bprefix\b", r"\bmore explicit\b", r"\btypo\b"]),

    ("test_design", "Test design — level and placement, not presence",
     "Distinct from 'add a test'. Reviewers argue about whether a test proves what it "
     "claims and whether it sits at the right level. Not covered by any guideline.",
     [r"\bdoesn'?t prove\b", r"\bthis doesn'?t prove\b", r"\btoo many tests\b",
      r"\bbetter place to test\b", r"\bdeep integration test\w*\b",
      r"\bown test case\b", r"\bmove this into\b", r"\bassertion for every\b",
      r"\bnot a specific change request\b", r"\btest request\b",
      r"\bmix (?:these )?counts up\b", r"\bnot tested\b", r"\bno .{0,20}scenario tested\b"]),

    ("test_missing", "Missing tests and coverage",
     "The mechanical 'add a test' ask. Accepted without argument — 'test', 'coverage' "
     "and 'changelog' are all distinctive of threads that drew NO reply.",
     [r"\badd (?:a |some |the )?tests?\b", r"\bplease add tests?\b",
      r"\bneeds? tests?\b", r"\bcoverage\b", r"\buncover this error\b",
      r"\bfailing test\b", r"\bfix (?:up )?the tests?\b", r"\bno live tests\b",
      r"\bcover (?:at least )?the\b", r"\bbump up your test\b"]),

    ("data_model_migrations", "Data model, migrations and queries",
     "Ecto schemas, migration structure, query shape. No guideline covers any of it.",
     [r"\bmigrations?\b", r"\bchangeset\b", r"\brepo\.\w+", r"\becto\b",
      r"\bpreload\w*\b", r"\bvirtual field\b", r"\bunique constraint\b",
      r"\bmulti\b", r"\btransaction\b", r"\bschema\b", r"\bone by one\b",
      r"\bbatch(?:es|ing)?\b", r"\bquery\b", r"\bindex(?:es|ed)?\b", r"\bcast\b"]),

    ("changelog", "Changelog",
     "Purely mechanical and entirely recurring across all five years. The clearest "
     "automation candidate in the dataset.",
     [r"\bchangelog\b"]),

    ("diff_hygiene", "Diff hygiene — unrelated changes and leftovers",
     "Formatter noise, files that shouldn't be in the PR, commented-out code, "
     "'residue'. Reviewers spending attention on things a check could catch.",
     [r"\bdoesn'?t seem related\b", r"\bnot related to (?:the|this) pr\b",
      r"\bunintentional\b", r"\bauto-?generated\b", r"\bplease revert\b",
      r"\brevert these\b", r"\bcommented[- ]out code\b", r"\bresidue\b",
      r"\bleftover\b", r"\bplease remove this file\b", r"\bre-?ordered\b",
      r"\bmakes the review harder\b", r"\breview your code before\b",
      r"\bno longer (?:needed|used)\b", r"\bshould be deleted\b"]),

    ("scope_ownership", "Scope and ownership — wrong place for this work",
     "Belongs in another repo, another service, or another PR. Rare but expensive: "
     "it lands after the work is done.",
     [r"\bshould be in \w+ rather than\b", r"\bdoesn'?t belong in\b",
      r"\bmake more sense in\b", r"\bsplit(?:ting)? (?:this )?out\b",
      r"\bseparate branch\b", r"\bout of scope\b", r"\bfollow-?up issue\b",
      r"\btrack this in an issue\b", r"\bsimplifies this pr\b",
      r"\bdidn'?t mean for this to be implemented\b"]),

    ("observability", "Logging and observability",
     "Asks to make a failure visible in logs or Sentry.",
     [r"\blogger\.\w+", r"\bprint something to the logs?\b", r"\bin the logs?\b",
      r"\bsentry\b", r"\blog level\b", r"\bstringif\w+\b", r"\bwe do want to know\b"]),

    ("routing_only", "Routing only — “see my comments below”",
     "The review body carries no substance; it points at inline comments. Matters "
     "because counting review bodies alone would badly misread this corpus.",
     [r"^.{0,240}$"]),  # gated in classify(): short AND pointing at comments
]

_ROUTING = re.compile(
    r"\b(?:left|added|made|i'?ve got|see|address|check) (?:a few |some |my |the |two |one )?"
    r"(?:comments?|notes?|questions?|suggestions?|observations?|change requests?|points?)\b"
    r"|\bcomments? below\b|\bdown below\b|\bwhat do you think\b|\baddress each comment\b",
    re.I)

_COMPILED = [(k, lbl, desc, [re.compile(p, re.I) for p in pats])
             for k, lbl, desc, pats in CATEGORIES if k != "routing_only"]
LABELS = {k: lbl for k, lbl, _, _ in CATEGORIES}
DESCRIPTIONS = {k: d for k, _, d, _ in CATEGORIES}
KEYS = [k for k, _, _, _ in CATEGORIES]


def classify(text):
    """Category keys matching this text. Multi-label; operates on prose only."""
    prose = T.prose_of(text)
    hits = {k for k, _lbl, _d, pats in _COMPILED if any(p.search(prose) for p in pats)}
    # Routing-only is structural: short, points at comments, says nothing else.
    stripped = " ".join(prose.split())
    if len(stripped) <= 240 and _ROUTING.search(stripped) and not (hits - {"naming"}):
        hits.add("routing_only")
    return hits


def main(argv=None):
    ap = argparse.ArgumentParser(description="Apply the derived taxonomy to the corpus.")
    ap.add_argument("--input", default=None)
    ap.add_argument("--examples", type=int, default=0,
                    help="show N quotable examples per category (PII-screened)")
    ap.add_argument("--probe", default=None)
    args = ap.parse_args(argv)

    if args.probe:
        print("prose      :", T.prose_of(args.probe).strip())
        print("categories :", sorted(classify(args.probe)) or "none")
        print("screen     :", T.screen(args.probe) or "clean (quotable)")
        return 0

    input_dir = args.input or os.path.join(
        D.repo_root(), ".scratch", "pr-history", "openfn-lightning")
    units = D.build_units(D.load(input_dir))
    if not units:
        sys.stderr.write("no dataset at %s\n" % input_dir)
        return 2

    for u in units:
        u["cats"] = classify(u["body"])

    cr = [u for u in units if u["state"] == "CHANGES_REQUESTED"]
    inline = [u for u in units if u["kind"] == "inline"]
    replied = [u for u in inline if u.get("got_reply")]

    print("# Derived taxonomy: counts\n")
    print("Categories were read off the corpus (see the header of `categories.py`). "
          "Every number is a **lower bound**, and comments are multi-label, so "
          "columns do not sum to 100%.\n")

    rows = []
    for k in KEYS:
        n_cr = sum(1 for u in cr if k in u["cats"])
        n_in = sum(1 for u in inline if k in u["cats"])
        n_rep = sum(1 for u in replied if k in u["cats"])
        rows.append([LABELS[k].split(" — ")[0], n_cr,
                     "%.0f%%" % (100.0 * n_cr / len(cr)) if cr else "-",
                     n_in, "%.0f%%" % (100.0 * n_in / len(inline)) if inline else "-",
                     "%.0f%%" % (100.0 * n_rep / n_in) if n_in else "-"])
    rows.sort(key=lambda r: -r[3])
    print(D.md_table(["category", "in change requests", "share of %d" % len(cr),
                      "in inline comments", "share of %d" % len(inline),
                      "of those, drew a reply"], rows))
    print()

    print("## What each category is\n")
    for k in KEYS:
        print("- **%s** — %s" % (LABELS[k], DESCRIPTIONS[k]))
    print()

    if args.examples:
        print("## Examples\n")
        print("_PII-screened: any comment matching a credential, token or email "
              "pattern is excluded from quotation while still counting above._\n")
        for k in KEYS:
            if k == "routing_only":
                continue
            pool = [u for u in units if k in u["cats"] and not u["flags"]
                    and 60 < len(u["prose"]) < 400]
            pool.sort(key=lambda u: -len(u["prose"]))
            step = max(1, len(pool) // max(1, args.examples))
            print("### %s\n" % LABELS[k])
            for u in pool[::step][:args.examples]:
                print("> %s\n" % " ".join(u["prose"].split())[:320])
            print()
    return 0


if __name__ == "__main__":
    sys.exit(main())
