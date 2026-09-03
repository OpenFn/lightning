#!/usr/bin/env python3
#
# scrape.py — fetch a GitHub repo's complete pull-request history into
# newline-delimited JSON under .scratch/pr-history/, as the raw material for the
# code-review meta-analysis in this directory's report.
#
# Why this shape, since none of it is arbitrary:
#
#   * REST only. GraphQL is blocked in Claude Code web sessions ("only the pinned
#     set of PR-review operations is served"), and so is /search/*. That is why
#     reviews are fetched per PR and why the PR count is verified by parsing
#     Link rel="last" instead of asking the search API for a total.
#
#   * Comments come from the two repo-wide bulk endpoints, not per PR. That is
#     100 requests instead of 4,470 for identical data, and it is the difference
#     between fitting in the rate-limit window and not.
#
#   * The rate limit is 5,550/hr, NOT the 15,000 that GET /rate_limit reports.
#     Every real response header says 5550, and the headers are what's enforced.
#     A cold run is ~4,600 requests = ~83% of one window, so you get roughly one
#     attempt per hour. Hence: iterate with --limit 25 (~60 requests), never
#     against the full set.
#
#   * ETag conditional requests + an on-disk response cache are therefore not a
#     nice-to-have. A 304 costs zero rate-limit budget, so a warm re-run is
#     effectively free. ETags are skipped on the bulk paginated lists, whose page
#     boundaries shift as content is added.
#
#   * Reviews cannot be pruned. No field on /pulls/{n} tells you whether reviews
#     exist -- PR #5100 reports review_comments:0 yet has an APPROVED review.
#
# Usage:
#   tooling/pr-history/scrape.py                     # full scrape, OpenFn/lightning
#   tooling/pr-history/scrape.py --limit 25          # smoke run, ~60 requests
#   tooling/pr-history/scrape.py --repo OpenFn/kit   # another repo
#   tooling/pr-history/scrape.py --verify            # re-check a dataset, no fetching
#   tooling/pr-history/scrape.py --spot-check 5111,5100
#
# Output: .scratch/pr-history/<owner>-<repo>/   (gitignored via .scratch/)
#   pulls.ndjson            one trimmed PR per line
#   reviews.ndjson          one review per line, carrying pr_number
#   review_comments.ndjson  inline code comments, with path + truncated diff_hunk
#   issue_comments.ndjson   conversation comments, filtered to PRs
#   pulls.csv               one row per PR, flattened + derived metrics
#   state.json              watermark + completed numbers (resume point)
#   manifest.json           run metadata + verification results
#   cache/                  one file per URL: etag + body
#
# Requires python3 >= 3.9 and GITHUB_TOKEN or GH_TOKEN. No pip install, no venv.

import argparse
import concurrent.futures as futures
import csv
import hashlib
import itertools
import json
import os
import re
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timedelta, timezone

API_ROOT = "https://api.github.com"
DEFAULT_REPO = "OpenFn/lightning"
DIFF_HUNK_MAX = 400
UA = "openfn-pr-history-scraper"

# Proxy and CA handling is deliberately absent: urllib's default ProxyHandler
# reads https_proxy, and SSL_CERT_FILE already sits on
# ssl.get_default_verify_paths(). Never disable verification to "fix" TLS here.


class PolicyBlocked(Exception):
    """A proxy/policy 403. Permanent -- retrying only wastes the backoff ladder."""


class GiveUp(Exception):
    """Retries exhausted."""


class NotFound(Exception):
    """404. Expected for roughly half the number range, since issues share it."""


# ---------------------------------------------------------------- small helpers

def now_utc():
    return datetime.now(timezone.utc)


def parse_ts(s):
    if not s:
        return None
    return datetime.strptime(s, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)


def iso(dt):
    return dt.strftime("%Y-%m-%dT%H:%M:%SZ") if dt else ""


def hours_between(a, b):
    if not a or not b:
        return None
    return round((b - a).total_seconds() / 3600.0, 2)


def login_of(obj):
    return (obj or {}).get("login") or ""


def is_bot(login, type_):
    return type_ == "Bot" or login.endswith("[bot]")


def parse_link(header):
    """Parse a Link header into {rel: url}. Never synthesize ?page=n+1 instead."""
    out = {}
    if not header:
        return out
    for part in header.split(","):
        seg = part.split(";")
        if len(seg) < 2:
            continue
        url = seg[0].strip().lstrip("<").rstrip(">")
        for attr in seg[1:]:
            m = re.match(r'\s*rel="?([^"]+)"?', attr)
            if m:
                out[m.group(1)] = url
    return out


_REPO_ID_URL = re.compile(r"^https://api\.github\.com/repositories/\d+/")


def normalize_url(url, repo):
    """Rewrite GitHub's numeric-ID pagination URLs back to the owner/name form.

    Link headers hand back https://api.github.com/repositories/454419290/pulls?...
    rather than /repos/OpenFn/lightning/pulls?..., and this session's proxy serves
    only the latter -- it 403s the numeric form ("sessions are bound to their
    configured repositories"). Both forms are equivalent on api.github.com, so
    rewriting is safe outside the proxy too. Without this, every crawl dies on
    page 2.
    """
    if not url:
        return url
    return _REPO_ID_URL.sub("%s/repos/%s/" % (API_ROOT, repo), url)


def pr_number_from_url(url):
    m = re.search(r"/(?:pulls|issues)/(\d+)(?:$|[/?#])", url or "")
    return int(m.group(1)) if m else None


