/**
 * WorkflowStoreProvider - Yjs WorkflowStore for workflow-specific operations
 * Uses SessionProvider for shared Yjs/Phoenix Channel infrastructure
 */

import React, { createContext, useContext, useEffect, useState } from 'react';
import * as Y from 'yjs';
import { useSession } from './SessionProvider';
import type {
  WorkflowJobData,
  Workflow,
  WorkflowStore,
} from '../types/workflow';
import type { TypedMap, TypedArray, TypedDoc } from 'yjs-types';
import { useURLState } from '#/react/lib/use-url-state';

interface WorkflowStoreContextValue extends WorkflowStore {
  // Domain-specific workflow operations only
  // Session concerns (ydoc, awareness, users, connection) come from useSession
}

const WorkflowStoreContext = createContext<WorkflowStoreContextValue | null>(
  null
);

export const useWorkflowStore = () => {
  const context = useContext(WorkflowStoreContext);
  if (!context) {
    throw new Error(
      'useWorkflowStore must be used within a WorkflowStoreProvider'
    );
  }
  return context;
};

interface WorkflowStoreProviderProps {
  children: React.ReactNode;
}

// TODO: move this somewhere else, but take note that we are using a 3rd party
// library to type the Yjs document.
type WorkflowDoc = TypedDoc<
  { workflow: TypedMap<{ id: string; name: string }> },
  { jobs: TypedArray<Y.Map<{ id: string; name: string; body: Y.Text }>> }
>;

export const WorkflowStoreProvider: React.FC<WorkflowStoreProviderProps> = ({
  children,
}) => {
  const { ydoc: ydoc_, isConnected, isSynced, users } = useSession();
  const ydoc = ydoc_ as WorkflowDoc;

  // Domain-specific Yjs state
  const [_workflowMap, setWorkflowMap] = useState<Y.Map<any> | null>(null);
  const [jobsArray, setJobsArray] = useState<Y.Array<Y.Map<any>> | null>(null);

  // Domain-specific React state
  const [workflow, setWorkflow] = useState<Workflow | null>(null);
  const [jobs, setJobs] = useState<WorkflowJobData[]>([]);

  const { searchParams, updateSearchParams } = useURLState();
  const selectedJobId = searchParams.get('job');

  const setSelectedJobId = (jobId: string) => {
    updateSearchParams({ job: jobId });
  };

  // Initialize domain-specific Yjs maps when ydoc is available
  useEffect(() => {
    if (!ydoc) {
      return;
    }

    console.log('🚀 Initializing WorkflowStore domain maps');

    // Get domain-specific Yjs maps
    const workflowMapInstance = ydoc.getMap('workflow');
    const jobsArrayInstance = ydoc.getArray('jobs');

    // Sync workflow state to React
    const syncWorkflow = () => {
      const workflowData = workflowMapInstance.toJSON();
      if (workflowData.id && workflowData.name !== undefined) {
        setWorkflow({
          id: workflowData.id,
          name: workflowData.name,
        });
      } else {
        setWorkflow(null);
      }
    };

    // Sync jobs state to React
    const syncJobs = () => {
      const yjsJobs = jobsArrayInstance.toArray(); // Array of Y.Map objects
      const jobsData: WorkflowJobData[] = yjsJobs.map(yjsJob => {
        const yText = yjsJob.get('body') as Y.Text;
        return {
          id: yjsJob.get('id') as string,
          name: yjsJob.get('name') as string,
          body: yText ? yText.toString() : '', // Convert Y.Text to string for display
        };
      });
      setJobs(jobsData);
    };

    // Set up observers on Y.Text bodies within jobs for real-time updates
    const setupJobBodyObservers = () => {
      const yjsJobs = jobsArrayInstance.toArray();
      yjsJobs.forEach(yjsJob => {
        const ytext = yjsJob.get('body') as Y.Text;
        if (ytext) {
          ytext.observe(() => {
            // Trigger syncJobs to update React state when job body changes
            syncJobs();
          });
        }
      });
    };

    // Set up observers for domain-specific data
    workflowMapInstance.observe(syncWorkflow);

    // Re-setup observers when jobs array changes
    jobsArrayInstance.observe(() => {
      syncJobs();
      setupJobBodyObservers();
    });

    setupJobBodyObservers();

    // Store domain state
    setWorkflowMap(workflowMapInstance);
    setJobsArray(jobsArrayInstance);

    // Initial sync
    syncWorkflow();
    syncJobs();

    // Cleanup function
    return () => {
      console.debug('WorkflowStore: cleaning up domain maps');
      setWorkflowMap(null);
      setJobsArray(null);
      setWorkflow(null);
      setJobs([]);
      setSelectedJobId(null);
    };
  }, [ydoc]);

  // Workflow operations
  const selectJob = (id: string | null) => {
    setSelectedJobId(id);
  };

  const updateJobName = (id: string, name: string) => {
    if (!jobsArray) return;

    const yjsJobs = jobsArray.toArray();
    const jobYMap = yjsJobs.find(yjsJob => yjsJob.get('id') === id);

    if (jobYMap) {
      jobYMap.set('name', name);
    }
  };

  const updateJobBody = (id: string, body: string) => {
    const yjsJob = getYjsJob(id);

    if (!yjsJob) {
      console.warn(
        `WorkflowStoreProvider: updateJobBody: job not found for id: ${id}`
      );
      return;
    }

    const ytext = yjsJob.get('body') as Y.Text;
    if (!ytext) {
      console.warn(
        `WorkflowStoreProvider: updateJobBody: job body Y.Text not found for id: ${id}`
      );
      return;
    }

    // Replace the entire text content
    ytext.delete(0, ytext.length);
    ytext.insert(0, body);
  };

  const getJobBodyYText = (id: string): Y.Text | null => {
    const yjsJob = getYjsJob(id);
    if (!yjsJob) {
      return null;
    }

    const ytext = yjsJob.get('body') as Y.Text;
    return ytext;
  };

  // Get Yjs Y.Map job by id
  const getYjsJob = (id: string): Y.Map<any> | null => {
    if (!jobsArray) return null;

    const yjsJobs = jobsArray.toArray();
    return yjsJobs.find(yjsJob => yjsJob.get('id') === id) || null;
  };

  // Get plain JS job data by id (for display)
  const getJob = (id: string): WorkflowJobData | null => {
    return jobs.find(job => job.id === id) || null;
  };

  const value: WorkflowStoreContextValue = {
    workflow,
    jobs,
    selectedJobId,
    users,
    isConnected,
    isSynced,
    selectJob,
    updateJobName,
    updateJobBody,
    getJobBodyYText,
    getYjsJob,
  };

  return (
    <WorkflowStoreContext.Provider value={value}>
      {children}
    </WorkflowStoreContext.Provider>
  );
};
