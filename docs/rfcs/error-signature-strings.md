# RFC: Error signature strings

**Status:** draft for discussion. **Audience:** technical and non-technical.
Sections 3 and 4 are a verified reference table and are longer than the rest; readers
who only want the proposal can skip to section 5.

## 1. Goal

Grouping failures by a single field (outcome, or the short error label) is already
possible, and it is already too coarse: one `fail` / `RuntimeError` bucket can hold a
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
| **Adaptor** | The connector library a job uses to reach an external system, with a version. Stored as a full package name such as `@openfn/language-salesforce@3.5.2`; shortened to `salesforce@3.5.2` below for readability. |
| **Worker** | The separate service that runs job code and reports back to Lightning. Internally it has a **runtime** (executes one job) and an **engine** (manages the whole run). |
| **Exit reason** | How a step or run ended: `success`; `fail`; `crash`; `kill`; `cancel`; `exception`. |
| **Error type** | The short label stored next to the exit reason, e.g. `RuntimeError`, `OOMError`. |
| **Source map** | A lookup that translates a position in machine-prepared code back to the line the user actually wrote. |

## 3. The vocabulary we already have

The worker raises typed errors, each declaring a **severity** that becomes the exit
reason. Every row below was checked against worker source by four independent reviewers
tasked with disproving it. The **Subtlety** column records what a worker maintainer needs
to know; several rows are only correct by accident, and two cannot happen at all.

**The error type is produced by three different mechanisms, not one.** This is the single
most important thing in this document, and it was wrong in earlier drafts:

| Where | How the label is chosen | Consequence |
| --- | --- | --- |
| **Step**, exit reason `fail` | `state.errors[<job id>].name` | You get the **class name**, e.g. `RuntimeError`. |
| **Step**, any other reason | `subtype \|\| type \|\| name` | You get the **underlying JavaScript name**, e.g. `ReferenceError`. |
| **Run**, any reason | `type \|\| name \|\| 'ERROR'` | You get the **class name**, because the run-level message carries only `{type, message, severity}` and drops `subtype`. |

So **a step and its run can store different error types for the same incident.** A
reference error is `ReferenceError` on the step and `RuntimeCrash` on the run. Any
grouping must therefore state which level it keys on. This RFC keys on the **step**.

