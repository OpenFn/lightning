# RFC: Error signature strings

**Status:** draft for discussion. **Audience:** technical and non-technical.

## 1. Goal

Grouping failures by a single field (outcome, or the short error label) is already
possible, and it is already too coarse: one `failed / TypeError` bucket can hold a
hundred unrelated bugs across fifty workflows. This RFC proposes an **error signature**:
one short string per **root cause**, precise enough that "group by signature" returns
roughly one row per thing a person actually has to fix.

## 2. Terms

| Term | Meaning |
| --- | --- |
| **Work order** | One end-to-end attempt to process one incoming item of data. |
| **Run** | One execution of a work order. A retry creates a new run. |
| **Step** | One job executing inside a run. |
| **Job** | One unit of user-written code in a workflow. |
| **Adaptor** | The connector library a job uses to reach an external system, with a version, e.g. `salesforce@4.2.1`. |
| **Worker** | The separate service that actually runs job code and reports back to Lightning. |
| **Exit reason** | How a step or run ended: `success`; `fail`; `crash`; `kill`; `cancel`; `exception`. |
| **Error type** | The short label the worker sends alongside the exit reason, e.g. `TypeError`, `OOMError`. |
| **Source map** | A lookup that translates a position in machine-prepared code back to the line the user actually wrote. |

## 3. The vocabulary we already have

The worker raises a fixed set of typed errors. Each one declares a **severity**, which
becomes the exit reason, and a name. So the vocabulary is real and complete today; it is
simply undocumented on the Lightning side.

One subtlety matters for every option below. The label Lightning stores is chosen as
`subtype` first, then `type`, then `name` (`packages/ws-worker/src/api/reasons.ts`). For
the two most common classes the subtype wins, so Lightning never sees the words
"RuntimeError" or "RuntimeCrash"; it sees the underlying JavaScript error name instead.

| Worker error class | Exit reason | `error_type` Lightning stores | Raised by | Plain-English cause |
| --- | --- | --- | --- | --- |
| `RuntimeError` | `fail` | `TypeError`, `RangeError` | runtime | User code hit a bad value, e.g. reading a field of something missing. |
| `AdaptorError` | `fail` | `AdaptorError` | runtime | The connector library reported a failure. |
| `JobError` | `fail` | `JobError` | runtime | User code deliberately threw an error. |
| (error written to state) | `fail` | the thrown error's own name | job state | An error the adaptor recorded rather than threw. |
| `RuntimeCrash` | `crash` | `ReferenceError`, `SyntaxError` | runtime | Code is broken, not just unlucky: undefined variable, bad syntax. |
| `ImportError` | `crash` | `ImportError` | runtime | An adaptor or module could not be loaded. |
| `ValidationError` | `crash` | `ValidationError` | runtime | The workflow or compiled job failed validation. |
| `EdgeConditionError` | `crash` | `EdgeConditionError` | runtime | A custom condition between two steps errored. |
| `InputError` | `crash` | `InputError` | runtime | The input given to the run was unusable. |
| `CompileError` | `crash` | `CompileError` | engine | Job code failed to compile. |
| `ExitError` | `crash` | `ExitError` | engine | The child process died with an exit code. |
| `SecurityError` | `kill` | `SecurityError` | runtime | Disallowed operation detected, e.g. `eval`. |
| `TimeoutError` | `kill` | `TimeoutError` | runtime | One job exceeded its time limit. |
| `TimeoutError` | `kill` | `TimeoutError` | engine | The whole workflow exceeded its time limit. |
| `StateTooLargeError` | `kill` | `StateTooLargeError` | runtime | Data passed between steps exceeded the size limit. |
| `OOMError` | `kill` | `OOMError` | engine | The run exceeded its memory allowance. |
| `ExecutionError` | `exception` | `ExecutionError` | engine | Catch-all: something in our platform went wrong. |
| `AutoinstallError` | `exception` | `AutoinstallError` | engine | We failed to install the adaptor the job asked for. |
| `CredentialLoadError` | `exception` | `CredentialLoadError` | engine | We could not load a credential for the step. |

Lightning adds a few of its own, with no worker involved: `LostAfterClaim`,
`LostAfterStart` and `UnknownReason` (a run that stopped reporting), and the `rejected`
state, which means we accepted incoming data but created no run at all because the
project had hit its run limit.

**Three ambiguities to note now, because they blunt any signature:**

1. `TimeoutError` + `kill` means either "one job was too slow" or "the whole workflow
   was too slow". These have different fixes. The worker knows which via a `source`
   field (`runtime` or `engine`) that is not sent to Lightning.
2. Three different classes all report `ValidationError`.
3. `RuntimeError` and `RuntimeCrash` are distinguishable only by exit reason, because
   both are flattened to their JavaScript subtype. So **exit reason and error type must
   always travel together**; neither alone identifies the class.

## 4. What we could put in a signature

