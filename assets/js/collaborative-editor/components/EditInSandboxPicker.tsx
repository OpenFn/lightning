// Modal from a live workflow: create a new sandbox or join an active one; both leave for the sandbox editor.

import {
  Dialog,
  DialogBackdrop,
  DialogPanel,
  DialogTitle,
} from '@headlessui/react';
import { format, formatDistanceToNow } from 'date-fns';
import { useCallback, useEffect, useRef, useState } from 'react';

import { cn } from '#/utils/cn';

import { Tooltip } from '../../components/Tooltip';
import type { Dataclip } from '../api/dataclips';
import {
  getDataclipBody,
  getRunDataclip,
  searchDataclips,
} from '../api/dataclips';
import { useOptionalLiveViewActions } from '../contexts/LiveViewActionsContext';
import { useDiscardGuard } from '../hooks/useDiscardGuard';
import { useActiveRun, useHistory } from '../hooks/useHistory';
import {
  useLimits,
  useProject,
  useRequestVersions,
  useVersions,
} from '../hooks/useSessionContext';
import { useWorkflowActions, useWorkflowState } from '../hooks/useWorkflow';
import { useKeyboardShortcut } from '../keyboard';
import {
  formatChannelErrorMessage,
  isChannelRequestError,
} from '../lib/errors';
import { notifications } from '../lib/notifications';
import { suppressUnloadWarning } from '../lib/unloadGuard';
import type { EditInSandboxStart } from '../stores/createWorkflowStore';
import type { Sandbox } from '../types/workflow';

import { Button } from './Button';
import { DiscardChangesDialog } from './DiscardChangesDialog';

type StartChoice = 'nothing' | 'run' | 'saved';
type Step = 'choose' | 'review';

// The run's input, and which run it came from. A body that belongs to another
// run is not this run's body, so it can never be shown or sent as one.
type RunReview =
  | { status: 'idle' }
  | { status: 'loading'; runId: string }
  | { status: 'ready'; runId: string; body: string }
  | { status: 'missing'; runId: string };

interface EditInSandboxPickerProps {
  isOpen: boolean;
  onClose: () => void;
}

// Turn an unknown error into a user-facing description. Channel replies carry
// structured field/base errors we can format; anything else gets a generic
// retry hint. Shared by the list-load and create handlers.
function describeSandboxError(error: unknown): string {
  return isChannelRequestError(error)
    ? formatChannelErrorMessage({
        errors: error.errors as { base?: string[] } & Record<string, string[]>,
        type: error.type,
      })
    : 'Please try again.';
}

// Pull a name-field validation message out of a channel error, if present.
// Duplicate names (and other name validations) come back as a validation_error
// keyed under `name`; those render inline under the input. Everything else
// (system/unexpected errors) returns null and is surfaced as a toast instead.
function extractNameFieldError(error: unknown): string | null {
  if (!isChannelRequestError(error)) return null;
  if (error.type !== 'validation_error') return null;

  const nameErrors = error.errors['name'];
  if (!Array.isArray(nameErrors) || !nameErrors[0]) return null;

  const joined = nameErrors.join(', ');

  // The duplicate-name case gets a friendly, product-specific message. Other
  // name validations (blank, too long, invalid) keep their own server message
  // so a different failure is never mislabelled as a duplicate.
  if (/taken/i.test(joined)) {
    return 'A sandbox with this name exists already.';
  }

  return joined;
}

