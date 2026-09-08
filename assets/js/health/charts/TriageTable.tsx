import type { FailureSignature } from '../types';

/**
 * Failed work orders grouped by error signature, heaviest first. Each row
 * links to the history page filtered to the work orders it counts, where the
 * existing "retry all" can act on the group. The signature grammar is:
 * `exitReason:errorType [@ stepName [adaptor]]` — the adaptor renders without
 * its version, since a merged row can span more than one (see `job_id` on
 * `FailureSignature`).
 */

// One sentence per error type the worker can report, written to hold
// for every root cause behind that type — the codes are general, so the tip
// has to be too. `error_type` is not a closed enum — it is whatever the
// throwing layer set — so `default` catches whatever is unlisted.
const TIPS: Record<string, string> = {
  RuntimeError:
    "Job code hit a value it didn't expect, often a missing input field.",
  JobError: 'The job code intentionally threw this error.',
  AdaptorError: 'An error occurred while an adaptor operation was underway.',
  CompileError: "Job code couldn't be compiled, so no step ever ran.",
  RuntimeCrash:
    "Job code threw an error the runtime couldn't recover from, so the run was abandoned.",
  // The only two raw JS names that reach Lightning: `assertRuntimeCrash` wraps
  // exactly these, and the worker reports the wrapper's `subtype` over its
  // `name`, so `RuntimeCrash` only ever names a run-level failure. Every other
  // JS error is wrapped as a `RuntimeError` and reports under that name.
  ReferenceError:
    "Job code referred to something that doesn't exist, often a typo or a missing import.",
  SyntaxError:
    "Job code tried to parse text that wasn't in the format it expected, most often JSON.",
  ValidationError:
    "The workflow or a job isn't in a shape the runtime accepts, so nothing ran.",
  ImportError:
    "A module or adaptor the job imports couldn't be loaded, so nothing ran.",
  EdgeConditionError:
    "An edge condition failed to evaluate, so the run couldn't pick a next step.",
  InputError: "The run's starting input couldn't be used, so nothing ran.",
  DataClipError:
    "The run's input data couldn't be loaded, so no step ever started.",
  ExitError: 'The process running this workflow exited before finishing.',
  OOMError: "The run used more memory than it's allowed and was stopped.",
  StateTooLargeError:
    'The state passed between steps grew past its size limit.',
  TimeoutError: 'The run hit its time limit and was stopped part-way through.',
  SecurityError:
    "The job tried something the worker doesn't allow and was stopped.",
  AutoinstallError:
    "The adaptor this workflow needs couldn't be installed, so nothing ran.",
  CredentialLoadError:
    "A credential couldn't be loaded, so no step could authenticate.",
  ExecutionError:
    'Something failed inside OpenFn rather than in this workflow.',
  LostAfterClaim: 'The run was picked up but never started, so nothing ran.',
  LostAfterStart:
    'The run started but never reported back, so how far it got is unknown.',
  RunLimitExceeded:
    'The project was over its run limit, so no run was created for this request.',
  default: 'The step failed without a recognised error type; check its logs.',
};

interface TriageTableProps {
  signatures: FailureSignature[];
  emptyMessage: string;
  projectId: string;
  workflowId: string;
  /** `window.from` off the same response — the picked range's start. */
  from: string;
}