# ------------------------------------------------------------------- rate limit

class RateGate:
    """Token-bucket QPS ceiling plus a primary-limit watchdog.

    The binding constraint is GitHub's *secondary* limit (~900 points/min, so
    ~15 req/s), not the primary one. Eight unthrottled workers land close enough
    to trip it, so the whole process is capped here.
    """

    def __init__(self, qps=10.0, floor=50, verbose=False):
        self.interval = 1.0 / qps if qps > 0 else 0.0
        self.floor = floor
        self.verbose = verbose
        self._lock = threading.Lock()
        self._next = 0.0
        self.limit = None
        self.remaining = None

    def acquire(self):
        with self._lock:
            now = time.monotonic()
            wait = self._next - now
            if wait < 0:
                wait = 0.0
            self._next = max(now, self._next) + self.interval
        if wait:
            time.sleep(wait)

    def observe(self, headers):
        # headers.get() is case-insensitive on urllib's HTTPMessage.
        # dict(headers) is NOT -- that silently yields None. Don't "simplify" this.
        lim = headers.get("X-RateLimit-Limit")
        rem = headers.get("X-RateLimit-Remaining")
        reset = headers.get("X-RateLimit-Reset")
        if lim:
            self.limit = int(lim)
        if rem is None:
            return
        rem = int(rem)
        with self._lock:
            # Track the lowest observed value; don't trust any single reading.
            self.remaining = rem if self.remaining is None else min(self.remaining, rem)
        if rem <= self.floor and reset:
            nap = max(0, int(reset) - int(time.time())) + 2
            sys.stderr.write(
                "\n  rate limit nearly exhausted (%s left of %s) -- sleeping %ds\n"
                % (rem, self.limit, nap)
            )
            sys.stderr.flush()
            time.sleep(nap)
            with self._lock:
                self.remaining = None


# ------------------------------------------------------------------------ cache

class Cache:
    """One JSON file per URL, holding the ETag and the decoded body.

    Written atomically so a killed run never leaves a torn entry. This is what
    makes a re-run cheap: a 304 costs no rate-limit budget at all.
    """

    def __init__(self, root, enabled=True):
        self.root = root
        self.enabled = enabled
        self.hits = 0
        self.revalidated = 0
        self._lock = threading.Lock()
        if enabled:
            os.makedirs(root, exist_ok=True)

    def _path(self, url):
        return os.path.join(self.root, hashlib.sha256(url.encode()).hexdigest()[:16] + ".json")

    def get(self, url):
        if not self.enabled:
            return None
        try:
            with open(self._path(url)) as fh:
                return json.load(fh)
        except (OSError, ValueError):
            return None

    def put(self, url, etag, body):
        if not self.enabled:
            return
        path = self._path(url)
        tmp = path + ".tmp.%d" % threading.get_ident()
        try:
            with open(tmp, "w") as fh:
                json.dump({"url": url, "etag": etag, "fetched_at": iso(now_utc()), "body": body}, fh)
            os.replace(tmp, path)
        except OSError:
            try:
                os.unlink(tmp)
            except OSError:
                pass

    def note_hit(self, revalidated):
        with self._lock:
            if revalidated:
                self.revalidated += 1
            else:
                self.hits += 1


# ----------------------------------------------------------------- REST client

