import React from 'react';

import type { WithActionProps } from '#/react/lib/with-props';

import useQuery from '../../hooks/useQuery';
import { ManualRunPanel } from '../../manual-run-panel/ManualRunPanel';
import type { Dataclip } from '../../manual-run-panel/types';
import type { RunStep } from '../../workflow-store/store';
import { Panel } from '../Panel';

interface ManualRunBody {
  manual: {
    body: string | null;
    dataclip_id: string | null;
  };
}

interface WorkflowRunPanel {
  job_id: string;
  job_title: string;
  cancel_url: string;
  back_url: string;
  is_edge: boolean;
}

export const WorkflowRunPanel: WithActionProps<WorkflowRunPanel> = props => {
  const {
    job_id,
    job_title,
    cancel_url,
    back_url,
    is_edge,
    pushEvent,
    ...actionProps
  } = props;
  const { a: runId } = useQuery(['a']);
  const [manualContent, setManualRunContent] = React.useState<ManualRunBody>({
    manual: { body: null, dataclip_id: null },
  });
  const [currentRunStep, setCurrentRunStep] = React.useState<RunStep | null>(
    null
  );
  const [currentDataclip, setCurrentDataclip] = React.useState<Dataclip | null>(
    null
  );

  const runDisabled = React.useMemo(() => {
    if (currentDataclip && currentDataclip.wiped_at) {
      return true;
    } else if (!manualContent.manual.body && !manualContent.manual.dataclip_id)
      return true;
    else if (manualContent.manual.body) {
      try {
        const parsed = JSON.parse(manualContent.manual.body);
        if (Array.isArray(parsed)) return true;
        return false;
      } catch (e: unknown) {
        return true;
      }
    } else if (manualContent.manual.dataclip_id) return false;
    return true;
  }, [
    manualContent.manual.body,
    manualContent.manual.dataclip_id,
    currentDataclip,
  ]);

  const pushEventProxy = React.useCallback(
    (title: string, payload: Record<string, unknown>, cb: unknown) => {
      // here we intercept manual_run_change events and keep the state local
      if (title === 'manual_run_change') {
        console.log('manual_run_change event received', payload);
        setManualRunContent(payload as unknown as ManualRunBody);
        return;
      }
      pushEvent(title, payload, cb);
    },
    [pushEvent]
  );

  const handleRunStepChange = React.useCallback((runStep: RunStep | null) => {
    setCurrentRunStep(runStep);
  }, []);

  const handleDataclipChange = React.useCallback(
    (dataclip: Dataclip | null) => {
      setCurrentDataclip(dataclip);
    },
    []
  );

  const startRetry = React.useCallback(() => {
    if (runId && currentRunStep) {
      pushEvent('rerun', {
        run_id: runId,
        step_id: currentRunStep.id,
        via: 'job_panel',
      });
    }
  }, [pushEvent, runId, currentRunStep]);

  const startRun = React.useCallback(() => {
    const from = job_id ? { from_job: job_id } : { from_start: true };
    pushEvent('manual_run_submit', { ...manualContent, ...from });
  }, [pushEvent, manualContent, job_id]);

  const shouldShowRetry = React.useMemo(() => {
    if (is_edge || !currentRunStep || !currentDataclip || !runId) return false;
    return (
      currentDataclip.wiped_at === null &&
      currentRunStep.input_dataclip_id === currentDataclip.id
    );
  }, [currentRunStep, runId, currentDataclip, is_edge]);

  return (
    <>
      <Panel
        heading={is_edge ? 'Run' : `Run from ${job_title}`}
        onClose={() => {
          props.navigate(cancel_url);
        }}
        onBack={() => {
          props.navigate(back_url);
        }}
        className="flex flex-col bg-red"
        footer={
          <div className="flex justify-end">
            {shouldShowRetry ? (
              <div className="inline-flex rounded-md shadow-xs">
                <button
                  type="button"
                  className="rounded-md text-sm font-semibold shadow-xs phx-submit-loading:opacity-75 cursor-pointer disabled:cursor-auto px-3 py-2 bg-primary-600 hover:bg-primary-500 text-white focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary-600 relative inline-flex items-center rounded-r-none"
                  onClick={startRetry}
                >
                  <span className="hero-play-mini w-4 h-4 mr-1"></span> Run
                  (retry)
                </button>
                <div className="relative -ml-px block">
                  <button
                    type="button"
                    className="rounded-md text-sm font-semibold shadow-xs phx-submit-loading:opacity-75 cursor-pointer disabled:cursor-auto px-3 py-2 bg-primary-600 hover:bg-primary-500 text-white focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary-600 h-full rounded-l-none pr-1 pl-1"
                    onClick={() => {
                      const dropdown = document.getElementById(
                        'new-work-order-option'
                      );
                      if (dropdown) {
                        dropdown.style.display =
                          dropdown.style.display === 'none' ? 'block' : 'none';
                      }
                    }}
                    aria-expanded="false"
                    aria-haspopup="true"
                  >
                    <span className="sr-only">Open options</span>
                    <span className="hero-chevron-down w-4 h-4"></span>
                  </button>
                  <div role="menu" aria-orientation="vertical">
                    <button
                      id="new-work-order-option"
                      type="button"
                      className="rounded-md text-sm font-semibold shadow-xs phx-submit-loading:opacity-75 cursor-pointer disabled:cursor-auto px-3 py-2 bg-white hover:bg-gray-50 text-gray-900 ring-1 ring-gray-300 ring-inset hidden absolute right-0 bottom-9 z-10 mb-2 w-max"
                      style={{ display: 'none' }}
                      disabled={is_edge ? true : runDisabled}
                      onClick={startRun}
                    >
                      <span className="hero-play-solid w-4 h-4 mr-1"></span> Run
                      (New Work Order)
                    </button>
                  </div>
                </div>
              </div>
            ) : (
              <button
                type="button"
                className="rounded-md text-sm font-semibold shadow-xs phx-submit-loading:opacity-75 bg-primary-600 hover:bg-primary-500 text-white disabled:bg-primary-300 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary-600 px-3 py-2 flex items-center gap-1"
                disabled={is_edge ? true : runDisabled}
                onClick={startRun}
              >
                <span className="hero-play-solid w-4 h-4"></span> Run Workflow
                Now
              </button>
            )}
          </div>
        }
      >
        {is_edge ? (
          <div className="flex justify-center flex-col items-center self-center">
            <div>Select a Step or Trigger to start a Run from</div>
          </div>
        ) : (
          <>
            <div className="truncate">Select input to start a run</div>
            <ManualRunPanel
              {...actionProps}
              pushEvent={pushEventProxy}
              job_id={job_id}
              fixedHeight
              onRunStepChange={handleRunStepChange}
              onDataclipChange={handleDataclipChange}
            />
          </>
        )}
      </Panel>
    </>
  );
};
