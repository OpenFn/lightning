/**
 * # Session Context Hooks
 *
 * Provides React hooks for consuming session context data with maximum referential stability.
 * These hooks use useSyncExternalStore with memoized selectors to minimize re-renders.
 *
 * ## Core Hooks:
 * - `useUser()`: Current user data
 * - `useProject()`: Current project data
 * - `useProjectRepoConnection()`: GitHub integration connection (null if not configured)
 * - `useAppConfig()`: Application configuration
 * - `useSessionContextLoading()`: Loading state
 * - `useSessionContextError()`: Error state
 *
 * ## Usage Examples:
 *
 * ```typescript
 * // Get current user
 * const user = useUser();
 *
 * // Get project info
 * const project = useProject();
 *
 * // Get app configuration
 * const config = useAppConfig();
 *
 * // Check loading state
 * const isLoading = useSessionContextLoading();
 *
 * // Check for errors
 * const error = useSessionContextError();
 * ```
 */

import { useSyncExternalStore, useContext } from 'react';

import { StoreContext } from '../contexts/StoreProvider';
import type { SessionContextStoreInstance } from '../stores/createSessionContextStore';
import type {
  UserContext,
  ProjectContext,
  ProjectRepoConnection,
  AppConfig,
  Permissions,
} from '../types/sessionContext';

/**
 * Main hook for accessing the SessionContextStore instance
 * Handles context access and error handling once
 */
const useSessionContextStore = (): SessionContextStoreInstance => {
  const context = useContext(StoreContext);
  if (!context) {
    throw new Error(
      'useSessionContextStore must be used within a StoreProvider'
    );
  }
  return context.sessionContextStore;
};

/**
 * Hook to get current user data
 * Returns null if user is not yet loaded
 */
export const useUser = (): UserContext | null => {
  const sessionContextStore = useSessionContextStore();

  const selectUser = sessionContextStore.withSelector(state => state.user);

  return useSyncExternalStore(sessionContextStore.subscribe, selectUser);
};

/**
 * Hook to get current project data
 * Returns null if project is not yet loaded
 */
export const useProject = (): ProjectContext | null => {
  const sessionContextStore = useSessionContextStore();

  const selectProject = sessionContextStore.withSelector(
    state => state.project
  );

  return useSyncExternalStore(sessionContextStore.subscribe, selectProject);
};

/**
 * Hook to get project repo connection (GitHub integration)
 * Returns null if no GitHub connection is configured for the project
 */
export const useProjectRepoConnection = (): ProjectRepoConnection | null => {
  const sessionContextStore = useSessionContextStore();

  const selectRepoConnection = sessionContextStore.withSelector(
    state => state.projectRepoConnection
  );

  return useSyncExternalStore(
    sessionContextStore.subscribe,
    selectRepoConnection
  );
};

/**
 * Hook to get application configuration
 * Returns null if config is not yet loaded
 */
export const useAppConfig = (): AppConfig | null => {
  const sessionContextStore = useSessionContextStore();

  const selectConfig = sessionContextStore.withSelector(state => state.config);

  return useSyncExternalStore(sessionContextStore.subscribe, selectConfig);
};

/**
 * Hook to get loading state
 * Returns true when session context is being loaded
 */
export const useSessionContextLoading = (): boolean => {
  const sessionContextStore = useSessionContextStore();

  const selectLoading = sessionContextStore.withSelector(
    state => state.isLoading
  );

  return useSyncExternalStore(sessionContextStore.subscribe, selectLoading);
};

/**
 * Hook to get error state
 * Returns error message if loading failed, null otherwise
 */
export const useSessionContextError = (): string | null => {
  const sessionContextStore = useSessionContextStore();

  const selectError = sessionContextStore.withSelector(state => state.error);

  return useSyncExternalStore(sessionContextStore.subscribe, selectError);
};

/**
 * Hook to get user permissions from session context
 * Returns null if not loaded yet
 */
export const usePermissions = (): Permissions | null => {
  const sessionContextStore = useSessionContextStore();

  const selectPermissions = sessionContextStore.withSelector(
    state => state.permissions
  );

  return useSyncExternalStore(sessionContextStore.subscribe, selectPermissions);
};

/**
 * Hook to get latest snapshot lock version from session context
 * Returns null if not loaded yet
 */
export const useLatestSnapshotLockVersion = (): number | null => {
  const sessionContextStore = useSessionContextStore();

  const selectLockVersion = sessionContextStore.withSelector(
    state => state.latestSnapshotLockVersion
  );

  return useSyncExternalStore(sessionContextStore.subscribe, selectLockVersion);
};

/**
 * Hook to check if this is a new workflow being created
 * Returns true during initial workflow creation, false after first save
 */
export const useIsNewWorkflow = (): boolean => {
  const sessionContextStore = useSessionContextStore();

  const selectIsNewWorkflow = sessionContextStore.withSelector(
    state => state.isNewWorkflow
  );

  return useSyncExternalStore(
    sessionContextStore.subscribe,
    selectIsNewWorkflow
  );
};

/**
 * Hook to get the entire session context state
 * Useful when you need multiple pieces of session context at once
 * Returns the full session context state object
 */
export const useSessionContext = () => {
  const sessionContextStore = useSessionContextStore();

  const selectState = sessionContextStore.withSelector(state => state);

  return useSyncExternalStore(sessionContextStore.subscribe, selectState);
};