class Client:
    def __init__(self, token, cache, gate, repo, verbose=False):
        self.token = token
        self.repo = repo
        self.cache = cache
        self.gate = gate
        self.verbose = verbose
        self.requests = 0
        self._lock = threading.Lock()

    def _headers(self, etag=None):
        h = {
            "Authorization": "Bearer " + self.token,
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28",
            "User-Agent": UA,
        }
        if etag:
            h["If-None-Match"] = etag
        return h

    def _raw(self, url, etag=None):
        """One HTTP round trip. Returns (status, body_or_None, headers)."""
        self.gate.acquire()
        req = urllib.request.Request(url, headers=self._headers(etag))
        with self._lock:
            self.requests += 1
        try:
            with urllib.request.urlopen(req, timeout=90) as resp:
                self.gate.observe(resp.headers)
                raw = resp.read()
                body = json.loads(raw.decode("utf-8")) if raw else None
                return resp.status, body, resp.headers
        except urllib.error.HTTPError as e:
            self.gate.observe(e.headers)
            if e.code == 304:
                return 304, None, e.headers
            payload = b""
            try:
                payload = e.read()
            except Exception:
                pass
            raise HttpFailure(e.code, payload.decode("utf-8", "replace"), e.headers)

    def get_json(self, url, conditional=True):
        """Fetch with cache + ETag revalidation. Returns the decoded body."""
        entry = self.cache.get(url) if conditional else None
        etag = entry.get("etag") if entry else None
        delay = 1.0
        for attempt in range(1, 7):
            try:
                status, body, headers = self._raw(url, etag)
            except HttpFailure as e:
                if e.code == 404:
                    raise NotFound(url)
                if e.code == 451:
                    raise GiveUp("451 unavailable for legal reasons: " + url)
                if is_policy_403(e.code, e.body):
                    raise PolicyBlocked(url + " -- " + e.body[:200])
                retry_after = e.headers.get("Retry-After") if e.headers else None
                if e.code in (403, 429) and retry_after:
                    nap = float(retry_after) + 1
                elif e.code == 403 and "secondary rate limit" in e.body.lower():
                    nap = 60.0 * attempt
                elif e.code in (403, 429) or 500 <= e.code < 600:
                    nap = delay
                    delay *= 2
                else:
                    raise GiveUp("HTTP %d on %s: %s" % (e.code, url, e.body[:200]))
                if attempt == 6:
                    raise GiveUp("gave up after %d attempts on %s" % (attempt, url))
                sys.stderr.write("  HTTP %d -- retry %d in %.0fs\n" % (e.code, attempt, nap))
                time.sleep(nap)
                continue
            except (urllib.error.URLError, OSError, ValueError) as e:
                if attempt == 6:
                    raise GiveUp("network failure on %s: %s" % (url, e))
                time.sleep(delay)
                delay *= 2
                continue

            if status == 304:
                self.cache.note_hit(revalidated=True)
                return entry["body"]
            self.cache.put(url, headers.get("ETag"), body)
            return body
        raise GiveUp(url)

    def paginate(self, url, conditional=False):
        """Yield items across pages, following Link rel=next.

        conditional defaults off: bulk list ETags churn as page boundaries shift,
        so revalidating them buys nothing.
        """
        while url:
            entry = self.cache.get(url) if conditional else None
            etag = entry.get("etag") if entry else None
            # paginate needs the headers, so it can't reuse get_json directly.
            delay = 1.0
            for attempt in range(1, 7):
                try:
                    status, body, headers = self._raw(url, etag)
                    break
                except HttpFailure as e:
                    if is_policy_403(e.code, e.body):
                        raise PolicyBlocked(url + " -- " + e.body[:200])
                    if e.code == 404:
                        raise NotFound(url)
                    retry_after = e.headers.get("Retry-After") if e.headers else None
                    nap = float(retry_after) + 1 if retry_after else delay
                    delay *= 2
                    if attempt == 6:
                        raise GiveUp("HTTP %d on %s" % (e.code, url))
                    sys.stderr.write("  HTTP %d -- retry %d in %.0fs\n" % (e.code, attempt, nap))
                    time.sleep(nap)
                except (urllib.error.URLError, OSError, ValueError):
                    if attempt == 6:
                        raise GiveUp("network failure on " + url)
                    time.sleep(delay)
                    delay *= 2
            else:
                raise GiveUp(url)

            if status == 304:
                page = entry["body"]
                self.cache.note_hit(revalidated=True)
            else:
                page = body or []
                if conditional:
                    self.cache.put(url, headers.get("ETag"), page)
            for item in page:
                yield item
            url = normalize_url(parse_link(headers.get("Link")).get("next"), self.repo)


class HttpFailure(Exception):
    def __init__(self, code, body, headers):
        super().__init__("HTTP %d" % code)
        self.code = code
        self.body = body
        self.headers = headers


def is_policy_403(code, body):
    if code != 403:
        return False
    b = (body or "").lower()
    return "not available" in b or "sessions are bound" in b or "not enabled for this session" in b


# -------------------------------------------------------------- trim to schema
#
# GitHub PR payloads are ~20KB each and mostly _links and URL templates; 2,235 of
# them is ~44MB of noise. These keep-lists are the schema. Free-text bodies ARE
# retained -- a meta-analysis of what reviewers ask for is a content analysis, so
# dropping bodies would defeat the point. They stay in gitignored .scratch/ and
# analyze.py screens them for credentials before anything becomes quotable.
#
# No endpoint called here returns an email address, so emails never enter the
# dataset by construction rather than by scrubbing. Don't add /users/{login} or
# the commits endpoints without revisiting that.


def trim_pull(d, scraped_at):
    user = d.get("user") or {}
    head = d.get("head") or {}
    base = d.get("base") or {}
    login = login_of(user)
    return {
        "number": d["number"],
        "title": d.get("title") or "",
        "body": d.get("body") or "",
        "state": d.get("state"),
        "draft": bool(d.get("draft")),
        "author": login,
        "author_type": user.get("type") or "",
        "author_association": d.get("author_association") or "",
        "labels": [l.get("name") for l in (d.get("labels") or [])],
        "milestone": (d.get("milestone") or {}).get("title") or "",
        "assignees": [login_of(a) for a in (d.get("assignees") or [])],
        "requested_reviewers": [login_of(r) for r in (d.get("requested_reviewers") or [])],
        "head_ref": head.get("ref") or "",
        "head_sha": head.get("sha") or "",
        "head_repo_fork": bool((head.get("repo") or {}).get("fork")),
        "base_ref": base.get("ref") or "",
        "created_at": d.get("created_at"),
        "updated_at": d.get("updated_at"),
        "closed_at": d.get("closed_at"),
        "merged_at": d.get("merged_at"),
        "merged": bool(d.get("merged") if "merged" in d else d.get("merged_at")),
        "merged_by": login_of(d.get("merged_by")),
        "additions": d.get("additions"),
        "deletions": d.get("deletions"),
        "changed_files": d.get("changed_files"),
        "commits": d.get("commits"),
        "review_comments_count": d.get("review_comments"),
        "comments_count": d.get("comments"),
        "mergeable_state": d.get("mergeable_state") or "",
        "html_url": d.get("html_url") or "",
        "scraped_at": scraped_at,
    }


