/**
 * WorkflowStoreProvider - Provider component for workflow state management
 *
 * This provider implements the useSyncExternalStore + Immer + Y.Doc pattern for
 * referentially stable workflow state management with proper separation between
 * collaborative data and local UI state.
 *
 * ## Usage:
 *
 * ```tsx
 * import { WorkflowStoreProvider } from "./contexts/WorkflowStoreProvider";
 *
 * function App() {
 *   return (
 *     <WorkflowStoreProvider>
 *       <YourWorkflowComponents />
 *     </WorkflowStoreProvider>
 *   );
 * }
 * ```
 *
 * ## Hooks for Interacting with WorkflowStore:
 *
 * All React hooks for workflow state management are located in:
 * **`../hooks/Workflow.ts`**
 *
 * ### Available Hooks:
 * - `useWorkflowSelector` - Complex selections with store method access
 * - `useWorkflowState` - Simple state-only selections
 * - `useWorkflowActions` - Action commands (CQS pattern)
 * - `useCurrentJob` - Current selected job with YJS YText
 * - `useNodeSelection` - URL-based node selection
 * - And more specialized hooks...
 *
 * ### Import Pattern:
 * ```tsx
 * import {
 *   useWorkflowSelector,
 *   useWorkflowState,
 *   useWorkflowActions
 * } from "../hooks/Workflow";
 * ```
 *
 * @see ../hooks/Workflow.ts for complete hook documentation and examples
 */

import type React from "react";
import { createContext, useContext, useEffect, useState } from "react";

import {
  createWorkflowStore,
  type WorkflowStoreInstance,
} from "../stores/createWorkflowStore";
import type { Session } from "../types/session";

import { useSession } from "./SessionProvider";

const WorkflowStoreContext = createContext<WorkflowStoreInstance | null>(null);

/**
 * Hook to access the WorkflowStore context.
 *
 * This is primarily for internal use by hooks in the Workflow.ts module.
 * Most components should use the specialized hooks instead.
 *
 * @internal Use hooks from ../hooks/Workflow.ts instead
 */
export const useWorkflowStoreContext = () => {
  const store = useContext(WorkflowStoreContext);
  if (!store) {
    throw new Error(
      "useWorkflowStore must be used within WorkflowStoreProvider"
    );
  }
  return store;
};

interface WorkflowStoreProviderProps {
  children: React.ReactNode;
}

/**
 * Provider component that creates and manages the WorkflowStore instance.
 *
 * Handles:
 * - Store creation with lazy initialization
 * - Y.Doc connection/disconnection based on session state
 * - Context provision for child components
 *
 * For detailed information about the store's three update patterns and architectural
 * principles, see the comprehensive documentation in:
 *
 * @see ../stores/createWorkflowStore.ts - Complete pattern documentation with examples
 */
export function WorkflowStoreProvider({
  children,
}: WorkflowStoreProviderProps) {
  const { ydoc } = useSession();
  const [store] = useState(createWorkflowStore());

  // Connect/disconnect Y.Doc when session changes
  useEffect(() => {
    if (ydoc) {
      store.connectYDoc(ydoc as Session.WorkflowDoc);
      return () => store.disconnectYDoc();
    } else {
      store.disconnectYDoc();
      return undefined;
    }
  }, [store, ydoc]);

  return (
    <WorkflowStoreContext.Provider value={store}>
      {children}
    </WorkflowStoreContext.Provider>
  );
}
