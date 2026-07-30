# RFC: Error signature strings

**Status:** draft for discussion. **Audience:** technical and non-technical.
Section 3 is a reference table; readers who only want the proposal can skip to section 5.

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
| **Blame** | Who has to act to make the failure stop. See section 3. |

## 3. The vocabulary we already have

The worker raises a fixed set of typed errors. Each declares a severity, which becomes
the exit reason, and a name, which becomes the error type. The vocabulary is real and
already flowing into our database; it is simply undocumented on the Lightning side. Every
row below is verified against worker source.

### Where the error type comes from

The label is chosen by three different mechanisms depending on where the failure is
recorded:

| Recorded on | How the label is chosen | You get |
| --- | --- | --- |
| A **step** that ended in `fail` | the name saved in the step's own error record | the **class name**, e.g. `RuntimeError` |
| A **step** that ended any other way | the underlying error's subtype, falling back to its name | the **JavaScript name**, e.g. `ReferenceError` |
| A **run**, any ending | the error's type, falling back to its name | the **class name**, e.g. `RuntimeCrash` |

Three things follow, and all three are ordinary implementation constraints rather than
blockers:

1. **A signature has to say which level it reads.** A step and its run can hold different
   error types for the same incident: a broken-code failure is `ReferenceError` on the
   step and `RuntimeCrash` on the run. This RFC reads the **step**, which is also the only
   level that knows which job failed.
2. **On `fail`, the useful detail is in the message, not the label.** The label says
   `RuntimeError` for every bad-value error on the platform; the specific JavaScript name
   sits in the message, prefixed, as `RuntimeError: TypeError: …`. So a signature needs
   the message to tell distinct bugs apart.
3. **The label set is open.** `crash` is the fallback whenever nothing more specific is
   known, and the label can be any JavaScript name, the literal `ERROR`, or empty. A
   signature needs a deliberate bucket for values we do not recognise.

### Blame

Blame answers "who has to act", which is what makes a health chart trustworthy: it
separates our failures from everyone else's. Five values cover the vocabulary:

| Blame | Meaning | Who acts |
| --- | --- | --- |
| **Platform** | Something in OpenFn went wrong. | Us. |
| **Workflow** | The job's code or configuration is wrong. | The project team. |
| **Data** | The incoming data was not what the job expected. | Whoever sends the data. |
| **Remote** | The external system refused or failed. | The third party, or the project team's account with them. |
| **Limit** | A configured ceiling was hit: time, memory or size. | Either: make the job leaner, or raise the ceiling. |

**Blame is a property of the whole row, not of the error type.** The same label can carry
different blame depending on how the run ended: `ExecutionError` appears twice below, once
as a `crash` we believe is not our fault and once as an `exception` that is. So any blame
lookup must be keyed on the exit reason and error type **together**.

Two rows below are marked "Workflow or Data". That ambiguity is real and worth keeping
visible rather than resolving arbitrarily; a bad-value error usually means the data was
unexpected *and* the code did not defend against it.

### The table

| Error class | Exit reason | Error type (step / run) | Plain-English cause | Blame |
| --- | --- | --- | --- | --- |
| `RuntimeError` | `fail` | `RuntimeError` / same | User code hit a bad value, e.g. reading a field of something that is missing. | Workflow or Data |
| `AdaptorError` | `fail` | `AdaptorError` / same | A connector library failed. Attributed by inspecting the stack, so a bug in any bundled library lands here too. | Remote |
| `JobError` | `fail` | `JobError` / same | Fallback for any error we could not classify, including errors a job threw on purpose. | Workflow or Data |
| adaptor-written | `fail` | whatever name was written | An error a connector recorded rather than threw. Indistinguishable from the rows above except by its label. | Remote |
| `RuntimeCrash` | `crash` | `ReferenceError`, and others / `RuntimeCrash` | Code is broken, not just unlucky: an undefined variable, for example. | Workflow |
| `ImportError` | `crash` | `ImportError` / same | A named adaptor or module could not be loaded. | Workflow or Platform |
| `ValidationError` | `crash` | `ValidationError` / same | The workflow failed validation before anything ran, so no step exists. | Workflow |
| `EdgeConditionError` | `crash` | `EdgeConditionError` / same | A custom condition between two steps errored. The original error type and position are lost. | Workflow |
| `CompileError` | `crash` | `CompileError` / same | Job code failed to compile. Happens before any step runs, so no step exists. | Workflow |
| `ExitError` | `crash` | `ExitError` / same | The process running the job died with an exit code. | Platform |
| `ExecutionError` | `crash` | `ExecutionError` / same | An uncaught background error, usually inside adaptor code. | Remote |
| untyped throw | `crash` | JavaScript name, `ERROR`, or empty | Anything thrown that did not declare how serious it was. | Unclassified |
| `InputError` | — | **cannot occur** | Unreachable: gated on a setting no caller ever enables. | — |
| `SecurityError` | `kill` | `SecurityError` / same | Job code tried to generate and run new code, e.g. `eval`. | Workflow |
| `TimeoutError` (engine) | `kill` | `TimeoutError` / same | The run exceeded its time limit. Also catches runs whose real error was never reported. | Limit |
| `TimeoutError` (runtime) | — | **cannot occur** | Unreachable: no per-job time limit is ever set, only a per-run one. | — |
| `StateTooLargeError` | `kill` | `StateTooLargeError` / same | The data at the end of a step exceeded the size limit. | Limit |
| `OOMError` | `kill` | `OOMError` / same | The run exceeded its memory allowance. | Limit |
| `ExecutionError` | `exception` | `ExecutionError` / same | Catch-all for a failure inside OpenFn before the job could run. | Platform |
| `AutoinstallError` | `exception` | `AutoinstallError` / same | We could not install the adaptor the job asked for. | Platform or Workflow |
| `CredentialLoadError` | `exception`, or `crash` | `CredentialLoadError` / same | A credential could not be loaded. Expired sign-ins are recorded as `crash` on the run and `exception` on the step. | Workflow |
| `DataClipError` | `exception` | `DataClipError` / same | The run's input data could not be loaded. | Platform |

