import type { WithActionProps } from "#/react/lib/with-props";
import React from "react";
import { useWorkflowStore, type PendingAction } from "./store"

// This component renders nothing. it just serves as a syn to the backend
export const WorkflowStoreSync: WithActionProps = (props) => {
  const [pendingChanges, setPendingChanges] = React.useState<PendingAction[]>([]);
  const { applyPatches } = useWorkflowStore((v) => {
    setPendingChanges(p => p.concat(v));
    // store pending changes somewhere
    // pause processing. react over re-renders
    // void processPendingChanges();
  });

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
    while (pendingChanges.length > 0) {
      const pendingChange = pendingChanges[0];
      setPendingChanges(p => p.slice(1))
      // pushchange here
      if (pendingChange)
        await pushPendingChange(pendingChange)
    }
  }, [pendingChanges, pushPendingChange])

  React.useEffect(() => {
    props.handleEvent('patches-applied', (response: { patches: Patch[] }) => {
      console.debug('patches-applied', response.patches);
      // eslint-disable-next-line @typescript-eslint/no-unsafe-argument, @typescript-eslint/no-unnecessary-condition
      if (response.patches) applyPatches(response.patches)
    })
  }, [applyPatches, props])
  return <></>
}