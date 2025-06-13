import { ManualRunPanel } from "../../manual-run-panel/ManualRunPanel"
import type { WithActionProps } from "#/react/lib/with-props"
import { Panel } from "../Panel"

interface WorkflowRunPanel {
    job_id: string
    cancel_url: string
}

export const WorkflowRunPanel: WithActionProps<WorkflowRunPanel> = (props) => {
    const { job_id, cancel_url, ...actionProps } = props;
    return <div className="">
        <Panel
            heading="Select Input to start run"
            cancelUrl={cancel_url}
            className="flex flex-col h-145 bg-red"
            {...actionProps}
        >
            <ManualRunPanel {...actionProps} job_id={job_id} selected_dataclip_id={null} />
        </Panel>
    </div>
}