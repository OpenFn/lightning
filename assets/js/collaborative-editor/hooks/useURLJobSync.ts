import { useEffect } from "react";
import { useURLState } from "#/react/lib/use-url-state";
import type { Store, Workflow } from "../types";

/**
 * Syncs selected job between URL params and store
 */
export const useURLJobSync = (store: Store<Workflow.Store>) => {
  const { searchParams, updateSearchParams } = useURLState();
  const selectedJobId = searchParams.get("job");

  // Sync URL → Store
  useEffect(() => {
    store.getState().selectJob(selectedJobId);
  }, [selectedJobId, store]);

  // Sync Store → URL
  useEffect(() => {
    const unsubscribe = store.subscribe(
      (state) => state.selectedJobId,
      (selectedJobId) => {
        const currentJobFromURL = searchParams.get("job");
        if (selectedJobId !== currentJobFromURL) {
          updateSearchParams({ job: selectedJobId });
        }
      },
    );

    return unsubscribe;
  }, [store, searchParams, updateSearchParams]);
};
