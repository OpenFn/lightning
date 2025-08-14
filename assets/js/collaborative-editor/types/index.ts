/**
 * Re-exports for backward compatibility during migration
 * New code should import from specific type files instead
 */

// Re-export session and trigger types
export type { AwarenessUser, Session } from "./session";
export type { Trigger } from "./trigger";
// Re-export types from workflow.ts for backward compatibility
export type { Workflow, YjsBridge } from "./workflow";

// Generic store interface for Zustand stores with Immer middleware (legacy)
export interface Store<T> {
  getState: () => T;
  setState: (partial: Partial<T> | ((state: T) => void)) => void;
  subscribe: (
    selector: (state: T) => unknown,
    listener: (selectedState: unknown, previousSelectedState: unknown) => void,
  ) => () => void;
}
