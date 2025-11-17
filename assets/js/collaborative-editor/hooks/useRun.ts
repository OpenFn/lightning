import { useContext, useMemo, useSyncExternalStore } from 'react';

import { StoreContext } from '../contexts/StoreProvider';
import type { RunStoreInstance } from '../stores/createRunStore';
import type { Run, Step } from '../types/run';

const useRunStore = (): RunStoreInstance => {
  const context = useContext(StoreContext);
  if (!context) {
    throw new Error('useRunStore must be used within StoreProvider');
  }
  return context.runStore;
};

export const useCurrentRun = (): Run | null => {
  const runStore = useRunStore();
  const selectRun = useMemo(
    () => runStore.withSelector(state => state.currentRun),
    [runStore]
  );
  return useSyncExternalStore(runStore.subscribe, selectRun);
};

export const useRunSteps = (): Step[] => {
  const runStore = useRunStore();
  const selectSteps = useMemo(
    () => runStore.withSelector(state => state.currentRun?.steps || []),
    [runStore]
  );
  return useSyncExternalStore(runStore.subscribe, selectSteps);
};

export const useRunLoading = (): boolean => {
  const runStore = useRunStore();
  const selectLoading = useMemo(
    () => runStore.withSelector(state => state.isLoading),
    [runStore]
  );
  return useSyncExternalStore(runStore.subscribe, selectLoading);
};

export const useRunError = (): string | null => {
  const runStore = useRunStore();
  const selectError = useMemo(
    () => runStore.withSelector(state => state.error),
    [runStore]
  );
  return useSyncExternalStore(runStore.subscribe, selectError);
};

export const useSelectedStepId = (): string | null => {
  const runStore = useRunStore();
  const selectStepId = useMemo(
    () => runStore.withSelector(state => state.selectedStepId),
    [runStore]
  );
  return useSyncExternalStore(runStore.subscribe, selectStepId);
};

export const useSelectedStep = (): Step | null => {
  const runStore = useRunStore();
  const selectStep = useMemo(
    () =>
      runStore.withSelector(state => {
        if (!state.selectedStepId || !state.currentRun) return null;
        return (
          state.currentRun.steps.find(s => s.id === state.selectedStepId) ||
          null
        );
      }),
    [runStore]
  );
  return useSyncExternalStore(runStore.subscribe, selectStep);
};

export const useRunActions = () => {
  const runStore = useRunStore();

  return useMemo(
    () => ({
      selectStep: runStore.selectStep,
      clearError: runStore.clearError,
      clear: runStore.clear,
    }),
    [runStore]
  );
};

// For internal use by RunViewerPanel
export const useRunStoreInstance = (): RunStoreInstance => {
  return useRunStore();
};
