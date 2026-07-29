# RFC: Error signature strings

**Status:** draft for discussion. **Audience:** technical and non-technical.

## 1. The problem (in brief)

When a work order fails we record its outcome (`failed`, `crashed`, `killed`) and
sometimes a short error label. There is no single string we can group on to answer
"what is breaking most often, and where?". This RFC proposes candidate formats for
an **error signature**: one short, repeatable string per failed work order that we
can count, sort, filter and share.

## 2. Terms used below

| Term | Meaning |
| --- | --- |
| **Work order** | One end-to-end attempt to process one incoming item of data. |
| **Run** | One execution of that work order. A retry creates a new run. |
| **Step** | One job executing inside a run. A run has one step per job it reaches. |
| **Job** | One unit of user-written code in a workflow. |
| **Adaptor** | The connector library a job uses to reach an external system, with a version, e.g. `salesforce@4.2.1`. |
| **Outcome** | The final state we store. Runs: `success`; `failed`; `crashed`; `cancelled`; `killed`; `exception`; `lost`. Steps use short forms (`fail`, `crash`, `kill`, …). |
| **Error type** | A short label the worker may send, e.g. `OOMError`; `TimeoutError`; `SecurityError`; `ImportError`; `StateTooLargeError`. Today it is free text, not a fixed list. |

## 3. What we already have, and what we do not

**Available today, no new data needed:** outcome at work order, run and step level;
error type; the failing job's id, name and adaptor version; the workflow and project;
the position of the failing step; and every log line the run produced.

**Not available today:** the worker sends an `error_message`, but we throw it away
(the database column is still commented out in the schema and migration). We also
have no line or column numbers, no adaptor operation name, and no external status
codes. And error type is uncontrolled free text, so new labels appear without notice.

## 4. Could build now

All seven use only data we already store. Examples describe the same incident: a job
called `Map-to-FHIR` was stopped because it ran out of memory.

| # | Format | Example | Pros | Cons |
| --- | --- | --- | --- | --- |
| **A** | Outcome only | `failed` | Trivial; already on every work order. | Answers almost nothing; we can already do this. |
| **B** | Outcome + cause | `failed / OOMError` | Cheap; small stable set; ideal top-line health metric. | Says nothing about which workflow or job; error type is optional, so an unhelpfully large "no cause given" bucket is likely (worth measuring before we commit). |
| **C** | Failing step's outcome + cause | `kill / OOMError` | More precise than the run-level view, which flattens detail; distinguishes "the job failed" from "the platform stopped it". | Two vocabularies (`kill` vs `killed`) to explain; still no location. |
| **D** | + place | `kill / OOMError @ Map-to-FHIR` | The first format that points at something fixable; readable in a chart legend. | Job names are not unique across projects; renaming a job splits its history. |
| **E** | + adaptor and version | `kill / OOMError @ Map-to-FHIR [salesforce@4.2.1]` | Exposes "this broke on the new adaptor version", a common real cause. | Longer; version churn fragments groups unless we also group on major version. |
| **F** | Stable fix key | `<workflow id>/<job id>/kill/OOMError` | Survives renames and edits; one row per genuinely broken thing; the natural key for "reprocess all of these" and "fix this once". | Unreadable to humans, so it needs a friendly label rendered beside it. |
| **G** | + normalised log detail | `kill / OOMError @ Map-to-FHIR: "TypeError: cannot read property 'id' of undefined"` | Highest resolution buildable now; usually enough to fix without opening the run. | Needs text extraction and scrubbing (ids, timestamps, URLs, secrets) or groups shatter; the most build effort in this section, and log retention limits history. |

**Coverage gap worth closing in the same change:** some work orders are marked
`rejected`, meaning we accepted the incoming data but created no run at all because the
project had hit its run limit. These have no step and no error type, so they need a
signature of their own, such as `rejected / RunLimitReached`. Without one, a whole class
of "nothing happened to my data" disappears from every chart.

## 5. Could build later

These need new data, a new agreed vocabulary, or worker changes.

| # | Format | Example | Pros | Cons |
| --- | --- | --- | --- | --- |
| **H** | Controlled vocabulary plus a "whose problem is it" class | `platform : OOMError`, `user : DataShapeError`, `remote : AuthError` | Directly answers "are our services working?" by separating our faults from users' and third parties'; makes charts trustworthy. | Requires agreeing and governing a fixed list, plus mapping today's free-text labels onto it. |
| **I** | Persist the error message and code position | `RuntimeError in Map-to-FHIR @ line 42` | Pinpoints the broken line; the tightest loop from alert to fix. | Needs the dropped `error_message` column restored, a worker contract for line numbers, and care that messages never carry sensitive data. |
| **J** | Adaptor operation and external response | `AdaptorError @ salesforce.upsert → HTTP 401` | Separates "their system rejected us" from "our code is wrong"; strongest signal for on-call. | Adaptors must emit structured error detail; a cross-repo change across many adaptors. |

## 6. Top three, and the recommendation

The three that carry the most value per unit of work are **B** (health), **D/E**
(diagnosis) and **F** (fix and reprocess). They are not competitors; they are the same
string at three lengths.

**Recommendation: store one key, display three resolutions.**

Store a structured key on each failed work order built from data we already have:

```
outcome · error_type · job_id · adaptor
```

Then derive three display levels by truncating it, so one field serves every question:

| Level | Shown as | Answers | Key result |
| --- | --- | --- | --- |
| 1 | `failed / OOMError` | Is the service healthy? What is trending? | 1.1 |
| 2 | `kill / OOMError @ Map-to-FHIR [salesforce@4.2.1]` | What is wrong with this workflow? | 1.2 |
| 3 | full key, grouped on ids | Which cases share one root cause; reprocess or fix them together. | 2.1, 2.2 |

Truncation is what makes this worth doing: teams get one vocabulary instead of three
competing ones, and a chart can be drilled into rather than rebuilt.

**Build first, in order:**

1. Compute and store the key for every failed work order, plus a signature for rejected
   ones so nothing is uncounted.
2. Give absent error types an explicit label (for example `Unspecified`) rather than
   leaving a blank bucket.
3. Expose "group by signature" in history filters and in the project dashboard.
4. Then take **H** (controlled vocabulary) and **I** (store the error message): together
   they shrink the `Unspecified` bucket and turn level 3 into a line number.

Option **G** is deliberately deferred. It is the most useful string to a person
debugging, but it is the only "now" option that depends on parsing free text, and it is
better added once the stored key exists to hang it from.
