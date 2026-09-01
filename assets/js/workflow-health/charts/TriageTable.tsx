import type { FailureSignature } from '../types';

/**
 * Failed runs grouped by error signature, heaviest first.
 *
 * Purely informational — there is nothing to act on here, so no row is a link
 * or a control. The signature grammar is CON-31:
 * `exitReason:errorType [@ stepName [adaptor@version]]`.
 */

// CON-111. One sentence per error type the worker can report, written to hold
// for every root cause behind that type — the codes are general, so the tip
// has to be too. `default` catches raw JS error names like `TypeError`, which
// reach Lightning through some paths.
const TIPS: Record<string, string> = {
  RuntimeError:
    "Job code hit a value it didn't expect, often a missing input field.",
  JobError: 'The job code intentionally threw this error.',
  AdaptorError: 'An error occurred while an adaptor operation was underway.',
  CompileError: "Job code couldn't be compiled, so no step ever ran.",
  RuntimeCrash:
    "Job code referred to something that doesn't exist; the run was abandoned.",
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
  Cancelled: 'This run was manually stopped before it finished.',
  default: 'The step failed without a recognised error type; check its logs.',
};

interface TriageTableProps {
  signatures: FailureSignature[];
  emptyMessage: string;
}

export const TriageTable = ({ signatures, emptyMessage }: TriageTableProps) => {
  if (signatures.length === 0) {
    return <p className="text-sm text-gray-500">{emptyMessage}</p>;
  }

  return (
    <table className="w-full text-left text-sm">
      <thead>
        <tr className="border-b border-gray-200 text-xs uppercase tracking-wide text-gray-500">
          <th scope="col" className="w-16 py-2 pr-4 font-medium">
            Runs
          </th>
          <th scope="col" className="py-2 font-medium">
            Signature
          </th>
        </tr>
      </thead>
      <tbody>
        {signatures.map(signature => (
          <tr
            key={[
              signature.exit_reason,
              signature.error_type,
              signature.step_name,
              signature.adaptor,
            ].join('|')}
            className="border-b border-gray-100 align-top last:border-0"
          >
            <td className="py-3 pr-4 tabular-nums text-gray-900">
              {signature.count.toLocaleString()}
            </td>
            <td className="py-3">
              <Signature signature={signature} />
              <p className="mt-1">
                <span className="font-medium text-gray-500">Tip: </span>
                <span className="text-gray-600">{tipFor(signature)}</span>
              </p>
            </td>
          </tr>
        ))}
      </tbody>
    </table>
  );
};

// The parts are styled apart rather than concatenated server-side: the error
// type is the bit worth scanning down the column for.
const Signature = ({ signature }: { signature: FailureSignature }) => (
  <p className="font-mono text-gray-900">
    <span className="text-gray-500">{signature.exit_reason}:</span>
    <span className="font-semibold">{errorTypeOf(signature)}</span>
    {signature.step_name && <span> @ {signature.step_name}</span>}
    {signature.adaptor && (
      <span className="text-gray-500"> [{signature.adaptor}]</span>
    )}
  </p>
);

// A step can finish without reporting a type, and a worker can report one as an
// empty string. The signature still has to say something, and `default` is the
// tip written for exactly that case — hence `||`, which catches '' as well as
// null, where `??` would render a bare `fail:` and a tip with no sentence.
const errorTypeOf = ({ error_type }: FailureSignature) =>
  error_type || 'unknown';

const tipFor = ({ error_type }: FailureSignature) =>
  (error_type && TIPS[error_type]) || TIPS['default'];