// A joinable sandbox row: the whole row is the click target (joins the
// sandbox). A colour stripe on the left, then the sandbox name over a single
// muted metadata line ("Created {relative} by {owner}"), and a quiet "Join"
// affordance on the right that fills in and reveals an arrow on hover. The
// creation time shows as a relative label with the exact timestamp on hover.
// The owner can be null (unknown), in which case the "by {owner}" suffix is
// omitted.
function SandboxRow({
  sandbox,
  onJoin,
}: {
  sandbox: Sandbox;
  onJoin: (sandbox: Sandbox) => void;
}) {
  const { owner } = sandbox;
  const ownerName = owner ? owner.name || owner.email || '' : '';

  const date = new Date(sandbox.inserted_at);
  const validDate = !Number.isNaN(date.getTime());
  const relative = validDate
    ? formatDistanceToNow(date, { addSuffix: true })
    : '';
  const exact = validDate ? format(date, 'd MMM yyyy, HH:mm') : '';

  // The whole row is the click target. Inner elements are phrasing spans (not
  // <div>/<p>) so the DOM stays valid inside the <button>; the timestamp's
  // Tooltip trigger is a Radix asChild <span>, which is valid nested here too.
  return (
    <li data-testid="sandbox-row">
      <button
        type="button"
        data-testid="join-sandbox-button"
        aria-label={`Join ${sandbox.name}`}
        onClick={() => {
          onJoin(sandbox);
        }}
        className="group -mx-3 flex w-[calc(100%+1.5rem)] items-center
          justify-between gap-4 rounded-lg px-3 py-3 text-left
          transition-colors hover:bg-gray-50 focus-visible:outline-2
          focus-visible:outline-offset-2 focus-visible:outline-primary-600"
      >
        <span className="flex min-w-0 items-center gap-2.5">
          <span
            aria-hidden="true"
            className="h-8 w-1 shrink-0 rounded-full"
            style={{ backgroundColor: sandbox.color ?? '#e5e7eb' }}
          />
          <span className="block min-w-0">
            <span className="block truncate text-sm font-semibold text-gray-900">
              {sandbox.name}
            </span>
            {/* The date never truncates; only the owner name gives way when
                space is tight. Hovering the date reveals the exact timestamp. */}
            <span className="flex min-w-0 items-center gap-1 text-xs text-gray-500">
              <Tooltip content={exact} side="top">
                <span className="shrink-0 whitespace-nowrap">
                  Created {relative}
                </span>
              </Tooltip>
              {owner && ownerName && (
                <>
                  <span className="shrink-0">by</span>
                  <span className="min-w-0 truncate">{ownerName}</span>
                </>
              )}
            </span>
          </span>
        </span>
        <span
          aria-hidden="true"
          className="flex shrink-0 items-center gap-1 text-sm font-medium
            text-gray-400 transition-colors group-hover:text-gray-900"
        >
          Join
          <span
            className="hero-arrow-right-micro h-4 w-4 -translate-x-1 opacity-0
              transition-all group-hover:translate-x-0 group-hover:opacity-100"
          />
        </span>
      </button>
    </li>
  );
}

// A single "start with" choice: radio, label, and a line saying what it means.
function StartOption({
  value,
  checked,
  onChange,
  label,
  hint,
}: {
  value: StartChoice;
  checked: boolean;
  onChange: (value: StartChoice) => void;
  label: string;
  hint: string;
}) {
  return (
    <label className="flex cursor-pointer items-start gap-2.5">
      <input
        type="radio"
        name="start-with"
        value={value}
        checked={checked}
        onChange={() => {
          onChange(value);
        }}
        className="mt-0.5 h-4 w-4 shrink-0 border-gray-300 text-primary-600
          focus:ring-primary-600"
      />
      <span className="min-w-0">
        <span className="block text-sm text-gray-900">{label}</span>
        <span className="block text-xs text-gray-500">{hint}</span>
      </span>
    </label>
  );
}

function SavedInputList({
  dataclips,
  isLoading,
  canAsk,
  anyFound,
  failed,
  selectedId,
  onSelect,
}: {
  dataclips: Dataclip[];
  isLoading: boolean;
  canAsk: boolean;
  anyFound: boolean;
  failed: boolean;
  selectedId: string | null;
  onSelect: (id: string) => void;
}) {
  if (!canAsk) {
    return (
      <p
        className="mt-3 text-xs text-gray-500"
        data-testid="saved-inputs-unavailable"
      >
        Add a step to this workflow to pick a saved input.
      </p>
    );
  }

  if (failed) {
    return (
      <p
        className="mt-3 text-xs text-gray-500"
        data-testid="saved-inputs-failed"
      >
        Could not load this project's saved inputs.
      </p>
    );
  }

  if (isLoading) {
    return (
      <p
        className="mt-3 text-xs text-gray-500"
        data-testid="saved-inputs-loading"
      >
        Loading saved inputs...
      </p>
    );
  }

  if (dataclips.length === 0) {
    return (
      <p
        className="mt-3 text-xs text-gray-500"
        data-testid="saved-inputs-empty"
      >
        {anyFound
          ? "None of this project's named inputs can be copied into a sandbox. A step result cannot travel."
          : 'This project has no named inputs yet. Name a dataclip to reuse it here.'}
      </p>
    );
  }

  return (
    <ul
      className="mt-3 max-h-48 space-y-1 overflow-y-auto"
      data-testid="saved-inputs"
    >
      {dataclips.map(dataclip => (
        <li key={dataclip.id}>
          <label
            className="flex cursor-pointer items-center gap-2.5 rounded-md
            px-2 py-1.5 hover:bg-gray-50"
          >
            <input
              type="radio"
              name="saved-input"
              checked={selectedId === dataclip.id}
              onChange={() => {
                onSelect(dataclip.id);
              }}
              className="h-4 w-4 shrink-0 border-gray-300 text-primary-600
                focus:ring-primary-600"
            />
            <span className="min-w-0 truncate text-sm text-gray-900">
              {dataclip.name}
            </span>
          </label>
        </li>
      ))}
    </ul>
  );
}

