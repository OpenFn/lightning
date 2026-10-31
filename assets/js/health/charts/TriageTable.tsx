import { cn } from '#/utils/cn';

import { adaptorLabel } from '../adaptorLabel';
import { historyUrl } from '../historyUrl';
import type { ErrorSignature, FailureState } from '../types';

import { EMPTY } from './Donut';
import { FAILURE_COLORS } from './FailureBreakdownDonut';

/**
 * Failed work orders grouped by error signature, largest group first. Each row
 * links to history filtered to that group, where "retry all" can act on it.
 * A signature reads `exitReason:errorType [@ stepName]`, with the job's adaptor
 * on the line below (see `adaptorLabel`).
 */

// One tip per error type the worker reports. Each type covers many root
// causes, so each tip stays general. `error_type` isn't a closed set, so
// `default` covers anything not listed.
const TIPS: Record<string, string> = {
  RuntimeError:
    "Job code hit a value it didn't expect, often a missing input field.",
  JobError: 'The job code intentionally threw this error.',
  AdaptorError: 'An error occurred while an adaptor operation was underway.',
  CompileError: "Job code couldn't be compiled, so no step ever ran.",
  RuntimeCrash:
    "Job code threw an error the runtime couldn't recover from, so the run was abandoned.",
  // The only raw JS error names that reach Lightning. `assertRuntimeCrash`
  // wraps these two, and the worker reports the wrapper's `subtype` rather than
  // its `name`, so `RuntimeCrash` only means a run-level failure. Every other
  // JS error is reported as `RuntimeError`.
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
  signatures: ErrorSignature[];
  emptyMessage: string;
  projectId: string;
  workflowId: string;
  /** Start of the selected range, from the same response's `window.from`. */
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
    return <p className={EMPTY}>{emptyMessage}</p>;
  }

  return (
    // Cancels the card's `p-6` so the header and row dividers reach the card's
    // edges, as on the LiveView tables.
    <div className="-m-6 overflow-x-auto rounded-lg">
      <table className="min-w-full divide-y divide-gray-200">
        <thead className="bg-gray-50">
          <tr>
            <th scope="col" className={cn(TH, 'w-1/8')}>
              Work orders
            </th>
            <th scope="col" className={TH}>
              Signature
            </th>
            <th scope="col" className={TH}>
              Suggestion
            </th>
            <th scope="col" className={TH}>
              Actions
            </th>
          </tr>
        </thead>
        <tbody className="divide-y divide-gray-200 bg-white">
          {signatures.map(signature => (
            // `job_id` is part of the key because a job deleted and recreated
            // under the same name gives two signatures that otherwise match.
            <tr
              key={[
                signature.exit_reason,
                signature.error_type,
                signature.step_name,
                signature.adaptor,
                signature.job_id,
              ].join('|')}
              className="transition-colors duration-150 hover:bg-gray-50"
            >
              <td className={TD}>
                <span className="inline-block rounded-full bg-slate-200 px-4 py-1.5 text-xs font-medium tabular-nums text-gray-700">
                  {signature.count.toLocaleString()}
                </span>
              </td>
              <td className={TD}>
                <Signature signature={signature} />
              </td>
              <td className={TD}>{tipFor(signature)}</td>
              {/* No link without an `exit_reason`: there's no step or run
                  state to filter history by. */}
              <td className={TD}>
                {signature.exit_reason && (
                  <ViewButton
                    href={signatureUrl(projectId, workflowId, from, signature)}
                  />
                )}
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
};

// Cell classes match the LiveView `table` component (`components/table.ex`).
// The outer padding matches the card's `p-6`, so the columns line up with the
// cards above.
const TH =
  'px-3 py-3.5 first:pl-6 last:pr-6 text-left text-sm font-medium whitespace-nowrap text-gray-800';
const TD = 'px-3 py-4 first:pl-6 last:pr-6 text-sm text-gray-500';

/**
 * Links to history filtered to the work orders in this row. The label leaves
 * out the count because history recounts on every load, so the two can differ.
 */
const ViewButton = ({ href }: { href: string }) => (
  <a
    href={href}
    target="_blank"
    rel="noopener noreferrer"
    className="inline-block whitespace-nowrap rounded-md bg-white px-3 py-2 text-sm font-medium text-gray-900 shadow-xs inset-ring inset-ring-gray-300 hover:inset-ring-gray-400 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary-600"
  >
    View history <span className="sr-only">(opens in a new tab)</span>
  </a>
);

// A rejected work order has no run, so the signature filter can't match it.
// Every rejected row has `exit_reason: "rejected"` (see `to_signature/2`), so
// those rows use history's `rejected` filter instead.
//
// Other rows set no status filter. The signature filter already limits results
// to failed work orders, and a status filter would drop some of them: a `fail:`
// row includes every work order with a failed step, whatever state its run
// ended in.
const signatureUrl = (
  projectId: string,
  workflowId: string,
  from: string,
  signature: ErrorSignature
) => {
  if (signature.exit_reason === 'rejected') {
    return historyUrl(projectId, workflowId, {
      date_after: from,
      rejected: 'true',
    });
  }

  return historyUrl(projectId, workflowId, {
    date_after: from,
    error_signature_exit_reason: signature.exit_reason,
    error_signature_error_type: signature.error_type,
    error_signature_job_id: signature.job_id,
  });
};

// Maps the worker's exit reasons to the donut's failure states. The exit reason
// describes the step that failed, which usually but not always matches how the
// work order ended. Unlisted reasons fall back to the error type.
const OUTCOMES: Partial<Record<string, FailureState>> = {
  fail: 'failed',
  crash: 'crashed',
  kill: 'killed',
  exception: 'exception',
  lost: 'lost',
  rejected: 'rejected',
};

// Shows the state in a word, then the full signature, then the adaptor. The
// state colour goes on the dot and the bar, never the text: some of the colours
// are too pale to read as text on white.
const Signature = ({ signature }: { signature: ErrorSignature }) => {
  const state = OUTCOMES[signature.exit_reason];
  const color = state && FAILURE_COLORS[state];

  return (
    <div className="space-y-1.5">
      <p className="flex items-center gap-2 font-medium text-gray-900 capitalize">
        {color && (
          <span
            aria-hidden="true"
            className="h-2.5 w-2.5 shrink-0 rounded-full"
            style={{ backgroundColor: color }}
          />
        )}
        {state ?? errorTypeOf(signature)}
      </p>
      <p
        className="border-l-2 border-gray-300 pl-2 font-mono text-gray-900"
        style={{ borderColor: color }}
      >
        {signature.exit_reason}:{errorTypeOf(signature)}
        {signature.step_name && ` @ ${signature.step_name}`}
      </p>
      {signature.adaptor && (
        <p className="font-mono text-gray-500">
          {adaptorLabel(signature.adaptor)}
        </p>
      )}
    </div>
  );
};

// A step can fail with no error type or an empty one. `||` catches both null
// and '', so the signature shows `unknown` rather than a bare `fail:`.
const errorTypeOf = ({ error_type }: ErrorSignature) => error_type || 'unknown';

const tipFor = ({ error_type }: ErrorSignature) =>
  (error_type && TIPS[error_type]) || TIPS['default'];