def trim_review(r, pr_number):
    user = r.get("user") or {}
    body = r.get("body") or ""
    return {
        "id": r["id"],
        "pr_number": pr_number,
        "reviewer": login_of(user),
        "reviewer_type": user.get("type") or "",
        "state": r.get("state"),
        "submitted_at": r.get("submitted_at"),
        "author_association": r.get("author_association") or "",
        "commit_id": r.get("commit_id") or "",
        "body": body,
        "body_length": len(body),
        "html_url": r.get("html_url") or "",
    }


def trim_review_comment(c):
    user = c.get("user") or {}
    body = c.get("body") or ""
    hunk = c.get("diff_hunk") or ""
    return {
        "id": c["id"],
        "pr_number": pr_number_from_url(c.get("pull_request_url") or ""),
        "review_id": c.get("pull_request_review_id"),
        "in_reply_to_id": c.get("in_reply_to_id"),
        "author": login_of(user),
        "author_type": user.get("type") or "",
        "author_association": c.get("author_association") or "",
        "created_at": c.get("created_at"),
        "updated_at": c.get("updated_at"),
        "path": c.get("path") or "",
        "line": c.get("line") if c.get("line") is not None else c.get("original_line"),
        "side": c.get("side") or "",
        "subject_type": c.get("subject_type") or "",
        "body": body,
        "body_length": len(body),
        # Truncated: enough to tell what the comment is about, without mirroring
        # Lightning source into the dataset.
        "diff_hunk": hunk[:DIFF_HUNK_MAX],
        "diff_hunk_truncated": len(hunk) > DIFF_HUNK_MAX,
        "reactions_total": (c.get("reactions") or {}).get("total_count") or 0,
        "html_url": c.get("html_url") or "",
    }


def trim_issue_comment(c):
    user = c.get("user") or {}
    body = c.get("body") or ""
    return {
        "id": c["id"],
        "pr_number": pr_number_from_url(c.get("issue_url") or ""),
        "author": login_of(user),
        "author_type": user.get("type") or "",
        "author_association": c.get("author_association") or "",
        "created_at": c.get("created_at"),
        "updated_at": c.get("updated_at"),
        "body": body,
        "body_length": len(body),
        "reactions_total": (c.get("reactions") or {}).get("total_count") or 0,
        # The reliable bot signal on this endpoint.
        "via_github_app": bool(c.get("performed_via_github_app")),
        "html_url": c.get("html_url") or "",
    }


# ----------------------------------------------------------------------- phases

def authoritative_pr_count(client, repo):
    """PR total from Link rel="last" with per_page=1.

    The obvious route -- /search/issues?q=repo:X+is:pr and read total_count -- is
    403 in this environment ("sessions are bound to their configured
    repositories"). This is one request, repo-scoped, and exact.
    """
    url = "%s/repos/%s/pulls?state=all&per_page=1" % (API_ROOT, repo)
    client.gate.acquire()
    req = urllib.request.Request(url, headers=client._headers())
    with client._lock:
        client.requests += 1
    with urllib.request.urlopen(req, timeout=90) as resp:
        client.gate.observe(resp.headers)
        resp.read()
        link = parse_link(resp.headers.get("Link")).get("last")
    if not link:
        return None
    q = urllib.parse.parse_qs(urllib.parse.urlparse(link).query)
    return int(q["page"][0]) if "page" in q else None


def fetch_pr_index(client, repo, limit=None):
    """The PR list.

    created&asc, not updated: paginating a live repo by updated_at reshuffles
    items across page boundaries mid-crawl and can silently skip or duplicate.
    """
    if limit:
        url = "%s/repos/%s/pulls?state=all&per_page=%d&sort=created&direction=desc" % (
            API_ROOT, repo, min(limit, 100))
        items = list(itertools.islice(client.paginate(url), limit))
        return sorted(items, key=lambda p: p["number"])
    url = "%s/repos/%s/pulls?state=all&per_page=100&sort=created&direction=asc" % (API_ROOT, repo)
    return list(client.paginate(url))


def _pooled(client, repo, numbers, suffix, workers, label):
    """Run a per-PR GET across a thread pool, tolerating 404s."""
    out, missing = {}, []
    total = len(numbers)
    done = [0]
    lock = threading.Lock()

    def one(n):
        url = "%s/repos/%s/pulls/%d%s" % (API_ROOT, repo, n, suffix)
        try:
            if suffix:
                return n, list(client.paginate(url, conditional=True)), None
            return n, client.get_json(url), None
        except NotFound:
            return n, None, "missing"

    with futures.ThreadPoolExecutor(max_workers=workers) as pool:
        for n, payload, err in pool.map(one, numbers):
            with lock:
                done[0] += 1
                if done[0] % 50 == 0 or done[0] == total:
                    sys.stderr.write("\r  %s %d/%d" % (label, done[0], total))
                    sys.stderr.flush()
            if err:
                missing.append(n)
            else:
                out[n] = payload
    sys.stderr.write("\n")
    return out, missing


def fetch_details(client, repo, numbers, workers):
    return _pooled(client, repo, numbers, "", workers, "detail")


def fetch_reviews(client, repo, numbers, workers):
    return _pooled(client, repo, numbers, "/reviews?per_page=100", workers, "reviews")


def fetch_bulk_comments(client, repo, kind, since=None):
    """Repo-wide comments. 100 requests for what per-PR fetching would cost 4,470."""
    url = "%s/repos/%s/%s/comments?per_page=100&sort=created&direction=asc" % (API_ROOT, repo, kind)
    if since:
        url += "&since=" + since
    return list(client.paginate(url))