// Three placeholder rows shown while the sandbox list loads.
function SandboxListSkeleton() {
  return (
    <ul className="mt-3 space-y-1" data-testid="sandbox-list-loading">
      {[0, 1, 2].map(index => (
        <li
          key={index}
          className="-mx-3 flex items-center gap-2.5 px-3 py-3"
          aria-hidden="true"
        >
          <div className="h-8 w-1 shrink-0 animate-pulse rounded-full bg-gray-200" />
          <div className="min-w-0 flex-1 space-y-2">
            <div className="h-3 w-1/3 animate-pulse rounded bg-gray-200" />
            <div className="h-2.5 w-1/2 animate-pulse rounded bg-gray-200" />
          </div>
        </li>
      ))}
    </ul>
  );
}

function createButtonLabel({
  isCreating,
  isLoadingBody,
  needsReview,
}: {
  isCreating: boolean;
  isLoadingBody: boolean;
  needsReview: boolean;
}) {
  if (isCreating) return 'Creating...';
  if (isLoadingBody) return 'Loading...';
  return needsReview ? 'Continue' : 'Create sandbox';
}

// A sandbox copy is restricted to these: a step result carries whatever the
// previous step emitted, which is the data we are trying not to move.
const COPYABLE_DATACLIP_TYPES = ['global', 'saved_input', 'http_request'];

function isCopyableDataclip(dataclip: Dataclip): boolean {
  return COPYABLE_DATACLIP_TYPES.includes(dataclip.type);
}

// Shape only, and checked here as well as on the server so the person is told
// before the sandbox is attempted. Size is the server's to judge, since the
// limit is configured there.
function describeBodyProblem(body: string): string | null {
  try {
    const parsed: unknown = JSON.parse(body);

    if (
      parsed === null ||
      typeof parsed !== 'object' ||
      Array.isArray(parsed)
    ) {
      return 'This needs to be a JSON object.';
    }

    return null;
  } catch {
    return "This isn't valid JSON.";
  }
}

// The dataclip id rides along so the sandbox opens with it already selected
// rather than merely holding it somewhere. The run panel has to be asked for,
// or the sandbox opens on a bare canvas and the input we carried is selected
// somewhere nobody can see.
const sandboxPath = (
  projectId: string,
  workflowId: string,
  dataclipId?: string | null
) => {
  const base = `/projects/${projectId}/w/${workflowId}`;

  return dataclipId
    ? `${base}?panel=run&dataclip=${encodeURIComponent(dataclipId)}`
    : base;
};

const hardNavigateToSandbox = (
  projectId: string,
  workflowId: string,
  dataclipId?: string | null
) => {
  // A deliberate departure, already agreed to, so the browser's own warning
  // would only ask the same question a second time.
  suppressUnloadWarning();
  window.location.href = sandboxPath(projectId, workflowId, dataclipId);
};

