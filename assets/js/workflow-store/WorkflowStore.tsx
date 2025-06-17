import type { WithActionProps } from '#/react/lib/with-props';
import React from 'react';
import { randomUUID } from '../common';
import { DEFAULT_TEXT } from '../editor/Editor';
import {
  useWorkflowStore,
  type ChangeArgs,
  type PendingAction,
  type WorkflowProps
} from './store';

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
export const WorkflowStore: WithActionProps = props => {
  const { pushEventTo, handleEvent, children } = props;
  const pendingChanges = React.useRef<PendingAction[]>([]);
  const {
    applyPatches,
    setState,
    add,
    setSelection,
    subscribe,
    setDisabled,
    setForceFit,
    reset
  } = useWorkflowStore();

  const pushPendingChange = React.useCallback(
    (pendingChange: PendingAction) => {
      return new Promise((resolve, reject) => {
        console.debug('pushing change', pendingChange);
        // How do we _undo_ the change if it fails?
        pushEventTo('push-change', pendingChange, response => {
          console.debug('push-change response', response);
          // eslint-disable-next-line @typescript-eslint/no-unsafe-argument
          if (response && response.patches) applyPatches(response.patches);
          resolve(true);
        });
      });
    },
    [pushEventTo, applyPatches]
  );

  const processPendingChanges = React.useCallback(async () => {
    while (pendingChanges.current.length > 0) {
      const pendingChange = pendingChanges.current[0];
      pendingChanges.current = pendingChanges.current.slice(1);
      if (pendingChange) await pushPendingChange(pendingChange);
    }
  }, [pushPendingChange]);

  React.useEffect(() => {
    subscribe(v => {
      pendingChanges.current = pendingChanges.current.concat(v);
      void processPendingChanges();
    });
  }, [processPendingChanges, subscribe]);

  React.useEffect(() => {
    handleEvent('patches-applied', (response: { patches: Patch[] }) => {
      console.debug('patches-applied', response.patches);
      // eslint-disable-next-line @typescript-eslint/no-unsafe-argument, @typescript-eslint/no-unnecessary-condition
      if (response.patches) applyPatches(response.patches);
    });
  }, [applyPatches, handleEvent]);

  React.useEffect(() => {
    handleEvent('state-applied', (response: { state: WorkflowProps }) => {
      console.log('state-applied', response.state);
      // eslint-disable-next-line @typescript-eslint/no-unsafe-argument, @typescript-eslint/no-unnecessary-condition
      if (response.state) setState(response.state);
    });
  }, [setState, handleEvent]);

  React.useEffect(() => {
    handleEvent('navigate', (e: any) => {
      const id = new URL(window.location.href).searchParams.get('s');

      // eslint-disable-next-line @typescript-eslint/no-unsafe-member-access
      if (e.patch) setSelection(id);
    });
    // force fitting
    handleEvent('force-fit', () => {
      setForceFit(true);
    });
  }, [add, handleEvent, setSelection, setForceFit]);

  // Fetch initial state once on mount
  React.useEffect(() => {
    const workflowLoadParamsStart = new Date();
    const eventName = 'workflow-params load';
    console.debug(
      'get-current-state pushed',
      workflowLoadParamsStart.toISOString()
    );
    console.time(eventName);

    pushEventTo(
      'get-current-state',
      {},
      (response: { workflow_params: WorkflowProps }) => {
        const { workflow_params } = response;
        setState(workflow_params);
        if (!workflow_params.triggers.length && !workflow_params.jobs.length) {
          const diff = createNewWorkflow();
          add(diff);
        }

        const end = new Date();
        console.debug('current-worflow-params processed', end.toISOString());
        console.timeEnd(eventName);

        pushEventTo('workflow_editor_metrics_report', {
          metrics: [
            {
              event: eventName,
              start: workflowLoadParamsStart.getTime(),
              end: end.getTime(),
            },
          ],
        });
      }
    );
  }, [pushEventTo, setState, add]);

  React.useEffect(() => {
    handleEvent('set-disabled', (response: { disabled: boolean }) => {
      setDisabled(response.disabled);
    });
  }, [handleEvent, setDisabled]);

  // clear store when store-component unmounted
  React.useEffect(() => {
    return () => {
      reset();
    }
  }, [reset])
  return <>{children}</>;
};