# ------------------------------------------------------------ derived metrics
#
# Definitions live here and are mirrored in README.md. If you change one, change
# both -- every number in the report traces back to this function.

SIZE_BUCKETS = ((10, "XS"), (50, "S"), (250, "M"), (1000, "L"))
REVIEW_STATES = ("APPROVED", "CHANGES_REQUESTED", "COMMENTED")


def size_bucket(churn):
    if churn is None:
        return ""
    for ceiling, name in SIZE_BUCKETS:
        if churn <= ceiling:
            return name
    return "XL"


def derive_row(pull, reviews, rcs, ics, now):
    author = pull["author"]
    created = parse_ts(pull.get("created_at"))
    merged = parse_ts(pull.get("merged_at"))
    closed = parse_ts(pull.get("closed_at"))

    # Self-review doesn't start the review clock.
    peer_reviews = [r for r in reviews if r["reviewer"] and r["reviewer"] != author]
    peer_rcs = [c for c in rcs if c["author"] and c["author"] != author]

    stamps = [parse_ts(r["submitted_at"]) for r in peer_reviews]
    stamps += [parse_ts(c["created_at"]) for c in peer_rcs]
    stamps = [s for s in stamps if s]
    first_review = min(stamps) if stamps else None

    reviewers = sorted({r["reviewer"] for r in peer_reviews} | {c["author"] for c in peer_rcs})
    counted = [r for r in peer_reviews if r["state"] in REVIEW_STATES]

    additions = pull.get("additions")
    deletions = pull.get("deletions")
    churn = (additions or 0) + (deletions or 0) if additions is not None else None

    paths = [c["path"] for c in rcs if c["path"]]
    end = closed or now

    return {
        "number": pull["number"],
        "html_url": pull["html_url"],
        "title": pull["title"],
        "author": author,
        "author_type": pull["author_type"],
        "author_association": pull["author_association"],
        "bot_authored": is_bot(author, pull["author_type"]),
        "state": pull["state"],
        "merged": pull["merged"],
        "still_open": pull["state"] == "open",
        "closed_unmerged": bool(closed and not merged),
        "self_merged": bool(pull["merged_by"]) and pull["merged_by"] == author,
        "draft_now": pull["draft"],
        "created_at": pull["created_at"] or "",
        "updated_at": pull["updated_at"] or "",
        "closed_at": pull["closed_at"] or "",
        "merged_at": pull["merged_at"] or "",
        "merged_by": pull["merged_by"],
        "base_ref": pull["base_ref"],
        "from_fork": pull["head_repo_fork"],
        "additions": additions,
        "deletions": deletions,
        "churn": churn,
        "size_bucket": size_bucket(churn),
        "changed_files": pull.get("changed_files"),
        "commits": pull.get("commits"),
        "labels": "|".join(pull["labels"]),
        "milestone": pull["milestone"],
        "n_reviews": len(peer_reviews),
        "n_review_rounds": len(counted),
        "n_approvals": sum(1 for r in peer_reviews if r["state"] == "APPROVED"),
        "n_change_requests": sum(1 for r in peer_reviews if r["state"] == "CHANGES_REQUESTED"),
        "n_review_comments": len(rcs),
        "n_issue_comments": len(ics),
        "n_comments_total": len(rcs) + len(ics),
        "reviewers": "|".join(reviewers),
        "n_reviewers": len(reviewers),
        "first_review_at": iso(first_review),
        "hours_to_first_review": hours_between(created, first_review),
        "hours_to_merge": hours_between(created, merged),
        "hours_to_close": hours_between(created, closed),
        "hours_open_total": hours_between(created, end),
        # Derived from *commented* paths, so this is coverage of reviewed areas,
        # not of changed areas -- the per-PR files endpoint is out of scope.
        "touches_backend": any(p.startswith("lib/") for p in paths),
        "touches_frontend": any(p.startswith("assets/") for p in paths),
        "touches_tests": any(p.startswith("test/") or "/test/" in p for p in paths),
        "created_month": (pull.get("created_at") or "")[:7],
        "merged_month": (pull.get("merged_at") or "")[:7],
    }


CSV_COLUMNS = [
    "number", "html_url", "title", "author", "author_type", "author_association",
    "bot_authored", "state", "merged", "still_open", "closed_unmerged",
    "self_merged", "draft_now", "created_at", "updated_at", "closed_at",
    "merged_at", "merged_by", "base_ref", "from_fork", "additions", "deletions",
    "churn", "size_bucket", "changed_files", "commits", "labels", "milestone",
    "n_reviews", "n_review_rounds", "n_approvals", "n_change_requests",
    "n_review_comments", "n_issue_comments", "n_comments_total", "reviewers",
    "n_reviewers", "first_review_at", "hours_to_first_review", "hours_to_merge",
    "hours_to_close", "hours_open_total", "touches_backend", "touches_frontend",
    "touches_tests", "created_month", "merged_month",
]


# -------------------------------------------------------------------------- io

def write_ndjson(path, rows, key):
    """Deterministic output: rows sorted by key, keys sorted, so two runs diff clean."""
    with open(path, "w") as fh:
        for row in sorted(rows, key=lambda r: r[key]):
            fh.write(json.dumps(row, sort_keys=True, ensure_ascii=False) + "\n")


def read_ndjson(path):
    if not os.path.exists(path):
        return []
    with open(path) as fh:
        return [json.loads(line) for line in fh if line.strip()]