export function EditInSandboxPicker({
  isOpen,
  onClose,
}: EditInSandboxPickerProps) {
  const { listSandboxes, editInSandbox } = useWorkflowActions();

  // Asks the LiveView to navigate rather than reloading the browser. The socket
  // survives, so there is no white flash and no unload warning to suppress, and
  // because it is a navigation rather than a patch the LiveView remounts and
  // every mount hook runs again. That matters: the project scope and the
  // workflow-ownership check are mount hooks, so a patch would leave the old
  // project's permissions resolved.
  //
  // The picker is mounted whether or not there is a LiveView to ask, so this
  // does not insist on one: without it the old hard navigation still works.
  const liveView = useOptionalLiveViewActions();

  const goToSandbox = useCallback(
    (projectId: string, workflowId: string, dataclipId?: string | null) => {
      if (liveView?.redirect) {
        liveView.redirect(sandboxPath(projectId, workflowId, dataclipId));
      } else {
        hardNavigateToSandbox(projectId, workflowId, dataclipId);
      }
    },
    [liveView]
  );

  const { guard, ...discardPrompt } = useDiscardGuard();

  // Creating a sandbox can be gated by the plan or by nesting depth; joining an
  // existing one never is. So the lock belongs on this button, not on the one
  // that opens this dialog. The wording comes from whichever gate refused.
  const newSandboxLimit = useLimits().new_sandbox ?? {
    allowed: true,
    message: null,
  };
  const createLocked = !newSandboxLimit.allowed;

  // High-priority Escape handler to prevent closing the parent IDE/inspector.
  // Priority 100 (MODAL) ensures this runs before the IDE handler (priority 50);
  // Headless UI's own Escape handling never fires while those intercept it.
  useKeyboardShortcut(
    'Escape',
    () => {
      onClose();
    },
    100,
    { enabled: isOpen }
  );

  const [name, setName] = useState('');
  const [nameError, setNameError] = useState<string | null>(null);
  const [isCreating, setIsCreating] = useState(false);
  const [isLoadingList, setIsLoadingList] = useState(false);
  const [sandboxes, setSandboxes] = useState<Sandbox[]>([]);
  const [startWith, setStartWith] = useState<StartChoice>('nothing');
  const [step, setStep] = useState<Step>('choose');
  const [reviewError, setReviewError] = useState<string | null>(null);
  // One value rather than four booleans and a token. Each state carries the run
  // it belongs to, so a run swap invalidates it by construction and there is
  // nothing to remember to reset. Four rounds of review found bugs in the
  // previous shape, every one of them a flag left out of a reset.
  const [review, setReview] = useState<RunReview>({ status: 'idle' });
  // A reply lands after a render, so what the person now wants has to be read
  // live rather than out of the closure that started the request.
  const startWithRef = useRef<StartChoice>('nothing');
  const canStartFromRunRef = useRef(false);
  const activeRunIdRef = useRef<string | null>(null);
  const reviewRef = useRef<RunReview>({ status: 'idle' });
  const [savedDataclipId, setSavedDataclipId] = useState<string | null>(null);

  const activeRun = useActiveRun();
  const history = useHistory();
  const project = useProject();
  const jobs = useWorkflowState(state => state.jobs);
  const versions = useVersions();
  const requestVersions = useRequestVersions();

  // Any job in the project resolves the same set of named dataclips, so the
  // first one is enough to ask for them.
  const anyJobId = jobs[0]?.id ?? null;
  const [savedDataclips, setSavedDataclips] = useState<Dataclip[]>([]);
  const [isLoadingSaved, setIsLoadingSaved] = useState(false);
  const [savedInputsFiltered, setSavedInputsFiltered] = useState(false);
  const [savedInputsFailed, setSavedInputsFailed] = useState(false);

  // A run's own input is its first step's input. Anything deeper is a step
  // result, which is a different thing to offer.
  const runInputDataclipId = activeRun?.steps?.[0]?.input_dataclip_id ?? null;
  const runStepJobId = activeRun?.steps?.[0]?.job_id ?? null;

  // Gated once, here, so no read can forget to ask. A review belongs to one run
  // and to the run choice: it is not this dialog's state if either has moved on.
  const activeReview =
    review.status !== 'idle' &&
    review.runId === activeRun?.id &&
    startWith === 'run'
      ? review
      : null;

  startWithRef.current = startWith;
  activeRunIdRef.current = activeRun?.id ?? null;
  reviewRef.current = review;

  const reviewBody = activeReview?.status === 'ready' ? activeReview.body : '';
  const isLoadingBody = activeReview?.status === 'loading';
  const hasLoadedBody = activeReview?.status === 'ready';
  const runInputMissing = activeReview?.status === 'missing';

  // Everything the fetch needs. Without all of it the choice could only create
  // an empty sandbox while reporting success.
  const canStartFromRun =
    runInputDataclipId !== null &&
    runStepJobId !== null &&
    activeRun !== null &&
    Boolean(project?.id);
  const runLabel = activeRun ? activeRun.id.slice(0, 6) : null;

  // Read when the dialog opens, so a run arriving later cannot change a choice
  // the person may already have made.
  canStartFromRunRef.current = canStartFromRun;

  useEffect(() => {
    if (!isOpen) return;

    let cancelled = false;
    setIsLoadingList(true);
    setSandboxes([]);
    // Opened with a run in hand, which is what happens when someone is looking
    // at a failure and reaches for a sandbox to fix it. That run's input is
    // what they came to reuse, so it is the choice already made.
    setStartWith(canStartFromRunRef.current ? 'run' : 'nothing');
    setStep('choose');
    setReviewError(null);
    setReview({ status: 'idle' });
    setSavedDataclipId(null);

    const load = async () => {
      try {
        const result = await listSandboxes();
        if (!cancelled) setSandboxes(result);
      } catch (error) {
        if (!cancelled) {
          notifications.alert({
            title: 'Could not load sandboxes',
            description: describeSandboxError(error),
          });
        }
      } finally {
        if (!cancelled) setIsLoadingList(false);
      }
    };

    void load();

    return () => {
      cancelled = true;
    };
  }, [isOpen, listSandboxes]);

  useEffect(() => {
    if (!isOpen || startWith !== 'saved' || !project?.id || !anyJobId) return;

    let cancelled = false;
    setIsLoadingSaved(true);
    setSavedInputsFailed(false);

    void searchDataclips(project.id, anyJobId, '', {
      named_only: true,
      limit: 100,
    })
      .then(({ data }) => {
        // Only what a sandbox can actually copy. Naming is not type-restricted,
        // so a named step result can appear here and would be refused on create.
        if (cancelled) return;

        setSavedDataclips(data.filter(isCopyableDataclip));
        setSavedInputsFiltered(data.length > 0);
      })
      .catch(() => {
        if (!cancelled) {
          setSavedInputsFailed(true);
          notifications.alert({
            title: 'Could not load saved inputs',
            description: 'Please try again.',
          });
        }
      })
      .finally(() => {
        if (!cancelled) setIsLoadingSaved(false);
      });

    return () => {
      cancelled = true;
    };
  }, [isOpen, startWith, project?.id, anyJobId]);

  useEffect(() => {
    if (!isOpen || versions.length > 0) return;

    void requestVersions();
  }, [isOpen, versions.length, requestVersions]);

  // A sandbox always forks the version live now, because promote rebuilds the
  // parent from the sandbox and an older fork would delete the newer work.
  //
  // The run's version comes from the history summaries, the same place the
  // history panel reads it. Opening a run does not load its snapshot, so the
  // document on screen says nothing about which version the run used.
  const runVersionNumber =
    history
      .flatMap(workOrder => workOrder.runs)
      .find(run => run.id === activeRun?.id)?.version_number ?? null;
  const latestVersionNumber =
    versions.find(version => version.is_latest)?.version_number ?? null;
  const startsFromNewerVersion =
    startWith === 'run' &&
    runVersionNumber !== null &&
    latestVersionNumber !== null &&
    runVersionNumber !== latestVersionNumber;

  useEffect(() => {
    if (canStartFromRun || startWith !== 'run') return;

    // The run went away. Leaving the review step behind would strand a redacted
    // body somewhere the person cannot reach or send.
    setStartWith('nothing');
    setStep('choose');
    setReview({ status: 'idle' });
  }, [canStartFromRun, startWith]);

  // A reply may only land if it is still the reply this dialog is waiting for:
  // the same request, the same run, and the same choice. Read from refs because
  // all three can have changed since the request went out.
  const stillLoading = useCallback((runId: string) => {
    const current = reviewRef.current;

    return current.status === 'loading' && current.runId === runId;
  }, []);

  // Landing the result is safe whatever the person has since chosen, because a
  // review is only ever read back through `activeReview`. Moving them to the
  // review screen is not: they may have picked something else while it loaded.
  const shouldShowReview = useCallback(
    (runId: string) =>
      startWithRef.current === 'run' && activeRunIdRef.current === runId,
    []
  );

  useEffect(() => {
    if (step === 'review' && !activeReview) {
      // Whatever the review belonged to has moved on, so the screen showing it
      // cannot be typed into or sent. Go back rather than sit there dead.
      setStep('choose');
    }
  }, [step, activeReview]);

  const handleCreate = useCallback(
    (start: EditInSandboxStart) => {
      setIsCreating(true);
      setNameError(null);
      const trimmed = name.trim();

      const create = async () => {
        try {
          const { project_id, workflow_id, dataclip_id } = await editInSandbox(
            trimmed,
            start
          );
          // Leaving takes the page with it, so uncommitted edits on this
          // workflow would go too.
          guard(() => {
            goToSandbox(project_id, workflow_id, dataclip_id);
          });
        } catch (error) {
          // A rejected name (duplicate, invalid) belongs under the input as an
          // inline field error; only genuinely unexpected/system errors toast.
          const fieldError = extractNameFieldError(error);
          if (fieldError) {
            setNameError(fieldError);
          } else {
            notifications.alert({
              title: 'Could not create a sandbox',
              description: describeSandboxError(error),
            });
          }
          setIsCreating(false);
        }
      };

      void create();
    },
    [name, editInSandbox, guard, goToSandbox]
  );

  // The run's input is checked before it travels, so that choice takes a review
  // step first. The other two create straight away.
  const handleContinue = useCallback(() => {
    if (startWith === 'saved') {
      if (!savedDataclipId) return;
      handleCreate({ dataclipId: savedDataclipId });
      return;
    }

    if (startWith !== 'run') {
      handleCreate({});
      return;
    }

    if (!canStartFromRun || !project?.id || !activeRun || !runStepJobId) {
      return;
    }

    setReviewError(null);

    // Already reviewed this run: keep it, or Back then Continue would restore
    // the production body the person had just redacted.
    if (hasLoadedBody) {
      setStep('review');
      return;
    }

    const runId = activeRun.id;
    setReview({ status: 'loading', runId });

    // Whether the input was kept is the dataclip's own answer. Inferring it from
    // the body does not work: a wiped http_request still serves a JSON object,
    // `{"data": null, "request": null}`, which reads as perfectly good data.
    void getRunDataclip(project.id, runId, runStepJobId)
      .then(async ({ dataclip }) => {
        if (!dataclip || dataclip.wiped_at) {
          if (stillLoading(runId)) setReview({ status: 'missing', runId });
          return;
        }

        const body = await getDataclipBody(dataclip.id);

        if (!stillLoading(runId)) return;

        setReview({ status: 'ready', runId, body });

        if (shouldShowReview(runId)) setStep('review');
      })
      .catch(() => {
        if (!stillLoading(runId)) return;

        setReview({ status: 'idle' });
        notifications.alert({
          title: "Could not load this run's input",
          description: 'Please try again.',
        });
      });
  }, [
    startWith,
    savedDataclipId,
    canStartFromRun,
    handleCreate,
    hasLoadedBody,
    stillLoading,
    shouldShowReview,
    project?.id,
    activeRun,
    runStepJobId,
  ]);

  const handleCreateFromReview = useCallback(() => {
    const problem = describeBodyProblem(reviewBody);

    if (problem) {
      setReviewError(problem);
      return;
    }

    setReviewError(null);
    handleCreate({
      body: reviewBody,
      bodyName: runLabel ? `Input from run ${runLabel}` : 'Reviewed input',
    });
  }, [reviewBody, runLabel, handleCreate]);

  const handleJoin = useCallback(
    (sandbox: Sandbox) => {
      if (!sandbox.workflow_id) return;
      const { id, workflow_id } = sandbox;
      guard(() => {
        goToSandbox(id, workflow_id);
      });
    },
    [guard, goToSandbox]
  );

  // The sandbox already exists by the time we ask, so backing out has to
  // release the create button rather than leave it spinning forever.
  const cancelDiscard = discardPrompt.cancel;
  const handleDiscardCancel = useCallback(() => {
    cancelDiscard();
    setIsCreating(false);
  }, [cancelDiscard]);

  // A name is required to create. The server already returns only joinable
  // sandboxes (each holding a clone of this workflow), so the list is rendered
  // as-is.
  const canCreate =
    name.trim().length > 0 &&
    (startWith !== 'saved' || savedDataclipId !== null) &&
    !(startWith === 'run' && runInputMissing);

  return (
    <>
      <Dialog
        open={isOpen}
        onClose={onClose}
        className="relative z-[60]"
        data-testid="edit-in-sandbox-picker"
      >
        <DialogBackdrop
          transition
          className="modal-backdrop data-closed:opacity-0 data-enter:duration-300
          data-enter:ease-out data-leave:duration-200 data-leave:ease-in"
        />

        <div className="fixed inset-0 z-10 w-screen overflow-y-auto">
          <div
            className="flex min-h-full items-end justify-center p-4 text-center
            sm:items-center sm:p-0"
          >
            <DialogPanel
              transition
              className="relative transform overflow-hidden rounded-lg bg-white
              px-4 pb-4 pt-5 text-left shadow-xl transition-all
              data-closed:translate-y-4 data-closed:opacity-0
              data-enter:duration-300 data-enter:ease-out
              data-leave:duration-200 data-leave:ease-in sm:my-8 sm:w-full
              sm:max-w-lg sm:p-6"
            >
              <button
                type="button"
                onClick={onClose}
                aria-label="Close"
                className="absolute right-4 top-4 sm:right-6 sm:top-6 rounded-md
                p-1 text-gray-400
                transition-colors hover:text-gray-600 focus-visible:outline-2
                focus-visible:outline-offset-2 focus-visible:outline-primary-600"
              >
                <span
                  className="hero-x-mark h-5 w-5"
                  aria-hidden="true"
                  role="img"
                />
              </button>

              {step === 'review' ? (
                <>
                  <DialogTitle
                    as="h3"
                    className="text-base font-semibold text-gray-900"
                  >
                    Check the data before it leaves production
                  </DialogTitle>
                  <p className="mt-1 text-sm text-gray-600">
                    This is a copy of what the run received. Remove anything
                    that shouldn't leave this project. The original is
                    untouched.
                  </p>

                  <label htmlFor="review-body" className="sr-only">
                    Run input
                  </label>
                  <textarea
                    id="review-body"
                    data-testid="review-body"
                    value={reviewBody}
                    onChange={event => {
                      const { value } = event.target;

                      setReview(current =>
                        current.status === 'ready'
                          ? { ...current, body: value }
                          : current
                      );
                      setReviewError(null);
                    }}
                    spellCheck={false}
                    rows={14}
                    className="mt-4 block w-full rounded-md border-0 px-3 py-2
                    font-mono text-xs text-gray-900 shadow-sm ring-1 ring-inset
                    ring-gray-300 focus:ring-2 focus:ring-inset
                    focus:ring-primary-600"
                  />

                  {startsFromNewerVersion && (
                    <p
                      className="mt-3 text-xs text-gray-500"
                      data-testid="review-version-note"
                    >
                      This run used v{runVersionNumber}. The sandbox starts from
                      v{latestVersionNumber}, the version live now.
                    </p>
                  )}

                  <div className="mt-1 min-h-[1rem]">
                    {reviewError && (
                      <p
                        data-testid="review-body-error"
                        className="text-xs text-red-600"
                      >
                        {reviewError}
                      </p>
                    )}
                    {/* A rejected name is decided a step back, so say it here
                      rather than leave the button flicking with nothing on
                      screen changing. */}
                    {nameError && (
                      <p
                        data-testid="review-name-error"
                        className="text-xs text-red-600"
                      >
                        {nameError} Go back to change it.
                      </p>
                    )}
                  </div>

                  <div className="mt-4 flex justify-end gap-3">
                    <button
                      type="button"
                      disabled={isCreating}
                      onClick={() => {
                        setStep('choose');
                      }}
                      className="inline-flex items-center rounded-md bg-white
                      px-3 py-2 text-sm font-semibold text-gray-900 shadow-sm
                      ring-1 ring-inset ring-gray-300 hover:bg-gray-50
                      disabled:cursor-not-allowed disabled:opacity-50"
                    >
                      Back
                    </button>
                    <button
                      type="button"
                      data-testid="create-from-review-button"
                      disabled={isCreating}
                      onClick={handleCreateFromReview}
                      className="inline-flex items-center rounded-md
                      bg-primary-600 px-3 py-2 text-sm font-semibold text-white
                      shadow-sm hover:bg-primary-500
                      disabled:cursor-not-allowed disabled:opacity-50"
                    >
                      {isCreating ? 'Creating...' : 'Create sandbox'}
                    </button>
                  </div>
                </>
              ) : (
                <>
                  <DialogTitle
                    as="h3"
                    className="text-base font-semibold text-gray-900"
                  >
                    Edit in sandbox
                  </DialogTitle>
                  <p className="mt-1 text-sm text-gray-600">
                    A sandbox is a copy of this project. Nothing you do in it
                    touches the live workflow until you promote it back.
                  </p>

                  {/* The title, subtitle and placeholder identify the field, so it
                needs no separate visible label. */}
                  <div className="mt-6">
                    <p
                      className="text-xs font-semibold uppercase tracking-wide
                  text-gray-500"
                    >
                      Create a new sandbox
                    </p>
                    <p className="mt-1 text-xs text-gray-500">
                      Starts from the version live now.
                    </p>
                    <form
                      className="mt-3"
                      onSubmit={event => {
                        event.preventDefault();
                        // Enter can submit even while the button is disabled; honour
                        // the same guards (non-empty name, no create in flight).
                        if (
                          createLocked ||
                          isCreating ||
                          isLoadingBody ||
                          !canCreate
                        )
                          return;
                        handleContinue();
                      }}
                    >
                      <div className="flex gap-2">
                        <div className="min-w-0 flex-1">
                          <label htmlFor="sandbox-name" className="sr-only">
                            Sandbox name
                          </label>
                          <input
                            id="sandbox-name"
                            type="text"
                            value={name}
                            onChange={event => {
                              setName(event.target.value);
                              // Editing the name dismisses a stale field error.
                              setNameError(null);
                            }}
                            placeholder="What are you trying out?"
                            disabled={isCreating}
                            aria-invalid={nameError ? true : undefined}
                            aria-describedby={
                              nameError ? 'sandbox-name-error' : undefined
                            }
                            className={cn(
                              `block w-full rounded-md border-0 px-3 py-2 text-sm
                          shadow-sm ring-1 ring-inset placeholder:text-gray-400
                          focus:ring-2 focus:ring-inset
                          disabled:cursor-not-allowed disabled:opacity-50`,
                              nameError
                                ? 'text-red-900 ring-red-300 focus:ring-red-500'
                                : 'text-gray-900 ring-gray-300 focus:ring-primary-600'
                            )}
                          />
                        </div>
                        <Tooltip
                          content={
                            createLocked ? newSandboxLimit.message : null
                          }
                          side="bottom"
                        >
                          <span className="inline-block shrink-0 self-start">
                            <Button
                              type="submit"
                              data-testid="create-sandbox-button"
                              disabled={
                                createLocked ||
                                isCreating ||
                                isLoadingBody ||
                                !canCreate
                              }
                              className="inline-flex items-center gap-1.5"
                            >
                              {createLocked && (
                                <span
                                  className="hero-lock-closed size-4"
                                  data-testid="create-sandbox-lock"
                                  aria-hidden="true"
                                />
                              )}
                              {createButtonLabel({
                                isCreating,
                                isLoadingBody,
                                needsReview: startWith === 'run',
                              })}
                            </Button>
                          </span>
                        </Tooltip>
                      </div>
                      {/* Always-rendered slot sized for one line of error text, so
                    showing/hiding the message never shifts the OR divider or
                    Join section below it. The message itself stays conditional
                    so the field only exposes an error when there is one. */}
                      <div className="mt-1 min-h-[1rem]">
                        {nameError && (
                          <p
                            id="sandbox-name-error"
                            data-testid="sandbox-name-error"
                            className="text-xs text-red-600"
                          >
                            {nameError}
                          </p>
                        )}
                      </div>

                      <fieldset className="mt-4" data-testid="start-with">
                        <legend
                          className="text-xs font-semibold uppercase tracking-wide
                      text-gray-500"
                        >
                          Start with
                        </legend>

                        <div className="mt-2 space-y-2">
                          <StartOption
                            value="nothing"
                            checked={startWith === 'nothing'}
                            onChange={setStartWith}
                            label="Nothing"
                            hint="An empty sandbox. Pick input when you run."
                          />

                          {canStartFromRun && (
                            <StartOption
                              value="run"
                              checked={startWith === 'run'}
                              onChange={setStartWith}
                              label="This run's input"
                              hint="A copy of the data this run received. You check it first."
                            />
                          )}

                          <StartOption
                            value="saved"
                            checked={startWith === 'saved'}
                            onChange={setStartWith}
                            label="A saved input"
                            hint="One of this project's named inputs."
                          />
                        </div>

                        {startWith === 'run' && runInputMissing && (
                          <p
                            className="mt-3 text-xs text-gray-500"
                            data-testid="run-input-missing"
                          >
                            This run's input was not kept, so there is nothing
                            to copy. Projects that never retain input and output
                            data have none to start from.
                          </p>
                        )}

                        {startsFromNewerVersion && (
                          <p
                            className="mt-3 text-xs text-gray-500"
                            data-testid="version-note"
                          >
                            This run used v{runVersionNumber}. The sandbox
                            starts from v{latestVersionNumber}, the version live
                            now, because promoting an older one would remove the
                            newer work.
                          </p>
                        )}

                        {startWith === 'saved' && (
                          <SavedInputList
                            dataclips={savedDataclips}
                            isLoading={isLoadingSaved}
                            canAsk={anyJobId !== null}
                            anyFound={savedInputsFiltered}
                            failed={savedInputsFailed}
                            selectedId={savedDataclipId}
                            onSelect={setSavedDataclipId}
                          />
                        )}
                      </fieldset>
                    </form>
                  </div>

                  {/* Join an existing sandbox. The server returns only sandboxes that
                hold a clone of this workflow; hidden entirely when there are
                none. */}
                  {(isLoadingList || sandboxes.length > 0) && (
                    <div className="mt-6">
                      <p
                        className="text-xs font-semibold uppercase tracking-wide
                    text-gray-500"
                      >
                        Join an active sandbox
                      </p>
                      <p className="mt-1 text-xs text-gray-500">
                        Pick up where someone left off, in a sandbox already
                        open for this workflow.
                      </p>

                      {isLoadingList ? (
                        <SandboxListSkeleton />
                      ) : (
                        // Cap the list at roughly 5-6 rows so a user with many
                        // sandboxes scrolls the list rather than the whole modal. The
                        // scroll container carries the row's -mx-3 bleed itself
                        // (-mx-3 px-3), so the rows fit exactly inside it: no
                        // horizontal scrollbar, the hover bleed is kept, and the px-3
                        // keeps the vertical scrollbar clear of the "Join" text.
                        <ul
                          className="mt-3 -mx-3 max-h-80 space-y-1 overflow-y-auto
                      overflow-x-hidden px-3"
                          data-testid="sandbox-list"
                        >
                          {sandboxes.map(sandbox => (
                            <SandboxRow
                              key={sandbox.id}
                              sandbox={sandbox}
                              onJoin={handleJoin}
                            />
                          ))}
                        </ul>
                      )}
                    </div>
                  )}
                </>
              )}
            </DialogPanel>
          </div>
        </div>
      </Dialog>
      <DiscardChangesDialog
        isOpen={discardPrompt.isAsking}
        onSaveAndContinue={discardPrompt.saveAndRunPending}
        onDiscardAndContinue={discardPrompt.runPending}
        onCancel={handleDiscardCancel}
        description="Opening the sandbox leaves this page, and your unsaved changes cannot come with it. Switch without saving and they are gone."
      />
    </>
  );
}
