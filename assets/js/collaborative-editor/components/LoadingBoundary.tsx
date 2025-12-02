/**
 * LoadingBoundary - Async boundary for Y.Doc synchronization
 *
 * Prevents rendering before Y.Doc is fully synced with the server.
 * This eliminates race conditions that cause:
 * - Bug 1: Nodes collapsing to center (positions not yet synced)
 * - Bug 2: "Old version" errors (lock_version not yet synced)
 *
 * Components inside this boundary can safely assume workflow data exists
 * and is fully synchronized, eliminating the need for defensive null checks.
 */

import React from 'react';

import { useSession } from '../hooks/useSession';
import { useSessionContextLoading } from '../hooks/useSessionContext';
import { useWorkflowState } from '../hooks/useWorkflow';

interface LoadingBoundaryProps {
  children: React.ReactNode;
}

export function LoadingBoundary({ children }: LoadingBoundaryProps) {
  const session = useSession();
  const workflow = useWorkflowState(state => state.workflow);
  const sessionContextLoading = useSessionContextLoading();

  // Wait for ALL sync conditions before rendering (initial load only)
  // - session.settled: Y.Doc has synced AND received first update from provider
  // - workflow !== null: WorkflowStore observers have populated state
  // - !sessionContextLoading: SessionContext (including latestSnapshotLockVersion) is loaded
  //
  // After initial hydration: only require workflow to exist
  // - This prevents flickering during transitions (room migrations, reconnects)
  // - Previous workflow data remains valid and visible during brief disconnects
  const hasWorkflow = workflow !== null;
  const fullReady = hasWorkflow && session.settled && !sessionContextLoading;

  // hydrated - have all conditions been met? (fullReady)
  const [hydrated, setHydrated] = React.useState(false);

  // - When fullReady becomes true -> we mark hydration complete
  // - When workflow disappears -> we reset hydration (wait for a fullReady once again)
  React.useEffect(() => {
    if (fullReady && !hydrated) {
      setHydrated(true);
    } else if (!hasWorkflow && hydrated) {
      setHydrated(false);
    }
  }, [fullReady, hasWorkflow, hydrated]);

  // after hydration require just the presence of a workflow
  const isReady = hydrated ? hasWorkflow : fullReady;

  if (!isReady) {
    return (
      <div className="flex items-center justify-center h-full w-full">
        <span className="relative inline-flex">
          <div className="inline-flex">
            <p className="text-gray-600">Loading workflow</p>
          </div>
          <span className="flex absolute h-3 w-3 right-0 -mr-5">
            <span className="animate-ping absolute inline-flex h-full w-full rounded-full bg-primary-400 opacity-75"></span>
            <span className="relative inline-flex rounded-full h-3 w-3 bg-primary-500"></span>
          </span>
        </span>
      </div>
    );
  }

  return <>{children}</>;
}
