import React from 'react';

import type { WithActionProps } from '#/react/lib/with-props';

import { randomUUID } from '../common';
import { DEFAULT_TEXT } from '../editor/Editor';

import {
  useWorkflowStore,
  type ChangeArgs,
  type RunInfo,
  type PendingAction,
  type ReplayAction,
  type WorkflowProps,
  type WorkflowRunHistory,
} from './store';

const createNewWorkflow = (): Required<ChangeArgs> => {
  const triggers = [
    {
      id: randomUUID(),
      type: 'webhook' as const,
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
  const pendingChanges = React.useRef<PendingAction[]>([]);
  const {
    applyPatches,
    setState,
    add,
    setSelection,
    subscribe,
    setDisabled,
    setForceFit,
    reset,
    updateRuns,
  } = useWorkflowStore();

  const pushPendingChange = React.useCallback(
    (pendingChange: PendingAction) => {
      return new Promise((resolve, reject) => {
        console.debug('pushing change', pendingChange);
        // How do we _undo_ the change if it fails?
        props.pushEventTo('push-change', pendingChange, response => {
          console.debug('push-change response', response);

          if (response && response.patches)
            applyPatches({
              patches: response.patches || [],
              inverse: response.inverse || [],
            });
          resolve(true);
        });
      });
    },
    [props, applyPatches]
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
    return props.handleEvent(
      'patches-applied',
      (response: Partial<ReplayAction>) => {
        console.debug('patches-applied', response);

        if (response && response.patches && response.patches.length)
          applyPatches({
            patches: response.patches || [],
            inverse: response.inverse || [],
          });
      }
    );
  }, [applyPatches, props]);

  React.useEffect(() => {
    return props.handleEvent(
      'state-applied',
      (response: { state: WorkflowProps }) => {
        console.log('state-applied', response.state);

        if (response.state)
          setState({
            ...response.state,
            positions: response.state.positions ?? null,
          });
      }
    );
  }, [setState, props]);

  React.useEffect(() => {
    const navigateCleanup = props.handleEvent('navigate', (e: any) => {
      const id = new URL(window.location.href).searchParams.get('s');

      // eslint-disable-next-line @typescript-eslint/no-unsafe-member-access
      if (e.patch) setSelection(id);
    });
    // force fitting
    const forcefitCleanup = props.handleEvent('force-fit', () => {
      setForceFit(true);
    });
    return () => {
      navigateCleanup();
      forcefitCleanup();
    };
  }, [add, props.handleEvent, setSelection, setForceFit]);

  React.useEffect(() => {
    return props.handleEvent(
      'patch-runs',
      (response: { run_id: string; run_steps: RunInfo }) => {
        updateRuns(response.run_steps, response.run_id);
      }
    );
  }, [props.handleEvent, updateRuns]);

  // Fetch initial state once on mount
  React.useEffect(() => {
    const workflowLoadParamsStart = new Date();
    const eventName = 'workflow-params load';
    console.debug(
      'get-current-state pushed',
      workflowLoadParamsStart.toISOString()
    );
    console.time(eventName);

    props.pushEventTo(
      'get-current-state',
      {},
      (response: {
        workflow_params: WorkflowProps;
        run_steps: RunInfo;
        run_id: string | null;
        history: WorkflowRunHistory;
      }) => {
        const { workflow_params, run_steps, run_id, history } = response;
        // workflow_params can contain an empty array of nodes and edges (empty workflow)
        setState(workflow_params);
        updateRuns(run_steps, run_id, history);

        const end = new Date();
        console.debug('current-worflow-params processed', end.toISOString());
        console.timeEnd(eventName);

        props.pushEventTo('workflow_editor_metrics_report', {
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
  }, [props.pushEventTo, setState, add, updateRuns]);

  React.useEffect(() => {
    return props.handleEvent(
      'set-disabled',
      (response: { disabled: boolean }) => {
        setDisabled(response.disabled);
      }
    );
  }, [props.handleEvent, setDisabled]);

  // clear store when store-component unmounted
  React.useEffect(() => {
    return () => {
      reset();
    };
  }, [reset]);

  return <>{props.children}</>;
};