| Field | Status |
| --- | --- |
| Exit reason, error type (step and run) | **In our database now.** |
| Job id (stable across edits and renames), job name, adaptor and version, workflow, project | **In our database now.** |
| Trigger kind (webhook, cron, Kafka); position of the failing step | **In our database now.** |
| Error message | **In our database now, in two indirect places.** The worker always writes a final log line in the exact form `"{error_type}: {error_message}"` from source `R/T`, so it is parseable with a reliable anchor rather than by guesswork. |
| Line number, column, and the failing line of source code | **In our database now for `fail`-severity errors only.** The worker writes the full error, source-mapped back to the user's own code, into the step's saved output data under `errors.<step id>`. Not present for crashes and kills, and absent when a project disables data storage. |
| Same, for crashes and kills | Computed by the worker, thrown away in transit. The message field is accepted by Lightning and then dropped: the database column is still commented out in the schema and its migration. |
| Adaptor operation name, remediation hint, filtered stack trace | Computed by the worker, not sent. |
| Blame class (ours, the user's, the data's, a third party's) | Not stored, but derivable today by a fixed lookup from the table in §3. |
| External status codes, e.g. HTTP 401 | Only inside a nested `details` blob, unnormalised. Needs adaptor-side work. |

The headline: **a line number for the most common failure class is already sitting in our
database**, and the error message is recoverable from a predictably formatted log line.
The precise options below are therefore much closer to hand than they first appear.

## 5. Could build now: the precise options

All examples describe the same incident: job `Map-to-FHIR` read a field of a missing
object on line 42.

| # | Format | Example | Pros | Cons |
| --- | --- | --- | --- | --- |
| **A** | Reason and type as a pair | `fail:TypeError` | Correctly treats the pair as the unit of meaning, which fixes the `RuntimeError`/`RuntimeCrash` collision. | Still one bucket per error kind across the whole platform. Too coarse to act on. |
| **B** | Pair + place | `fail:TypeError @ Map-to-FHIR` | First actionable level; grouped on job id it survives renames and edits. | A job with three different `TypeError` bugs still collapses to one row. |
| **C** | Pair + place + position | `fail:TypeError @ Map-to-FHIR:42:18` | Close to one row per root cause; points a person straight at the line. | Available now only for `fail` severities; and any edit above line 42 silently splits the group's history. |
| **D** | Pair + place + normalised message | `fail:TypeError @ Map-to-FHIR "cannot read property 'id' of undefined"` | Separates distinct bugs in one job without being tied to line numbers; readable without opening the run. | Messages must be scrubbed of ids, values, URLs and secrets or every occurrence becomes its own group. |
| **E** | Blame-classified | `user:fail:TypeError @ Map-to-FHIR` | Separates our faults from users' and third parties', which is what makes a service-health chart trustworthy. Needs no new data, only an agreed lookup from §3. | The mapping needs sign-off, and a few classes are genuinely ambiguous. |
| **F** | Adaptor-resolved | `fail:AdaptorError @ Map-to-FHIR › salesforce@4.2.1 upsert()` | Catches "this broke on the new adaptor version", a common real cause. | Operation name is not transmitted yet, so today this stops at the adaptor version. |
| **G** | Propagation-aware | `crash:ReferenceError @ Map-to-FHIR (step 2 of 5, 3 steps skipped)` | Shows blast radius, which distinguishes "one record failed" from "the workflow stopped dead". | Longer; the skipped-step count is derived, so it must be computed consistently. |
| **H** | Short stable fingerprint | `sig_7f3a9c2` plus a human label | One value to group, filter, share in a ticket and select for bulk reprocessing. Immune to renames and message churn. | Meaningless to a human on its own, so it must always be rendered with its label. |

## 6. Could build later

| # | Format | Needs | Pros | Cons |
| --- | --- | --- | --- | --- |
| **I** | Position for every severity: `crash:ReferenceError @ Map-to-FHIR:42` | Restore the dropped `error_message` column; add `source` and `pos` to the worker's completion message. | Extends §5's option C to crashes, kills and exceptions, and removes the ambiguities in §3. Small, well-understood change on both sides. | Cross-repo coordination, and messages must be scrubbed before storage. |
| **J** | Remediation-aware: `… fix: "Ensure job code has been compiled"` | Transmit the worker's existing `fix` hint. | The worker already writes human remediation advice for several classes and we discard it. | Only some classes provide it. |
| **K** | External-system detail: `fail:AdaptorError @ salesforce.upsert → HTTP 401` | Structured error metadata from adaptors. | Best possible signal for on-call: distinguishes "their system refused us" from "our code is wrong". | Requires changes across many adaptors; largest scope here. |

## 7. Top three and recommendation

The three that carry the most value are **E** (blame class), **D** (normalised message)
and **H** (stable fingerprint). They are not alternatives; they are one signature seen at
different lengths.

**Recommendation: one stable key, one human rendering.**

```
key      = hash(blame, exit_reason, error_type, job_id, normalised_message)
rendered = user:fail:TypeError @ Map-to-FHIR [salesforce@4.2.1]
           "cannot read property 'id' of undefined"    (line 42)
```

Deliberate choices in that shape:

- **Exit reason and error type are always paired.** Neither alone identifies the cause.
- **Blame class leads**, so a service-health view is a filter on the signature rather
  than a separate metric.
- **Grouped on `job_id`, displayed with the job name.** Renames do not split history.
- **Line number is displayed but excluded from the key.** Otherwise editing a comment
  above the failing line invents a "new" root cause and resets its trend.
- **The normalised message is in the key**, so two distinct bugs in one job stay apart.

Truncating the same key gives every level we need: blame alone for health; blame plus
reason and type for triage; the full key for "fix this once" and "reprocess all of these".

**Build in this order:**

1. Write down the §3 table as a checked-in mapping from error type to blame class, with
   an explicit bucket for unrecognised labels so new worker errors surface loudly rather
   than silently.
2. Compute and store the key for every failed work order, including a signature for
   `rejected` ones so that class stops being invisible.
3. Extract the normalised message from the worker's final `R/T` log line, and the line
   number from saved step output where present.
4. Expose "group by signature" in history filters and on the project dashboard.
5. Then do **I**: restore the dropped message column and add `source` and position to the
   worker's completion message. That single change removes all three ambiguities in §3
   and makes the line number reliable for every failure, not just fails.
