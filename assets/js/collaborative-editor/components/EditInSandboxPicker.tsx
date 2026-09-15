/**
 * Creating or joining a sandbox from the editor, and choosing what data the
 * clone starts from.
 */

import {
  Dialog,
  DialogBackdrop,
  DialogPanel,
  DialogTitle,
} from '@headlessui/react';
import { format, formatDistanceToNow } from 'date-fns';
import { useCallback, useEffect, useRef, useState } from 'react';

import { MonacoEditor } from '#/monaco';
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
  useRequestReleases,
  useReleases,
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

function formatBody(body: string): string {
  try {
    return JSON.stringify(JSON.parse(body), null, 2);
  } catch {
    return body;
  }
}

type StartChoice = 'nothing' | 'run' | 'saved';
type Step = 'choose' | 'review';

type RunReview =
  | { status: 'idle' }
  | { status: 'loading'; runId: string }
  | { status: 'ready'; runId: string; body: string }
  | { status: 'missing'; runId: string };

interface EditInSandboxPickerProps {
  isOpen: boolean;
  onClose: () => void;
}

function describeSandboxError(error: unknown): string {
  return isChannelRequestError(error)
    ? formatChannelErrorMessage({
        errors: error.errors as { base?: string[] } & Record<string, string[]>,
        type: error.type,
      })
    : 'Please try again.';
}

function extractNameFieldError(error: unknown): string | null {
  if (!isChannelRequestError(error)) return null;
  if (error.type !== 'validation_error') return null;

  const nameErrors = error.errors['name'];
  if (!Array.isArray(nameErrors) || !nameErrors[0]) return null;

  const joined = nameErrors.join(', ');

  if (/taken/i.test(joined)) {
    return 'A sandbox with this name exists already.';
  }

  return joined;
}

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

const COPYABLE_DATACLIP_TYPES = ['global', 'saved_input', 'http_request'];

function isCopyableDataclip(dataclip: Dataclip): boolean {
  return COPYABLE_DATACLIP_TYPES.includes(dataclip.type);
}

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
  suppressUnloadWarning();
  window.location.href = sandboxPath(projectId, workflowId, dataclipId);
};

