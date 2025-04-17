import type { WithActionProps } from "#/react/lib/with-props";
import React from "react";
import { useWorkflowStore, type ChangeArgs, type PendingAction, type WorkflowProps } from "./store"
import { randomUUID } from "../common";
import { DEFAULT_TEXT } from "../editor/Editor";

const createNewWorkflow = (): Required<ChangeArgs> => {
  const triggers = [
    {
      id: randomUUID(),
      type: 'webhook' as 'webhook',
    },
  ];
  const jobs = [
    {
      id: randomUUID(),
      name: 'New job',
      adaptor: '@openfn/language-common@latest',
      body: DEFAULT_TEXT,
    },
  ];

  const edges = [
    {
      id: randomUUID(),
      source_trigger_id: triggers[0].id,
      target_job_id: jobs[0].id,
      condition_type: 'always',
    },
  ];
  return { triggers, jobs, edges };
};

// This component renders nothing. it just serves as a store sync to the backend
export const WorkflowStore: WithActionProps = (props) => {
  const pendingChanges = React.useRef<PendingAction[]>([]);
  const workflowLoadParamsStart = React.useRef<Date | null>(null)
  const { applyPatches, setState, add, setSelection, subscribe, setDisabled } = useWorkflowStore();

  const pushPendingChange = React.useCallback((pendingChange: PendingAction) => {
    return new Promise((resolve, reject) => {
      console.debug('pushing change', pendingChange);
      // How do we _undo_ the change if it fails?
      props.pushEventTo(
        'push-change',
        pendingChange,
        response => {
          console.debug('push-change response', response);
          // eslint-disable-next-line @typescript-eslint/no-unsafe-argument
          if (response && response.patches) applyPatches(response.patches)
          resolve(true);
        }
      );
    });
  }, [props, applyPatches])

  const processPendingChanges = React.useCallback(async () => {
    while (pendingChanges.current.length > 0) {
      const pendingChange = pendingChanges.current[0];
      pendingChanges.current = pendingChanges.current.slice(1);
      if (pendingChange)
        await pushPendingChange(pendingChange)
    }
  }, [pushPendingChange])

  React.useEffect(() => {
    subscribe((v) => {
      pendingChanges.current = pendingChanges.current.concat(v);
      void processPendingChanges();
    })
  }, [processPendingChanges, subscribe])

  React.useEffect(() => {
    props.handleEvent('patches-applied', (response: { patches: Patch[] }) => {
      console.debug('patches-applied', response.patches);
      // eslint-disable-next-line @typescript-eslint/no-unsafe-argument, @typescript-eslint/no-unnecessary-condition
      if (response.patches) applyPatches(response.patches)
    })
  }, [applyPatches, props])

  React.useEffect(() => {
    props.handleEvent('navigate', (e: any) => {
      const id = new URL(window.location.href).searchParams.get('s');

      // eslint-disable-next-line @typescript-eslint/no-unsafe-member-access
      if (e.patch) setSelection(id);
    })
    props.handleEvent('current-workflow-params', (payload: { workflow_params: WorkflowProps }) => {
      const { workflow_params } = payload;
      setState(workflow_params);
      if (!workflow_params.triggers.length && !workflow_params.jobs.length) {
        const diff = createNewWorkflow();
        add(diff);
      }

      const end = new Date();
      console.debug('current-worflow-params processed', end.toISOString());
      console.timeEnd('workflow-params load');
      props.pushEventTo('workflow_editor_metrics_report', {
        metrics: [
          {
            event: 'workflow-params load',
            start: workflowLoadParamsStart.current?.getTime(),
            end: end.getTime(),
          },
        ],
      })
    })
    workflowLoadParamsStart.current = new Date();
    console.debug('get-initial-state pushed', workflowLoadParamsStart.current.toISOString());
    console.time('workflow-params load');
    props.pushEventTo('get-initial-state', {});
  }, [add, props, setState, setSelection])

  React.useEffect(() => {
    props.handleEvent('set-disabled', (response: { disabled: boolean }) => {
      setDisabled(response.disabled);
    });
  }, [props, setDisabled])

  return <></>
}