export const TriageTable = ({
  signatures,
  emptyMessage,
  projectId,
  workflowId,
  from,
}: TriageTableProps) => {
  if (signatures.length === 0) {
    return <p className="text-sm text-gray-500">{emptyMessage}</p>;
  }

  return (
    // Capped in height rather than in rows: the tail is still worth reading,
    // just not worth pushing the rest of the page down for. `max-h` over a
    // row count so a short list keeps the card short.
    //
    // `-mr-6 pr-4` bleeds the scroll region out to the card's own edge (the
    // card is `p-6`), so the scrollbar sits flush against it instead of
    // floating in the middle of the card's padding.
    <div className="-mr-6 max-h-96 overflow-y-auto pr-4">
      <table className="w-full text-left text-sm">
        <thead className="sticky top-0 z-10 bg-white">
          <tr className="border-b border-gray-200 text-xs uppercase tracking-wide text-gray-500">
            <th scope="col" className="w-28 py-2 pr-4 font-medium">
              Work orders
            </th>
            <th scope="col" className="py-2 font-medium">
              Signature
            </th>
            <th scope="col" className="w-24 py-2 pl-4 font-medium">
              <span className="sr-only">Actions</span>
            </th>
          </tr>
        </thead>
        <tbody>
          {signatures.map(signature => (
            // job_id joins the key: a job deleted and recreated with the same
            // name reads as two identical-looking signatures otherwise.
            <tr
              key={[
                signature.exit_reason,
                signature.error_type,
                signature.step_name,
                signature.adaptor,
                signature.job_id,
              ].join('|')}
              className="border-b border-gray-100 last:border-0"
            >
              <td className="py-3 pr-4 tabular-nums text-gray-900">
                {signature.count.toLocaleString()}
              </td>
              <td className="py-3 align-top">
                <Signature signature={signature} />
                <p className="mt-1">
                  <span className="font-medium text-gray-500">Tip: </span>
                  <span className="text-gray-600">{tipFor(signature)}</span>
                </p>
              </td>
              <td className="py-3 pl-4 text-right">
                <ViewButton
                  signature={signature}
                  projectId={projectId}
                  workflowId={workflowId}
                  from={from}
                />
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
};

/**
 * Lands on history filtered to exactly the work orders this row counts, where
 * the existing "retry all" can act on the group. Not labelled with the row's
 * count — the filter re-derives the count on every load, so the number moves.
 *
 * Nothing to link on a row whose `exit_reason` never resolved — that leaves
 * neither a step nor a mappable run state to filter history on.
 */
const ViewButton = ({
  signature,
  projectId,
  workflowId,
  from,
}: {
  signature: FailureSignature;
  projectId: string;
  workflowId: string;
  from: string;
}) => {
  if (!signature.exit_reason) return null;

  return (
    <a
      href={historyUrl(projectId, workflowId, from, signature)}
      className="inline-flex items-center gap-x-1 whitespace-nowrap rounded-full bg-primary-50 px-2.5 py-1 text-xs font-semibold text-primary-700 hover:bg-primary-100"
    >
      View
      <span className="hero-arrow-right-micro h-3 w-3" />
    </a>
  );
};

// A rejected work order never got a run, so the signature filter would fail
// closed on it server-side — history's existing `rejected` status filter is
// what actually matches these. `to_signature/2` gives every rejected row the
// same literal `exit_reason: "rejected"`, so that is the signal to switch.
const historyUrl = (
  projectId: string,
  workflowId: string,
  from: string,
  signature: FailureSignature
) => {
  const params = new URLSearchParams({
    'filters[workflow_id]': workflowId,
    'filters[date_after]': from,
    // SearchParams.from_uri/1 reads the search-field flags out of the query
    // string and put_new's the result, so an absent set means `search_fields:
    // []` rather than the schema default, and every later search term matches
    // nothing. to_uri_params/1 fills these in for every server-built link.
    'filters[id]': 'true',
    'filters[body]': 'true',
    'filters[log]': 'true',
    'filters[dataclip_name]': 'true',
  });

  if (signature.exit_reason === 'rejected') {
    params.set('filters[rejected]', 'true');
  } else {
    params.set('filters[exit_reason]', signature.exit_reason);
    if (signature.error_type) {
      params.set('filters[error_type]', signature.error_type);
    }
    if (signature.job_id) {
      params.set('filters[job_id]', signature.job_id);
    }
  }

  return `/projects/${projectId}/history?${params.toString()}`;
};

// The parts are styled apart rather than concatenated server-side: the error
// type is the bit worth scanning down the column for.
const Signature = ({ signature }: { signature: FailureSignature }) => (
  <p className="font-mono text-gray-900">
    <span className="text-gray-500">{signature.exit_reason}:</span>
    <span className="font-semibold">{errorTypeOf(signature)}</span>
    {signature.step_name && <span> @ {signature.step_name}</span>}
    {signature.adaptor && (
      <span className="text-gray-500">
        {' '}
        [{packageNameOf(signature.adaptor)}]
      </span>
    )}
  </p>
);

// A row is keyed and labelled by `job_id`, not by (job_id, adaptor) — see
// "Why `job_id`" in the plan — so a row spanning an adaptor bump mid-window is
// labelled from its newest failing snapshot. Rendering that snapshot's version
// would head older failures with a version that isn't theirs, so only the
// package name renders. Strips everything from the last '@' that isn't the
// scope's leading one, so a scoped package's own '@' survives.
const packageNameOf = (adaptor: string) => {
  const lastAt = adaptor.lastIndexOf('@');
  return lastAt > 0 ? adaptor.slice(0, lastAt) : adaptor;
};

// A step can finish without reporting a type, and a worker can report one as an
// empty string. The signature still has to say something, and `default` is the
// tip written for exactly that case — hence `||`, which catches '' as well as
// null, where `??` would render a bare `fail:` and a tip with no sentence.
const errorTypeOf = ({ error_type }: FailureSignature) =>
  error_type || 'unknown';

const tipFor = ({ error_type }: FailureSignature) =>
  (error_type && TIPS[error_type]) || TIPS['default'];
