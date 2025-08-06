/**
 * WorkflowStoreProvider - Yjs WorkflowStore for workflow-specific operations
 * Uses SessionProvider for shared Yjs/Phoenix Channel infrastructure
 */

import React, { createContext, useContext, useEffect, useState } from 'react';
import * as Y from 'yjs';
import { useSession } from './SessionProvider';
import type { WorkflowJob, Workflow, WorkflowStore } from '../types/workflow';

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

export const WorkflowStoreProvider: React.FC<WorkflowStoreProviderProps> = ({
  children,
}) => {
  const { ydoc, isConnected, isSynced, users } = useSession();

  // Domain-specific Yjs state
  const [workflowMap, setWorkflowMap] = useState<Y.Map<any> | null>(null);
  const [jobsArray, setJobsArray] = useState<Y.Array<WorkflowJob> | null>(null);

  // Domain-specific React state
  const [workflow, setWorkflow] = useState<Workflow | null>(null);
  const [jobs, setJobs] = useState<WorkflowJob[]>([]);
  const [selectedJobId, setSelectedJobId] = useState<string | null>(null);

  // Initialize domain-specific Yjs maps when ydoc is available
  useEffect(() => {
    if (!ydoc) {
      return;
    }

    console.log('🚀 Initializing WorkflowStore domain maps');

    // Get domain-specific Yjs maps
    const workflowMapInstance = ydoc.getMap<any>('workflow');
    const jobsArrayInstance = ydoc.getArray<WorkflowJob>('jobs');

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
      const jobsData = jobsArrayInstance.toArray();
      setJobs(jobsData);
    };

    // Set up observers for domain-specific data
    workflowMapInstance.observe(syncWorkflow);
    jobsArrayInstance.observe(syncJobs);

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

    const jobsData = jobsArray.toArray();
    const jobIndex = jobsData.findIndex(job => job.id === id);

    if (jobIndex !== -1) {
      const updatedJob = { ...jobsData[jobIndex], name };
      jobsArray.delete(jobIndex, 1);
      jobsArray.insert(jobIndex, [updatedJob]);
    }
  };

  const updateJobBody = (id: string, body: string) => {
    if (!jobsArray) return;

    const jobsData = jobsArray.toArray();
    const jobIndex = jobsData.findIndex(job => job.id === id);

    if (jobIndex !== -1) {
      const updatedJob = { ...jobsData[jobIndex], body };
      jobsArray.delete(jobIndex, 1);
      jobsArray.insert(jobIndex, [updatedJob]);
    }
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
  };

  return (
    <WorkflowStoreContext.Provider value={value}>
      {children}
    </WorkflowStoreContext.Provider>
  );
};
