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

import { useSession } from "../hooks/useSession";
import { useSessionContextLoading } from "../hooks/useSessionContext";
import { useWorkflowState } from "../hooks/useWorkflow";

interface LoadingBoundaryProps {
  children: React.ReactNode;
}

export function LoadingBoundary({ children }: LoadingBoundaryProps) {
  const session = useSession();
  const workflow = useWorkflowState(state => state.workflow);
  const sessionContextLoading = useSessionContextLoading();

  // Wait for ALL sync conditions before rendering
  // - session.isSynced: Y.Doc has received and applied all initial data
  // - workflow !== null: WorkflowStore observers have populated state
  // - !sessionContextLoading: SessionContext (including latestSnapshotLockVersion) is loaded
  const isReady =
    session.isSynced && workflow !== null && !sessionContextLoading;

  if (!isReady) {
    return (
      <div className="flex items-center justify-center h-full w-full">
        <div className="text-center">
          <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-primary-600 mx-auto mb-4" />
          <p className="text-gray-600">Syncing workflow...</p>
        </div>
      </div>
    );
  }

  return <>{children}</>;
}
