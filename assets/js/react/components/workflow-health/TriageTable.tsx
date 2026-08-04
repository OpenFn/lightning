import { ProvisionalBadge } from './Panel';
import { blameStyles, formatCount } from './theme';
import type { Blame, TriageSignature } from './types';

/**
 * Plain-English gloss on each kind of failure, so the signature is not the
 * only thing a reader has to go on.
 */
const explanations: Record<string, string> = {
  // Raised by job code.
  RuntimeError: 'Job code hit a bad value while running.',
  ReferenceError: 'Job code referred to something that does not exist.',
  CompileError: 'Job code failed to compile, so no step ever ran.',
  ImportError: 'An import in the job could not be resolved.',
  JobError: 'The job threw an error deliberately.',

  // Raised by an adaptor against the system it talks to.
  AdaptorError: 'A connector library failed against the remote system.',

  // Ceilings the platform enforces.
  OOMError: 'The run exceeded its memory allowance.',
  TimeoutError: 'The run passed its deadline without finishing.',
  StateTooLargeError: 'The run’s state grew past the size limit.',
  SecurityError: 'The run attempted something the sandbox forbids.',

  // Written by Lightning when it loses track of a run.
  LostAfterStart: 'The run started but never reported back.',
  LostAfterClaim: 'A worker claimed the run but never started it.',
  UnknownReason: 'The run ended without reporting why.',
};

const blameNote: Record<Blame, string> = {
  user: 'in this workflow’s own code',
  remote: 'in an adaptor or the system it talks to',
  limit: 'against a resource limit',
  platform: 'inside Lightning itself',
};

export const TriageTable = ({ rows }: { rows: TriageSignature[] }) => {
  if (rows.length === 0) {
    return (
      <p className="rounded-lg border border-gray-200 bg-white px-5 py-8 text-center text-sm text-gray-400">
        No failures in this window.
      </p>
    );
  }

  return (
    <div className="divide-y divide-gray-200 overflow-hidden rounded-lg border border-gray-200 bg-white">
      <div className="flex items-center gap-4 bg-gray-50 px-5 py-2 text-[10px] font-semibold uppercase tracking-wide text-gray-500">
        <span className="w-14 shrink-0 text-center">Runs</span>
        <span className="flex-1">Signature</span>
        <span className="w-40 shrink-0 text-right">Actions</span>
      </div>

      {rows.map(row => (
        <TriageRow key={signatureKey(row)} row={row} />
      ))}
    </div>
  );
};

const TriageRow = ({ row }: { row: TriageSignature }) => (
  <div className="flex items-start gap-4 px-5 py-4">
    <span className="w-14 shrink-0 text-center">
      <span className="inline-block rounded-full border border-gray-200 px-2 py-0.5 text-xs font-medium tabular-nums text-gray-700">
        {formatCount(row.runs)}
      </span>
    </span>

    <div className="min-w-0 flex-1">
      <p className="font-mono text-xs leading-relaxed">
        <span className={blameStyles[row.blame] ?? 'text-gray-600'}>
          {row.blame}
        </span>
        <span className="text-gray-400">:</span>
        <span className="text-gray-700">{row.exit_reason}</span>
        {row.error_type ? (
          <>
            <span className="text-gray-400">:</span>
            <span className="text-gray-900">{row.error_type}</span>
          </>
        ) : null}
        {row.job ? (
          <>
            <span className="text-gray-400"> @ </span>
            <span className="text-gray-900">{row.job}</span>
          </>
        ) : (
          <span className="text-gray-400"> — no step ran</span>
        )}
        {row.adaptor ? (
          <span className="text-gray-400"> [{row.adaptor}]</span>
        ) : null}
      </p>

      <p className="mt-1 text-xs text-gray-600">
        {explanations[row.error_type ?? ''] ?? 'The run did not complete.'}{' '}
        <span className="text-gray-400">Likely {blameNote[row.blame]}.</span>
      </p>

      {/*
        The error message is the missing half of a real signature. The worker
        sends one, but there is no column on a step to keep it, so these rows
        group by error type — lumping together every distinct bug that happens
        to raise the same class.
      */}
      <p className="mt-1.5 flex items-center gap-1.5 text-xs italic text-gray-400">
        <ProvisionalBadge />
        Grouped by error type, not the specific failure — the error message is
        only kept in the run logs.
      </p>
    </div>

    <div className="flex w-40 shrink-0 justify-end">
      <button
        type="button"
        disabled
        title="Not wired up in this mockup"
        className="cursor-not-allowed rounded-md border border-gray-200 px-2.5 py-1.5 text-xs font-medium text-gray-400"
      >
        {row.blame === 'user' ? 'Fix in sandbox' : `Re-run ${row.runs}`}
      </button>
    </div>
  </div>
);

const signatureKey = (row: TriageSignature) =>
  [row.blame, row.exit_reason, row.error_type, row.job].join(':');
