import { ManualRunPanel } from "../../manual-run-panel/ManualRunPanel"
import type { WithActionProps } from "#/react/lib/with-props"
import { Panel } from "../Panel"
import React from "react"


interface ManualRunBody {
  manual: {
    body: string | null
    dataclip_id: string | null
  }
}

interface WorkflowRunPanel {
  job_id: string
  job_title: string
  cancel_url: string
  back_url: string
  is_edge: boolean
}

export const WorkflowRunPanel: WithActionProps<WorkflowRunPanel> = (props) => {
  const { job_id, job_title, cancel_url, back_url, is_edge, pushEvent, ...actionProps } = props;
  const [manualContent, setManualRunContent] = React.useState<ManualRunBody>({ manual: { body: null, dataclip_id: null } })

  const runDisabled = React.useMemo(() => {
    if (!manualContent.manual.body && !manualContent.manual.dataclip_id) return true;
    else if (manualContent.manual.body) {
      try {
        const parsed = JSON.parse(manualContent.manual.body);
        if (Array.isArray(parsed)) return true;
        return false;
      } catch (e: unknown) {
        return true;
      }
    } else if (manualContent.manual.dataclip_id)
      return false;
    return true;
  }, [manualContent.manual.body, manualContent.manual.dataclip_id])

  const pushEventProxy = React.useCallback((title: string, payload: Record<string, unknown>, cb: unknown) => {
    // here we intercept manual_run_change events and keep the state local
    if (title === "manual_run_change") {
      setManualRunContent(payload as unknown as ManualRunBody);
      return;
    }
    pushEvent(title, payload, cb);
  }, [pushEvent])

  const startRun = React.useCallback(() => {
    const from = job_id ? { from_job: job_id } : { from_start: true };
    pushEvent("manual_run_submit", { ...manualContent, ...from });
  }, [pushEvent, manualContent, job_id])

  return <>
    <Panel
      heading={is_edge ? "Can't run from an edge" : `Run from ${job_title}`}
      onClose={() => { props.navigate(cancel_url); }}
      onBack={() => { props.navigate(back_url) }}
      className="flex flex-col h-150 bg-red"
      footer={
        <div className="flex justify-end">
          <button
            type="button"
            className="rounded-md text-sm font-semibold shadow-xs phx-submit-loading:opacity-75 bg-primary-600 hover:bg-primary-500 text-white disabled:bg-primary-300 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary-600 px-3 py-2"
            disabled={is_edge ? true : runDisabled}
            onClick={startRun}
          >
            Run Workflow Now
          </button>
        </div>
      }
    >
      {
        is_edge ? <div className="flex justify-center flex-col items-center self-center">
          <span className="hero-exclamation-circle w-8 h-8 text-red-300"></span>
          <div>Select a Step or Trigger to start a Run from</div>
        </div> :
          <>
            <div>Select input to start a run</div>
            <ManualRunPanel
              {...actionProps}
              pushEvent={pushEventProxy}
              job_id={job_id}
              fixedHeight
            />
          </>
      }
    </Panel>
  </>
}