export function EditInSandboxPicker({
  isOpen,
  onClose,
}: EditInSandboxPickerProps) {
  const { listSandboxes, editInSandbox } = useWorkflowActions();

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

  const newSandboxLimit = useLimits().new_sandbox ?? {
    allowed: true,
    message: null,
  };
  const createLocked = !newSandboxLimit.allowed;

  const [name, setName] = useState('');
  const [nameError, setNameError] = useState<string | null>(null);
  const [isCreating, setIsCreating] = useState(false);

  const handleDismiss = () => {
    if (isCreating) return;
    onClose();
  };

  useKeyboardShortcut(
    'Escape',
    () => {
      handleDismiss();
    },
    100,
    { enabled: isOpen }
  );

  const [isLoadingList, setIsLoadingList] = useState(false);
  const [sandboxes, setSandboxes] = useState<Sandbox[]>([]);
  const [startWith, setStartWith] = useState<StartChoice>('nothing');
  const [step, setStep] = useState<Step>('choose');
  const [reviewError, setReviewError] = useState<string | null>(null);
  const [review, setReview] = useState<RunReview>({ status: 'idle' });
  const startWithRef = useRef<StartChoice>('nothing');
  const canStartFromRunRef = useRef(false);
  const activeRunIdRef = useRef<string | null>(null);
  const reviewRef = useRef<RunReview>({ status: 'idle' });
  const [savedDataclipId, setSavedDataclipId] = useState<string | null>(null);

  const activeRun = useActiveRun();
  const history = useHistory();
  const project = useProject();
  const jobs = useWorkflowState(state => state.jobs);
  const releases = useReleases();
  const requestReleases = useRequestReleases();

  const anyJobId = jobs[0]?.id ?? null;
  const [savedDataclips, setSavedDataclips] = useState<Dataclip[]>([]);
  const [isLoadingSaved, setIsLoadingSaved] = useState(false);
  const [savedInputsFiltered, setSavedInputsFiltered] = useState(false);
  const [savedInputsFailed, setSavedInputsFailed] = useState(false);

  const runInputDataclipId = activeRun?.steps?.[0]?.input_dataclip_id ?? null;
  const runStepJobId = activeRun?.steps?.[0]?.job_id ?? null;

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

  const canStartFromRun =
    runInputDataclipId !== null &&
    runStepJobId !== null &&
    activeRun !== null &&
    Boolean(project?.id);
  const runLabel = activeRun ? activeRun.id.slice(0, 6) : null;

  canStartFromRunRef.current = canStartFromRun;

  useEffect(() => {
    if (!isOpen) return;

    let cancelled = false;
    setIsLoadingList(true);
    setSandboxes([]);
    setStartWith(canStartFromRunRef.current ? 'run' : 'nothing');
    setStep('choose');
    setIsCreating(false);
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
    if (!isOpen || releases.length > 0) return;

    void requestReleases();
  }, [isOpen, releases.length, requestReleases]);

  const runVersionNumber =
    history
      .flatMap(workOrder => workOrder.runs)
      .find(run => run.id === activeRun?.id)?.version_number ?? null;
  const latestVersionNumber =
    releases.find(version => version.is_latest)?.version_number ?? null;
  const startsFromNewerVersion =
    startWith === 'run' &&
    runVersionNumber !== null &&
    latestVersionNumber !== null &&
    runVersionNumber !== latestVersionNumber;

  useEffect(() => {
    if (canStartFromRun || startWith !== 'run') return;

    setStartWith('nothing');
    setStep('choose');
    setReview({ status: 'idle' });
  }, [canStartFromRun, startWith]);

  const stillLoading = useCallback((runId: string) => {
    const current = reviewRef.current;

    return current.status === 'loading' && current.runId === runId;
  }, []);

  const shouldShowReview = useCallback(
    (runId: string) =>
      startWithRef.current === 'run' && activeRunIdRef.current === runId,
    []
  );

  useEffect(() => {
    if (step === 'review' && !activeReview) {
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
          guard(() => {
            goToSandbox(project_id, workflow_id, dataclip_id);
          });
        } catch (error) {
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

    if (hasLoadedBody) {
      setStep('review');
      return;
    }

    const runId = activeRun.id;
    setReview({ status: 'loading', runId });

    void getRunDataclip(project.id, runId, runStepJobId)
      .then(async ({ dataclip }) => {
        if (!dataclip || dataclip.wiped_at) {
          if (stillLoading(runId)) setReview({ status: 'missing', runId });
          return;
        }

        const body = await getDataclipBody(dataclip.id);

        if (!stillLoading(runId)) return;

        setReview({ status: 'ready', runId, body: formatBody(body) });

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

  const cancelDiscard = discardPrompt.cancel;
  const handleDiscardCancel = useCallback(() => {
    cancelDiscard();
    setIsCreating(false);
  }, [cancelDiscard]);

  const canCreate =
    name.trim().length > 0 &&
    (startWith !== 'saved' || savedDataclipId !== null) &&
    !(startWith === 'run' && runInputMissing);

  return (
    <>
      <Dialog
        open={isOpen}
        onClose={handleDismiss}
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
              className={cn(
                `relative transform overflow-hidden rounded-lg bg-white
                px-4 pb-4 pt-5 text-left shadow-xl transition-all
                data-closed:translate-y-4 data-closed:opacity-0
                data-enter:duration-300 data-enter:ease-out
                data-leave:duration-200 data-leave:ease-in sm:my-8 sm:w-full
                sm:p-6`,
                step === 'review' ? 'sm:max-w-4xl' : 'sm:max-w-lg'
              )}
            >
              <button
                type="button"
                onClick={handleDismiss}
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

                  {/* The same editor the run viewer shows a dataclip in, made
                      editable. This is the one screen where the data matters
                      most, and it was the one screen that dropped to a plain
                      box with no highlighting, no folding and no line numbers. */}
                  <div
                    data-testid="review-editor"
                    className="mt-4 h-[60vh] min-h-80 overflow-hidden rounded-md ring-1
                    ring-inset ring-gray-300 focus-within:ring-2
                    focus-within:ring-primary-600"
                  >
                    <MonacoEditor
                      defaultLanguage="json"
                      theme="default"
                      value={reviewBody}
                      loading={<div className="p-3 text-xs">Loading...</div>}
                      onChange={(value: string | undefined) => {
                        const next = value ?? '';

                        setReview(current =>
                          current.status === 'ready'
                            ? { ...current, body: next }
                            : current
                        );
                        setReviewError(null);
                      }}
                      options={{
                        readOnly: false,
                        lineNumbersMinChars: 3,
                        tabSize: 2,
                        scrollBeyondLastLine: false,
                        overviewRulerLanes: 0,
                        overviewRulerBorder: false,
                        fontFamily: 'Fira Code VF',
                        fontSize: 13,
                        fontLigatures: true,
                        fixedOverflowWidgets: true,
                        minimap: { enabled: false },
                        wordWrap: 'on',
                      }}
                    />
                  </div>

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

                  {/* Continue in a sandbox someone already has open. The server returns only sandboxes that
                hold a clone of this workflow; hidden entirely when there are
                none. */}
                  {(isLoadingList || sandboxes.length > 0) && (
                    <div className="mt-6">
                      <p
                        className="text-xs font-semibold uppercase tracking-wide
                    text-gray-500"
                      >
                        Continue in a sandbox
                      </p>
                      <p className="mt-1 text-xs text-gray-500">
                        Pick up where someone left off, in a sandbox already
                        open for this workflow.
                      </p>

                      {isLoadingList ? (
                        <SandboxListSkeleton />
                      ) : (
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