def write_csv(path, rows):
    with open(path, "w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=CSV_COLUMNS, lineterminator="\n", extrasaction="ignore")
        w.writeheader()
        for row in sorted(rows, key=lambda r: r["number"]):
            w.writerow({k: ("" if row.get(k) is None else row.get(k)) for k in CSV_COLUMNS})


def write_json(path, obj):
    tmp = path + ".tmp"
    with open(tmp, "w") as fh:
        json.dump(obj, fh, indent=2, sort_keys=True)
    os.replace(tmp, path)


def upsert(existing, new, key):
    """Union-never-trim merge. Incremental runs must not delete."""
    merged = {r[key]: r for r in existing}
    for r in new:
        merged[r[key]] = r
    return list(merged.values())


# ----------------------------------------------------------------- verification

class Check:
    def __init__(self, name, ok, detail):
        self.name, self.ok, self.detail = name, ok, detail

    def as_dict(self):
        return {"name": self.name, "ok": self.ok, "detail": self.detail}


def verify(pulls, reviews, rcs, ics, expected, newest, missing, dropped_ics, strict=True):
    checks = []
    numbers = [p["number"] for p in pulls]
    nset = set(numbers)

    # V1 -- against Link rel="last", since /search is 403 here.
    if expected is None:
        checks.append(Check("count vs Link rel=last", True, "skipped (not fetched)"))
    else:
        ok = len(pulls) == expected
        checks.append(Check("count vs Link rel=last", ok,
                            "fetched %d, authoritative %d" % (len(pulls), expected)))

    # V2 -- every indexed PR got its detail call (additions is detail-only).
    no_detail = [n for n, p in zip(numbers, pulls) if p.get("additions") is None]
    checks.append(Check("index/detail parity", not no_detail,
                        "%d without detail%s; %d 404-missing" % (
                            len(no_detail),
                            (" e.g. " + str(no_detail[:5])) if no_detail else "",
                            len(missing))))

    # V3 -- coverage, NOT "no gaps in numbering". PRs and issues share one
    # sequence, so ~56% of the numbers in the range are legitimately absent.
    checks.append(Check("no duplicate numbers", len(numbers) == len(nset),
                        "%d rows, %d distinct" % (len(numbers), len(nset))))
    if newest:
        checks.append(Check("newest PR present", newest in nset,
                            "newest is #%s, max fetched #%s" % (newest, max(nset) if nset else "-")))
    months = sorted({p["created_at"][:7] for p in pulls if p.get("created_at")})
    gaps = []
    if len(months) > 1:
        y, m = (int(x) for x in months[0].split("-"))
        while "%04d-%02d" % (y, m) != months[-1]:
            key = "%04d-%02d" % (y, m)
            if key not in months:
                gaps.append(key)
            m += 1
            if m > 12:
                y, m = y + 1, 1
    checks.append(Check("no empty calendar months", not gaps,
                        "gaps: %s" % (gaps[:6] if gaps else "none")))

    # V4 -- the important one. The bulk-comment join is where this design could
    # silently lose data, so reconcile it against each PR's own counters.
    # A small nonzero delta is EXPECTED: counters are point-in-time on the detail
    # payload while the bulk lists are a separate snapshot, and deletions still
    # decrement counters.
    rc_by_pr, ic_by_pr = {}, {}
    for c in rcs:
        rc_by_pr[c["pr_number"]] = rc_by_pr.get(c["pr_number"], 0) + 1
    for c in ics:
        ic_by_pr[c["pr_number"]] = ic_by_pr.get(c["pr_number"], 0) + 1
    rc_bad, ic_bad = [], []
    for p in pulls:
        n = p["number"]
        if p.get("review_comments_count") is not None:
            d = rc_by_pr.get(n, 0) - p["review_comments_count"]
            if d:
                rc_bad.append((n, d))
        if p.get("comments_count") is not None:
            d = ic_by_pr.get(n, 0) - p["comments_count"]
            if d:
                ic_bad.append((n, d))
    for label, bad in (("review", rc_bad), ("conversation", ic_bad)):
        rate = len(bad) / len(pulls) if pulls else 0
        worst = max((abs(d) for _, d in bad), default=0)
        ok = rate <= 0.01 and worst <= 5 if strict else True
        checks.append(Check("%s-comment reconciliation" % label, ok,
                            "%d/%d PRs differ (%.2f%%), worst delta %d%s" % (
                                len(bad), len(pulls), rate * 100, worst,
                                ("; e.g. " + str(sorted(bad, key=lambda t: -abs(t[1]))[:4]))
                                if bad else "")))

    # V5 -- no orphan children, and account for dropped issue comments.
    orphans = [r["pr_number"] for r in reviews if r["pr_number"] not in nset]
    orphans += [c["pr_number"] for c in rcs if c["pr_number"] not in nset]
    checks.append(Check("no orphan reviews/comments", not orphans,
                        "%d orphans%s" % (len(orphans), (" e.g. " + str(orphans[:5])) if orphans else "")))
    checks.append(Check("issue comments split", True,
                        "%d kept on PRs, %d dropped as non-PR issues" % (len(ics), dropped_ics)))

    # Sanity: review-state mix should sit near the 60-PR probe that sized this job
    # (COMMENTED 46%, APPROVED 38%, CHANGES_REQUESTED 16%). Wild divergence = bug.
    mix = {}
    for r in reviews:
        mix[r["state"]] = mix.get(r["state"], 0) + 1
    total = sum(mix.values())
    if total < 100:
        checks.append(Check("review-state mix plausible", True,
                            "skipped: only %d reviews, too few to be a shape check" % total))
    else:
        cr_share = mix.get("CHANGES_REQUESTED", 0) / total
        checks.append(Check("review-state mix plausible", 0.05 <= cr_share <= 0.30,
                            "CHANGES_REQUESTED %.1f%% of %d reviews; mix %s" % (
                                cr_share * 100, total, mix)))
    return checks


def print_checks(checks):
    sys.stderr.write("\nVerification\n")
    for c in checks:
        sys.stderr.write("  [%s] %-32s %s\n" % ("ok" if c.ok else "FAIL", c.name, c.detail))
    bad = [c.name for c in checks if not c.ok]
    if bad:
        sys.stderr.write("\n  %d check(s) failed: %s\n" % (len(bad), ", ".join(bad)))
    else:
        sys.stderr.write("\n  all checks passed\n")
    return not bad


# --------------------------------------------------------------------- the run

def repo_root():
    try:
        out = subprocess.check_output(["git", "rev-parse", "--show-toplevel"],
                                      stderr=subprocess.DEVNULL)
        return out.decode().strip()
    except (subprocess.CalledProcessError, OSError):
        return os.getcwd()


def main(argv=None):
    ap = argparse.ArgumentParser(
        description="Scrape a GitHub repo's PR history into .scratch/pr-history/.")
    ap.add_argument("--repo", default=DEFAULT_REPO, help="owner/name (default %s)" % DEFAULT_REPO)
    ap.add_argument("--out", default=None, help="output dir (default <repo-root>/.scratch/pr-history/<owner>-<name>)")
    ap.add_argument("--limit", type=int, default=None,
                    help="smoke mode: only the N newest PRs, into a /smoke subdir")
    ap.add_argument("--full", action="store_true", help="ignore the watermark; revalidate everything (ETag-cheap)")
    ap.add_argument("--concurrency", type=int, default=8, help="worker threads (default 8, capped 16)")
    ap.add_argument("--qps", type=float, default=10.0, help="process-wide request ceiling (default 10/s)")
    ap.add_argument("--no-cache", action="store_true", help="bypass the on-disk response cache")
    ap.add_argument("--verify", action="store_true", help="verify an existing dataset without fetching")
    ap.add_argument("--spot-check", default="", help="comma-separated PR numbers to print")
    ap.add_argument("--quiet", action="store_true")
    args = ap.parse_args(argv)

    if "/" not in args.repo:
        ap.error("--repo must be owner/name")
    owner, name = args.repo.split("/", 1)
    root = repo_root()
    out = args.out or os.path.join(root, ".scratch", "pr-history", "%s-%s" % (owner.lower(), name.lower()))
    if args.limit:
        out = os.path.join(out, "smoke")
    os.makedirs(out, exist_ok=True)

    paths = {
        "pulls": os.path.join(out, "pulls.ndjson"),
        "reviews": os.path.join(out, "reviews.ndjson"),
        "rcs": os.path.join(out, "review_comments.ndjson"),
        "ics": os.path.join(out, "issue_comments.ndjson"),
        "csv": os.path.join(out, "pulls.csv"),
        "state": os.path.join(out, "state.json"),
        "manifest": os.path.join(out, "manifest.json"),
    }

    if args.spot_check:
        wanted = {int(x) for x in args.spot_check.split(",") if x.strip()}
        by_n = {p["number"]: p for p in read_ndjson(paths["pulls"])}
        rows = {r["number"]: r for r in _csv_rows(paths["csv"])}
        for n in sorted(wanted):
            p, r = by_n.get(n), rows.get(n)
            if not p:
                print("#%d not in dataset" % n)
                continue
            print("#%d  %s" % (n, p["title"][:70]))
            print("    %s" % p["html_url"])
            print("    author=%s state=%s merged=%s  +%s/-%s files=%s commits=%s" % (
                p["author"], p["state"], p["merged"], p["additions"], p["deletions"],
                p["changed_files"], p["commits"]))
            if r:
                print("    reviews=%s approvals=%s changes_requested=%s reviewers=%s" % (
                    r["n_reviews"], r["n_approvals"], r["n_change_requests"], r["reviewers"] or "-"))
                print("    hours_to_first_review=%s hours_to_merge=%s" % (
                    r["hours_to_first_review"] or "-", r["hours_to_merge"] or "-"))
        return 0

    if args.verify:
        pulls = read_ndjson(paths["pulls"])
        if not pulls:
            sys.stderr.write("no dataset at %s -- run a scrape first\n" % out)
            return 2
        state = json.load(open(paths["state"])) if os.path.exists(paths["state"]) else {}
        ok = print_checks(verify(
            pulls, read_ndjson(paths["reviews"]), read_ndjson(paths["rcs"]),
            read_ndjson(paths["ics"]), state.get("authoritative_count"),
            state.get("newest_number"), state.get("missing", []),
            state.get("dropped_issue_comments", 0)))
        return 0 if ok else 1

    token = os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN")
    if not token:
        sys.stderr.write("set GITHUB_TOKEN (or GH_TOKEN) to a token with repo read access\n")
        return 2

    gate = RateGate(qps=args.qps, verbose=not args.quiet)
    cache = Cache(os.path.join(out, "cache"), enabled=not args.no_cache)
    client = Client(token, cache, gate, args.repo, verbose=not args.quiet)
    workers = max(1, min(args.concurrency, 16))
    started = now_utc()
    scraped_at = iso(started)

    sys.stderr.write("scraping %s -> %s\n" % (args.repo, out))
    if args.limit:
        sys.stderr.write("  smoke mode: %d newest PRs\n" % args.limit)

    try:
        expected = None if args.limit else authoritative_pr_count(client, args.repo)
        if expected:
            sys.stderr.write("  authoritative PR count: %d\n" % expected)

        index = fetch_pr_index(client, args.repo, limit=args.limit)
        numbers = sorted(p["number"] for p in index)
        sys.stderr.write("  indexed %d PRs (#%d..#%d)\n" % (
            len(numbers), numbers[0], numbers[-1]) if numbers else "  indexed 0 PRs\n")
        newest = max(numbers) if numbers else None

        details, missing = fetch_details(client, args.repo, numbers, workers)
        reviews_raw, _ = fetch_reviews(client, args.repo, numbers, workers)

        since = None
        if args.limit and index:
            since = min(p["created_at"] for p in index)
        rcs_raw = fetch_bulk_comments(client, args.repo, "pulls", since)
        ics_raw = fetch_bulk_comments(client, args.repo, "issues", since)
        sys.stderr.write("  bulk: %d review comments, %d issue comments\n" % (
            len(rcs_raw), len(ics_raw)))
    except PolicyBlocked as e:
        sys.stderr.write("\nblocked by policy: %s\n"
                         "This path is not served in this session. Nothing to retry.\n" % e)
        return 3
    except GiveUp as e:
        sys.stderr.write("\ngave up: %s\n" % e)
        return 4

    by_index = {p["number"]: p for p in index}
    pulls = [trim_pull(details.get(n) or by_index[n], scraped_at) for n in numbers]
    nset = set(numbers)

    reviews = []
    for n, rl in reviews_raw.items():
        for r in rl or []:
            reviews.append(trim_review(r, n))

    rcs = [trim_review_comment(c) for c in rcs_raw]
    rcs = [c for c in rcs if c["pr_number"] in nset]
    ics_all = [trim_issue_comment(c) for c in ics_raw]
    ics = [c for c in ics_all if c["pr_number"] in nset]
    dropped_ics = len(ics_all) - len(ics)

    if not args.limit and not args.full and os.path.exists(paths["pulls"]):
        pulls = upsert(read_ndjson(paths["pulls"]), pulls, "number")
        reviews = upsert(read_ndjson(paths["reviews"]), reviews, "id")
        rcs = upsert(read_ndjson(paths["rcs"]), rcs, "id")
        ics = upsert(read_ndjson(paths["ics"]), ics, "id")

    rc_by, ic_by, rv_by = {}, {}, {}
    for c in rcs:
        rc_by.setdefault(c["pr_number"], []).append(c)
    for c in ics:
        ic_by.setdefault(c["pr_number"], []).append(c)
    for r in reviews:
        rv_by.setdefault(r["pr_number"], []).append(r)

    now = now_utc()
    rows = [derive_row(p, rv_by.get(p["number"], []), rc_by.get(p["number"], []),
                       ic_by.get(p["number"], []), now) for p in pulls]

    write_ndjson(paths["pulls"], pulls, "number")
    write_ndjson(paths["reviews"], reviews, "id")
    write_ndjson(paths["rcs"], rcs, "id")
    write_ndjson(paths["ics"], ics, "id")
    write_csv(paths["csv"], rows)

    checks = verify(pulls, reviews, rcs, ics, expected, newest, missing, dropped_ics,
                    strict=not args.limit)
    ok = print_checks(checks)

    watermark = max((p["updated_at"] or "" for p in pulls), default="")
    write_json(paths["state"], {
        "schema": 1,
        "repo": args.repo,
        "authoritative_count": expected,
        "newest_number": newest,
        "watermark_updated_at": watermark,
        "missing": sorted(missing),
        "dropped_issue_comments": dropped_ics,
        "completed": sorted(p["number"] for p in pulls),
    })
    write_json(paths["manifest"], {
        "repo": args.repo,
        "started_at": scraped_at,
        "finished_at": iso(now_utc()),
        "duration_seconds": round((now_utc() - started).total_seconds(), 1),
        "requests_made": client.requests,
        "cache_revalidated_304": cache.revalidated,
        "rate_limit_header": gate.limit,
        "rate_limit_remaining_low_water": gate.remaining,
        "token_source": "GITHUB_TOKEN" if os.environ.get("GITHUB_TOKEN") else "GH_TOKEN",
        "counts": {"pulls": len(pulls), "reviews": len(reviews),
                   "review_comments": len(rcs), "issue_comments": len(ics)},
        "checks": [c.as_dict() for c in checks],
        # Phases run at different instants, so an actively-updating open PR can be
        # internally inconsistent across files. Stated, not pretended away.
        "snapshot_is_not_transactional": True,
    })

    sys.stderr.write("\n%d requests (%d served by 304), %.0fs, limit header %s\n" % (
        client.requests, cache.revalidated,
        (now_utc() - started).total_seconds(), gate.limit))
    sys.stderr.write("wrote %s\n" % out)
    return 0 if ok else 1


def _csv_rows(path):
    if not os.path.exists(path):
        return []
    with open(path, newline="") as fh:
        out = []
        for r in csv.DictReader(fh):
            r["number"] = int(r["number"])
            out.append(r)
        return out


if __name__ == "__main__":
    sys.exit(main())