### Lightning's own values, with no worker involved

| Value | Where | Meaning | Blame |
| --- | --- | --- | --- |
| `LostAfterClaim`, `LostAfterStart` | run error type, state `lost` | A run passed its deadline without finishing. Triggered by the deadline, not by silence, so a run still writing logs can be marked lost. | Platform |
| `UnknownReason` | run error type | Unreachable: the query that would produce it cannot select a run in that state. | — |
| `cancelled` | run state | A queued run was cancelled before starting. Never has an error type. | Not a failure |
| `lost` steps | step exit reason | Steps swept when their run was lost. No error type. | Platform |
| `rejected` | work order state | Data was accepted but no run was created, because the project hit its run limit. **No run exists, so there are no error fields at all.** Requires a commercial usage-limiter extension, and only via webhook or Kafka. | Limit |

### Known soft spots, for the worker team

These do not block the proposal, but each one costs us grouping accuracy:

- A step and its run can report different error types for the same incident.
- Out-of-memory detection at the process level depends on error output having buffered by
  the time the process exits; otherwise the run is recorded as `crash` / `ExitError`
  instead. Its tests are skipped or flaky.
- The process exit code is stripped in transit and survives only inside log text.
- The fallback severity differs by code path (`crash` in some places, `exception` in
  others), and the shared base class ships a placeholder value that would be stored
  verbatim as an exit reason we do not recognise.

## 4. What we could put in a signature

Examples describe one incident: a webhook-triggered work order on workflow "Patient sync",
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
| Position for crashes, kills and exceptions | Computed, then dropped in transit. The message is accepted by Lightning and discarded, because the column is still commented out; the run-level message is not even accepted. | would be: `"ReferenceError: patient is not defined"` + `{line:42}` |
| Remediation hint and stack trace | Never stored. The hint exists on only two classes, both crashes, so it is never saved. The stack is dropped by how the error is copied. | would be: `fix: "Ensure job code has been compiled…"` |
| Blame | Not stored. Derivable today from the exit reason and error type together. | would be: `blame="workflow"` |
| External status codes, e.g. HTTP 401 | Only inside an unnormalised nested blob whose keys each adaptor sets for itself. | would be: `errors["7f3a9c2e…"].details = {"statusCode":401}` |

**Three caveats that shape the options below.**

- **Line numbers are patchier than they look.** `JobError`, one of the two commonest
  `fail`s, has no position at all. Adaptor errors carry a line and an operation name but
  no column; everything else carries the reverse. And positions live in saved step output,
  which retention policy later empties, so a key built on them would decay over time.
- **Some failures have no step**, and therefore no job id: validation and compile failures
  happen before anything runs. They need a workflow-level signature.
- **A mid-workflow `fail` whose downstream step succeeds reports the run as `success`**
  while the step stays `fail`. Run-level grouping silently loses these.

## 5. Could build now

