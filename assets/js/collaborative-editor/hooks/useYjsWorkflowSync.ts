import { useEffect } from "react";
import type * as Y from "yjs";
import type { TypedMap } from "yjs-types";
import type { Store, Workflow } from "../types";
import type { Session } from "../types/session";

interface YjsBridge {
  workflowMap: Y.Map<unknown>;
  jobsArray: Y.Array<Y.Map<unknown>>;
  edgesArray: Y.Array<Y.Map<unknown>>;
  getYjsJob: (id: string) => Y.Map<unknown> | null;
  getJobBodyText: (id: string) => Y.Text | null;
}

/**
 * Sets up bidirectional sync between Yjs document and Zustand store
 */
export const useYjsWorkflowSync = (
  ydoc: Session.WorkflowDoc | null,
  store: Store<Workflow.Store>,
) => {
  useEffect(() => {
    console.log("WorkflowStoreProvider: useEffect", store);
    if (!ydoc || !store) return;

    // Get domain-specific Yjs maps
    const workflowMap = ydoc.getMap("workflow");
    const jobsArray = ydoc.getArray("jobs");
    const edgesArray = ydoc.getArray("edges");

    // Create bridge for Yjs operations
    const yjsBridge: YjsBridge = {
      workflowMap: workflowMap as Y.Map<unknown>,
      jobsArray: jobsArray as Y.Array<Y.Map<unknown>>,
      edgesArray: edgesArray as Y.Array<Y.Map<unknown>>,
      getYjsJob: (id: string) => {
        const jobs = jobsArray.toArray();
        return jobs.find((job) => job.get("id") === id) || null;
      },
      getJobBodyText: (id: string) => {
        const jobs = jobsArray.toArray();
        const yjsJob = jobs.find((job) => job.get("id") === id);
        return (yjsJob?.get("body") as Y.Text) || null;
      },
    };

    // Connect the bridge to the store
    store.getState().connectToYjs(yjsBridge);

    const cleanupWorkflowSync = observeY(
      workflowMap as Y.Map<unknown>,
      (workflowMap) => {
        const workflow = workflowMap.toJSON() as Session.Workflow;
        if (workflow.id && workflow.name !== undefined) {
          store.setState({ workflow });
        } else {
          store.setState({ workflow: null });
        }
      },
    );

    // Sync jobs state to React
    const cleanupJobsSync = observeY(
      jobsArray as Y.Array<unknown>,
      (jobsArray) => {
        const yjsJobs = (
          jobsArray as Y.Array<Y.Map<unknown>>
        ).toArray() as TypedMap<Session.Job & { body: Y.Text }>[];

        const jobsData: Workflow.Job[] = yjsJobs.map((yjsJob) => {
          return yjsJob.toJSON() as Workflow.Job;
        });

        store.setState({ jobs: jobsData });
      },
    );

    const cleanupEdgesSync = observeY(
      edgesArray as Y.Array<unknown>,
      (edgesArray) => {
        const yjsEdges = (
          edgesArray as Y.Array<Y.Map<unknown>>
        ).toArray() as TypedMap<Session.Edge>[];
        const edgesData: Session.Edge[] = yjsEdges.map((yjsEdge) => {
          return yjsEdge.toJSON() as Session.Edge;
        });
        store.setState({ edges: edgesData });
      },
    );

    // Cleanup function
    return () => {
      console.debug("WorkflowStore: cleaning up domain maps");
      cleanupWorkflowSync();
      cleanupJobsSync();
      cleanupEdgesSync();
    };
  }, [ydoc, store]);
};

function observeY<T extends Y.Map<unknown> | Y.Array<unknown>>(
  sharedType: T,
  callback: (sharedType: T) => void,
): () => void {
  function onChange() {
    console.log("useYjsWorkflowSync: onChange", sharedType);
    callback(sharedType);
  }

  sharedType.observe(onChange);

  return () => {
    sharedType.unobserve(onChange);
  };
}
