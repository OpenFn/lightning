#!/usr/bin/env python3
#
# textutil.py — text hygiene and safety screening for the review corpus.
#
# Deliberately contains NO semantic categories. Deciding up front what reviewers
# talk about would pre-commit the analysis to a guess and guarantee we only find
# what we already assumed; the categories are supposed to fall out of the corpus
# (see discover.py). What lives here is only the stuff that is true regardless of
# what the corpus turns out to say:
#
#   * prose_of()  -- strip code so we analyse what reviewers WROTE, not what they
#                    quoted. Without this, any comment quoting a Repo.all/1 call
#                    looks like a database comment. This is data hygiene, not
#                    interpretation, and it is the highest-leverage step here.
#   * screen()    -- credential/PII detection, a safety gate on what may be
#                    quoted in a published report.
#   * tokenize()/ngrams() -- plumbing for the inductive pass.

import re

# ------------------------------------------------------------------- hygiene

_FENCE = re.compile(r"```.*?```", re.S)
_INLINE_CODE = re.compile(r"`[^`\n]*`")
_QUOTED_LINE = re.compile(r"^\s*>.*$", re.M)
_URL = re.compile(r"https?://\S+")
_HTML_COMMENT = re.compile(r"<!--.*?-->", re.S)
_IMG = re.compile(r"!\[[^\]]*\]\([^)]*\)")
_SUGGESTION = re.compile(r"```suggestion", re.I)
_MENTION = re.compile(r"@[A-Za-z0-9-]+")
# GitHub comments are full of pasted screenshots as raw HTML, plus <details>
# wrappers. Left in, "img width alt image src" dominates the top bigrams and the
# vocabulary is worthless. Matches real tags only, so a stray "<-" survives.
_HTML_TAG = re.compile(r"</?[A-Za-z][^>]*>")
# Keep the visible text of a markdown link, drop the target.
_MD_LINK = re.compile(r"\[([^\]]*)\]\([^)]*\)")
_CHECKBOX = re.compile(r"^\s*[-*]\s*\[[ xX]\]", re.M)


def prose_of(text):
    """The human prose of a comment: code, quotes, URLs and images removed."""
    if not text:
        return ""
    t = _HTML_COMMENT.sub(" ", text)
    t = _FENCE.sub(" ", t)
    t = _QUOTED_LINE.sub(" ", t)
    t = _IMG.sub(" ", t)
    t = _INLINE_CODE.sub(" ", t)
    t = _HTML_TAG.sub(" ", t)
    t = _MD_LINK.sub(r"\1", t)
    t = _CHECKBOX.sub(" ", t)
    t = _URL.sub(" ", t)
    t = _MENTION.sub(" ", t)
    return t


def has_suggestion_block(text):
    """A ```suggestion block is mechanically an applyable change request.

    This is a fact about GitHub's UI, not an interpretation of the text, which is
    why it is allowed to live here.
    """
    return bool(_SUGGESTION.search(text or ""))


# ------------------------------------------------------------------ tokenizing

# Structural English + review-thread boilerplate. NOT topic words: nothing here
# encodes what reviewers care about, only what carries no signal in any corpus.
STOPWORDS = set("""
a about above after again against all am an and any are aren as at be because
been before being below between both but by can cannot could couldn did didn do
does doesn doing don down during each few for from further had hadn has hasn have
haven having he her here hers herself him himself his how i if in into is isn it
its itself just ll me might mightn more most must mustn my myself need needn no
nor not now o of off on once only or other ought our ours ourselves out over own
re s same shan she should shouldn so some such t than that the their theirs them
themselves then there these they this those through to too under until up ve very
was wasn we were weren what when where which while who whom why will with won
would wouldn you your yours yourself yourselves
also get got make makes making use used using like really actually maybe probably
think thing things bit lot way ways sure yeah yep ok okay thanks thank cheers
one two three first second new old good bad better best nice great sorry oh ah
hmm well right sure done yes see look looks looking seems seem let lets us
pr prs commit commits branch main merge merged rebase push pushed file files line
lines change changes changed changing code review reviews reviewed comment
comments here there now then still already going gonna want wants wanted
""".split())

_WORD = re.compile(r"[a-z][a-z0-9_]{1,}")


def tokenize(text, keep_stopwords=False):
    toks = _WORD.findall((text or "").lower())
    if keep_stopwords:
        return toks
    return [t for t in toks if t not in STOPWORDS and len(t) > 2]


def ngrams(tokens, n):
    return [" ".join(tokens[i:i + n]) for i in range(len(tokens) - n + 1)]


# --------------------------------------------------- credential / PII screening
#
# Gates whether a comment may be QUOTED. Flagged comments still count toward
# every total -- they just never appear verbatim in the report.

SECRET_PATTERNS = [
    ("email", r"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"),
    ("github_token", r"\b(?:ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{16,}\b|\bgithub_pat_[A-Za-z0-9_]{20,}\b"),
    ("openai_key", r"\bsk-[A-Za-z0-9]{20,}\b"),
    ("slack_token", r"\bxox[abprs]-[A-Za-z0-9-]{10,}\b"),
    ("aws_key", r"\bAKIA[0-9A-Z]{16}\b"),
    ("private_key", r"-----BEGIN [A-Z ]*PRIVATE KEY-----"),
    ("jwt", r"\beyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\b"),
    ("bearer", r"(?i)\bbearer\s+[A-Za-z0-9._-]{20,}"),
    ("secret_assignment",
     r"(?i)\b(?:password|passwd|secret|api[_-]?key|access[_-]?token|client[_-]?secret)\b\s*[:=]\s*\S{6,}"),
    ("url_with_credential", r"https?://[^\s]*[?&](?:key|token|secret|password|access_token)=[^\s&]+"),
    ("high_entropy_hex", r"\b[A-Fa-f0-9]{40,}\b"),
    ("basic_auth_url", r"https?://[^\s/@]+:[^\s/@]+@"),
]

_COMPILED_SECRETS = [(name, re.compile(p)) for name, p in SECRET_PATTERNS]


def screen(text):
    """Names of secret/PII patterns present. Empty list means safe to quote."""
    if not text:
        return []
    return [name for name, p in _COMPILED_SECRETS if p.search(text)]


def is_quotable(text):
    return not screen(text)