| # | Format | Example | Pros | Cons |
| --- | --- | --- | --- | --- |
| **A** | Reason and type as a pair | `fail:RuntimeError` | The correct minimum unit: it is what blame can be derived from. | Still one bucket per error kind platform-wide. For `fail`s the specific JavaScript name is not in it. |
| **B** | Pair + place | `fail:RuntimeError @ Map-to-FHIR` | First actionable level; grouped on job id it survives renames and edits. | Three unrelated bugs in one job still collapse into one row. |
| **C** | Pair + place + position | `fail:RuntimeError @ Map-to-FHIR:42:18` | Points a person straight at the line. | Unavailable for `JobError`, for all crashes and kills, and after retention expiry. Any edit above line 42 splits the group's history. |
| **D** | Pair + place + normalised message | `fail:RuntimeError @ Map-to-FHIR "cannot read property 'id' of undefined"` | The only option that recovers the JavaScript name on `fail`s, since the message is prefixed with it. Not tied to line numbers, and works for every severity. | Messages must be scrubbed of ids, values and secrets, or each occurrence becomes its own group. |
| **E** | Blame-classified | `workflow:fail:RuntimeError @ Map-to-FHIR` | Separates our failures from everyone else's, which is what a service-health chart needs. No new data required. | Needs the mapping in section 3 agreed and owned, and the `crash` versus `exception` split of `ExecutionError` decided deliberately. |
| **F** | Adaptor-resolved | `fail:AdaptorError @ Map-to-FHIR › salesforce@3.5.2 upsert()` | Catches "this broke on the new adaptor version". Buildable today for adaptor `fail`s, since the operation name is already saved. | Only for adaptor `fail`s; absent for every other class. |
| **G** | Propagation-aware | `crash:RuntimeCrash @ Map-to-FHIR (step 2 of 5, 3 steps skipped)` | Shows blast radius: one record lost versus the workflow stopped dead. | Nothing about skipped steps is recorded. It must be reconstructed, and cannot distinguish "skipped by crash" from "not taken by condition". |
| **H** | Short stable fingerprint | `sig_7f3a9c2` plus a human label | One value to group, filter, quote in a ticket and select for bulk reprocessing. Immune to renames and message churn. | Meaningless alone, so it must always render with its label. |

## 6. Could build later

| # | Format | Needs | Pros | Cons |
| --- | --- | --- | --- | --- |
| **I** | Position for every severity: `crash:RuntimeCrash @ Map-to-FHIR:42` | Restore the dropped message column on both the step and run handlers; carry position and subtype through the run-level message. | Extends option C to crashes and kills, and makes step and run agree. | Cross-repo. One class has no source to send, and messages need scrubbing before storage. |
| **J** | Remediation-aware: `… fix: "Ensure job code has been compiled…"` | Transmit the hint the worker already writes. | Free human remediation advice we currently discard. | Exists on only two classes today. |
| **K** | External-system detail: `fail:AdaptorError @ salesforce.upsert → HTTP 401` | Agreed structured error fields from adaptors. | Best signal for on-call: "their system refused us" versus "our code is wrong". | Every adaptor sets its own keys today, so this needs a convention across many repositories. |

## 7. Top three and recommendation

**D** (normalised message), **E** (blame class) and **H** (stable fingerprint). D is
load-bearing rather than optional: because `fail`s all report the same label, the message
is the only place the distinguishing detail exists.

**Recommendation: one stable key, one human rendering, anchored on the step.**

```
key      = hash(blame, exit_reason, error_type, job_id, normalised_message)
rendered = workflow:fail:RuntimeError @ Map-to-FHIR [salesforce@3.5.2]
           "cannot read property 'id' of undefined"    (line 42)
```

Each choice is forced by something in section 3 or 4:

- **Anchored on the step, not the run.** The two levels can hold different error types,
  and run-level grouping loses mid-workflow fails entirely.
- **Exit reason and error type always travel together**, because blame depends on both.
- **Grouped on job id, displayed with the job name**, so renames do not split history.
- **The normalised message is in the key.** It is the only way to separate the many
  distinct bugs that all report `RuntimeError`.
- **Line number is displayed but excluded from the key.** It is missing for `JobError`
  and all crashes, comes in two shapes, and expires with the saved output.

Truncating the same key gives every level we need: blame alone for health; blame with
reason and type for triage; the full key for "fix this once" and "reprocess all of these".

**Build in this order:**

1. Check in the section 3 table as a mapping from exit reason and error type to blame,
   with an explicit bucket for values we do not recognise, covering unrecognised exit
   reasons and empty error types as well.
2. Compute and store the key for every failed work order. Handle `rejected` and the
   no-step classes separately, since neither has the fields the key expects.
3. Extract the normalised message from the final log line, and the position from saved
   step output where present. Scrub ids, values and secrets: the saved source line
   reproduces user code, and the nested details blob is a verbatim third-party payload,
   so both can contain identifiers or secrets.
4. Expose "group by signature" in history filters and on the project dashboard.
5. Then do **I**, which makes step and run agree and makes position reliable everywhere.
