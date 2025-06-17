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
  cancel_url: string
}

export const WorkflowRunPanel: WithActionProps<WorkflowRunPanel> = (props) => {
  const { job_id, cancel_url, pushEvent, ...actionProps } = props;
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
    pushEvent("manual_run_submit", {...manualContent, from_start: true});
  }, [pushEvent, manualContent])

  return <div className="">
    <Panel
      heading="Select Input to start run"
      cancelUrl={cancel_url}
      className="flex flex-col h-145 bg-red"
      {...actionProps}
      pushEvent={props.pushEvent}
      footer={
        <div className="flex justify-end">
          <button
            type="button"
            className="rounded-md text-sm font-semibold shadow-xs phx-submit-loading:opacity-75 bg-primary-600 hover:bg-primary-500 text-white disabled:bg-primary-300 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary-600 px-3 py-2"
            disabled={runDisabled}
            onClick={startRun}
          >
            Run Workflow Now
          </button>
        </div>
      }
    >
      <ManualRunPanel
        {...actionProps}
        pushEvent={pushEventProxy}
        pushEventTo={(title, payload) => { console.log("ev:to", title, payload) }}
        job_id={job_id}
        selected_dataclip_id={null}
      />
    </Panel>
  </div>
}