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

  // Wait for ALL sync conditions before rendering
  // - session.settled: Y.Doc has synced AND received first update from provider
  // - workflow !== null: WorkflowStore observers have populated state
  // - !sessionContextLoading: SessionContext (including latestSnapshotLockVersion) is loaded

  const isReady =
    session.settled && workflow !== null && !sessionContextLoading;

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