| Error class | Exit reason | Error type stored (step / run) | Plain-English cause | Subtlety a worker maintainer must know |
| --- | --- | --- | --- | --- |
| `RuntimeError` | `fail` | `RuntimeError` / same | User code hit a bad value, e.g. reading a field of something missing. | Stores the class name, never `TypeError`. The JS name survives only as the message prefix, `RuntimeError: TypeError: …`. |
| `AdaptorError` | `fail` | `AdaptorError` / same | The connector library failed. | Not adaptor-declared: the runtime sniffs the first non-runtime stack frame, so any `node_modules` throw becomes this, and a stackless one becomes `JobError`. |
| `JobError` | `fail` | `JobError` / same | Fallback for any error the classifier did not recognise. | Not "deliberately thrown": swallows `URIError`, custom classes and stackless adaptor throws. Carries **no position at all**. |
| adaptor-written to state | `fail` | whatever `name` was written | An error the adaptor recorded rather than threw. | Indistinguishable from the three rows above; only "not one of those three names" separates it. A missing `name` yields a null error type. |
| `RuntimeCrash` | `crash` | `ReferenceError`, and others / `RuntimeCrash` | Code is broken, not just unlucky: undefined variable. | Step and run disagree for one incident (kit issue #1004). The subtype set is open, not just `ReferenceError`/`SyntaxError`. |
| `ImportError` | `crash` | `ImportError` / same | An adaptor or module could not be loaded. | The only crash row where step and run agree, purely because its check is ordered before the crash wrapper. Unresolvable imports become `fail`/`JobError` instead. |
| `ValidationError` | `crash` | `ValidationError` / same | The workflow failed validation. | Only the base class reports this; its two same-named siblings get wrapped and report their own constructor names. Fails before any step, so **no step row exists**. |
| `EdgeConditionError` | `crash` | `EdgeConditionError` / same | A custom condition between two steps errored. | Destroys the underlying JS type and position. A condition that fails to *compile* is a separate `crash` / `Error`. |
| `CompileError` | `crash` | `CompileError` / same | Job code failed to compile. | Correct only by accident: its `subtype` (`SyntaxError`) is stripped at the engine boundary, and its own `name` is `SyntaxError`, not `CompileError`. No step row exists. |
| `ExitError` | `crash` | `ExitError` / same | The child process died with an exit code. | The exit code is stripped in transit and survives only inside the log text. Production hits a hand-rolled object, not the class. |
| `ExecutionError` | `crash` | `ExecutionError` / same | An uncaught asynchronous throw, usually in adaptor code. | The thread's uncaught-exception handler **overwrites** severity to `crash`, with the comment "likely not our fault". Same error type as the `exception` row below. |
| untyped throw | `crash` | JS constructor name, or `ERROR`, or **null** | Anything thrown without a declared severity. | `crash` is the default at three separate fallbacks, and one path omits `name` entirely, so the error type can be null. |
| `InputError` | — | **unreachable** | — | Dead code: gated on a `forceSandbox` flag that no caller ever sets. Drop the row or mark it dead. |
| `SecurityError` | `kill` | `SecurityError` / same | Disallowed code generation, e.g. `eval`. | Only catches one specific engine-level error. The same code inside an adaptor becomes `fail`/`AdaptorError`, and inside an edge condition `crash`/`EdgeConditionError`. |
| `TimeoutError` (engine) | `kill` | `TimeoutError` / same | The whole run exceeded its time limit. | The only reachable timeout. It also silently absorbs dead threads whose real error was never forwarded, so the root cause can be unrelated. |
| `TimeoutError` (runtime) | — | **unreachable** | Would be: one job exceeded its own limit. | The worker deliberately omits the per-job timeout option and only the command-line tool arms this timer. No per-job timeout exists in production. |
| `StateTooLargeError` | `kill` | `StateTooLargeError` / same | Data at the end of a step exceeded the size limit. | Extends the plain `Error` class, not the shared base, so it has no `source`. Thrown outside the step's error handling, so the step inherits the run's reason. |
| `OOMError` | `kill` | `OOMError` / same | The run exceeded its memory allowance. | Process-level detection depends on error output having buffered by the time the process exits; otherwise it degrades to `crash`/`ExitError`. Both tests are skipped or flaky. |
| `ExecutionError` | `exception` | `ExecutionError` / same | Catch-all: something in our platform went wrong before execution. | Only the pre-execution wrap keeps `exception`. See its `crash` twin above: one label, two blame classes. |
| `AutoinstallError` | `exception` | `AutoinstallError` / same | We failed to install the adaptor the job asked for. | Only the install call is guarded. Version lookup for `@latest` and repository setup failures surface as `exception`/`ExecutionError` instead. |
| `CredentialLoadError` | `exception`, or `crash` | `CredentialLoadError` / same | We could not load a credential for the step. | Expired-OAuth messages are pattern-matched and rewritten to `crash`, **and only on the run**; the step still reports `exception`. |
| `DataClipError` | `exception` | `DataClipError` / same | The run's input data could not be loaded. | Has no error class at all, just a hand-built object, so it is invisible to anyone reading the error definitions. |

**Lightning adds its own values, with no worker involved:**

| Value | Where | Subtlety |
| --- | --- | --- |
| `LostAfterClaim`, `LostAfterStart` | run error type, state `lost` | Triggered by a **deadline**, not by silence. A run still healthily writing logs past its deadline is marked lost. |
| `UnknownReason` | run error type | Dead code: the query that feeds it can never select a run in the state that would produce it. |
| `cancelled` | run state | Never has an error type. No worker error produces `cancel` at all; it is Lightning-only. |
| `lost` steps | step exit reason | Swept steps get the reason but no error type. |
| `rejected` | work order state | Not an error type and not a run state. **No run exists**, so there are no error fields whatsoever. Requires a commercial usage-limiter extension, and only via webhook or Kafka ingress. |

**The real ambiguities.** Earlier drafts of this RFC listed three; all three were wrong.
These four are verified:

1. **Step and run disagree.** Same incident, two different error types (`RuntimeCrash`,
   `CredentialLoadError`). Grouping must name its level.
2. **One label, two blame classes.** `ExecutionError` is both a `crash` "not our fault"
   and an `exception` "our fault". So blame must be derived from the **pair**
   (exit reason plus error type), never the label alone.
3. **The label set is open.** `crash` is the default at three fallbacks, and the error
   type can be any JavaScript constructor name, the literal `ERROR`, or null.
4. **Severity defaults are inconsistent.** Different boundaries default to `crash` or to
   `exception`, and the shared base class ships a placeholder `-` that would be stored
   verbatim as an exit reason we do not recognise.

## 4. What we could put in a signature

Examples describe one incident: webhook-triggered work order on workflow "Patient sync",
job `Map-to-FHIR` (`job_id=7f3a9c2e…`) using `salesforce@3.5.2`, reading a patient id on
line 42 of a record where that object is absent.

| Field | Status | Realistic example |
| --- | --- | --- |
| Exit reason and error type (step and run) | **In our database now.** | `exit_reason="fail"`, `error_type="RuntimeError"` |
| Job id (stable across edits and renames), job name, adaptor and version, workflow, project | **In our database now.** | `job_id=7f3a9c2e…`, `"Map-to-FHIR"`, `@openfn/language-salesforce@3.5.2` |
| Trigger kind | **In our database now**, except manual runs, which have no trigger. | `triggers.type=:webhook` |
| Position of the failing step | **Derived, not stored.** No ordinal column exists; order comes from start times. | `2nd of 5, by started_at` |
| Error message | **In our database now, indirectly.** The worker writes one final log line per run in the form `"{error_type}: {error_message}"`. | `source="R/T" level=info` `"RuntimeError: TypeError: Cannot read prop…"` |
| Line, column and the failing line of code | **In our database now, for `fail` errors only**, inside the step's saved output. | `errors["7f3a9c2e…"].pos = {"line":42,"column":18,"src":"  Id__c: p.patient.id,"}` |
| Adaptor operation name | **In our database now, for adaptor `fail`s**, on the same channel. | `errors["7f3a9c2e…"] = {"name":"AdaptorError","operationName":"upsert","line":42}` |
| Position for crashes, kills and exceptions | Computed, then dropped in transit. The message field is accepted by Lightning and discarded, because the column is still commented out; the run-level message is not even accepted. | would be: `"ReferenceError: patient is not defined"` + `{line:42}` |
| Remediation hint and stack trace | Never stored. The hint exists on only two classes, both crashes, so it is never written to state. The stack is dropped by an accident of how the error is copied. | would be: `fix: "Ensure job code has been compiled…"` |
| Blame class (ours, the user's, a third party's) | Not stored. Derivable today, but only from the **pair**, per ambiguity 2 above. | would be: `blame="user"` |
| External status codes, e.g. HTTP 401 | Only inside an unnormalised nested blob whose keys are set by each adaptor. | would be: `errors["7f3a9c2e…"].details = {"statusCode":401}` |

**Four caveats that shape the options below.**

- **`JobError` has no position at all**, and it is one of the two commonest `fail`s. So
  "we already have line numbers" is true for `RuntimeError` and `AdaptorError` only.
- **Position comes in two mutually exclusive shapes.** An operation-attributed adaptor
  error has `line` plus `operationName` and no column or source text; everything else has
  the full position and no operation name. Extraction must handle both.
- **Position data expires sooner than the step.** It lives in a dataclip, which retention
  policy later empties, and oversized data is dropped entirely. A key built on position
  would decay out from under itself.
- **A mid-workflow `fail` whose downstream leaf succeeds reports the run as `success`**
  while the step stays `fail`. Run-level grouping silently loses these.

## 5. Could build now

| # | Format | Example | Pros | Cons |
| --- | --- | --- | --- | --- |
| **A** | Reason and type as a pair | `fail:RuntimeError` | The correct unit: it resolves ambiguity 2, and at run level it is close to one-to-one with the error class. | Still one bucket per error kind platform-wide. For `fail`s the actionable JavaScript name is not in it. |
| **B** | Pair + place | `fail:RuntimeError @ Map-to-FHIR` | First actionable level; grouped on job id it survives renames and edits. | Three unrelated bugs in one job still collapse into one row. |
| **C** | Pair + place + position | `fail:RuntimeError @ Map-to-FHIR:42:18` | Points a person at the line. | Unavailable for `JobError`, for all crashes and kills, and after retention expiry. Any edit above line 42 splits the group's history. |
| **D** | Pair + place + normalised message | `fail:RuntimeError @ Map-to-FHIR "cannot read property 'id' of undefined"` | The only option that recovers the JavaScript name on `fail`s, since the message is prefixed with it. Not tied to line numbers. Available for every severity. | Messages must be scrubbed of ids, values and secrets, or each occurrence becomes its own group. |
| **E** | Blame-classified | `user:fail:RuntimeError @ Map-to-FHIR` | Separates our faults from users' and third parties', which is what makes a service-health chart trustworthy. Needs no new data. | Must key on the pair, not the label. A few classes are genuinely ambiguous, and the `crash`/`exception` split of `ExecutionError` needs a deliberate decision. |
| **F** | Adaptor-resolved | `fail:AdaptorError @ Map-to-FHIR › salesforce@3.5.2 upsert()` | Catches "this broke on the new adaptor version". Buildable today for adaptor `fail`s, since the operation name is already saved. | Only for adaptor `fail`s; absent for every other class. |
| **G** | Propagation-aware | `crash:RuntimeCrash @ Map-to-FHIR (step 2 of 5, 3 steps skipped)` | Shows blast radius: one record lost versus the workflow stopped dead. | Nothing about skipped steps is recorded. It must be reconstructed by comparing the workflow to the steps that exist, and cannot distinguish "skipped by crash" from "not taken by condition". |
| **H** | Short stable fingerprint | `sig_7f3a9c2` plus a human label | One value to group, filter, quote in a ticket and select for bulk reprocessing. Immune to renames and message churn. | Meaningless alone, so it must always render with its label. |

## 6. Could build later

| # | Format | Needs | Pros | Cons |
| --- | --- | --- | --- | --- |
| **I** | Position for every severity: `crash:RuntimeCrash @ Map-to-FHIR:42` | Restore the dropped message column on **both** the step and run handlers; carry position and `subtype` through the run-level message. | Extends option C to crashes and kills, and fixes ambiguity 1 at the same time. | Cross-repo. One class has no `source` to send, and messages need scrubbing before storage. |
| **J** | Remediation-aware: `… fix: "Ensure job code has been compiled…"` | Transmit the hint the worker already writes. | Free human remediation advice we currently discard. | Exists on only two classes today. |
| **K** | External-system detail: `fail:AdaptorError @ salesforce.upsert → HTTP 401` | Agreed structured error fields from adaptors. | Best signal for on-call: "their system refused us" versus "our code is wrong". | Every adaptor sets its own keys today, so this needs a convention across many repositories. |

## 7. Top three and recommendation

**D** (normalised message), **E** (blame class) and **H** (stable fingerprint). The
verification changed this ranking: because `fail`s store the class name and bury the
actionable JavaScript name in the message, **D is now load-bearing rather than optional**,
and C is a display detail rather than a key.

**Recommendation: one stable key, one human rendering, anchored on the step.**

```
key      = hash(blame, exit_reason, error_type, job_id, normalised_message)
rendered = user:fail:RuntimeError @ Map-to-FHIR [salesforce@3.5.2]
           "cannot read property 'id' of undefined"    (line 42)
```

Deliberate choices, each forced by a verified finding:

- **Anchored on the step, not the run.** Step and run store different error types, and
  run-level grouping loses mid-workflow fails entirely.
- **Exit reason and error type always travel together**, because one label can carry two
  different blame classes.
- **Blame is derived from the pair**, never from the label alone.
- **Grouped on job id, displayed with the job name**, so renames do not split history.
- **The normalised message is in the key.** It is the only way to tell apart the many
  distinct bugs that all report `RuntimeError`.
- **Line number is displayed but excluded from the key.** It is missing for `JobError`
  and all crashes, comes in two shapes, and expires with the dataclip.

**Build in this order:**

1. Check in the section 3 table as a mapping from (exit reason, error type) to blame
   class, with an explicit bucket for unrecognised values. That bucket must also cover
   unrecognised **exit reasons** and null error types, per ambiguities 3 and 4.
2. Compute and store the key for every failed work order. Handle `rejected` separately:
   it has no error fields at all, so it needs a synthetic signature.
3. Extract the normalised message from the final log line, and the position from saved
   step output where present. Scrub ids, values and secrets: the saved source line
   reproduces user code, and the nested details blob is a verbatim third-party payload,
   so both can contain identifiers or secrets.
4. Expose "group by signature" in history filters and on the project dashboard.
5. Then do **I**, which fixes ambiguity 1 and makes position reliable for every class.

**Worth raising with the worker team regardless of this RFC**, since each one costs us
signal today: the step-and-run error type divergence (kit issue #1004); the two
unreachable classes; the unreliable process-level out-of-memory detection; the stripped
process exit code; and the inconsistent severity defaults.
