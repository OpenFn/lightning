import { ManualRunPanel } from "../../manual-run-panel/ManualRunPanel"
import type { WithActionProps } from "#/react/lib/with-props"
import { Panel } from "../Panel"
import React from "react"


interface ManualRunBody {
  body: string | null
  dataclip_id: string | null
}

interface WorkflowRunPanel {
  job_id: string
  cancel_url: string
}

export const WorkflowRunPanel: WithActionProps<WorkflowRunPanel> = (props) => {
  const { job_id, cancel_url, pushEvent, ...actionProps } = props;
  const [manualRunContent, setManualRunContent] = React.useState<ManualRunBody>({ body: null, dataclip_id: null })

  // when is it disabled?
  // no content for both?

  const pushEventProxy = React.useCallback((title: string, payload: Record<string, unknown>, cb: unknown) => {
    // here we intercept manual_run_change events and keep the state local
    if (title === "manual_run_change") {
      setManualRunContent(payload as unknown as ManualRunBody);
      return;
    }
    pushEvent(title, payload, cb);
  }, [pushEvent])
  return <div className="">
    <Panel
      heading="Select Input to start run"
      cancelUrl={cancel_url}
      className="flex flex-col h-145 bg-red"
      {...actionProps}
      pushEvent={props.pushEvent}
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