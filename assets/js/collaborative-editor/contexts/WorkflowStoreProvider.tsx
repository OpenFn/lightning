/**
 * WorkflowStoreProvider - Yjs WorkflowStore for workflow-specific operations
 * Uses SessionProvider for shared Yjs/Phoenix Channel infrastructure
 */

import { useURLState } from '#/react/lib/use-url-state';
import React, { createContext, useContext, useEffect, useState } from 'react';
import * as Y from 'yjs';
import type { TypedMap } from 'yjs-types';
import type { Lightning } from '../../workflow-diagram/types';
import type { Session } from '../types/session';
import type { Workflow, WorkflowStore } from '../types/workflow';
import { useSession } from './SessionProvider';

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
  const { ydoc: ydoc_, isConnected, isSynced, users } = useSession();
  const ydoc = ydoc_ as Session.WorkflowDoc;

  // Domain-specific Yjs state
  const [_workflowMap, setWorkflowMap] = useState<Y.Map<any> | null>(null);
  const [jobsArray, setJobsArray] = useState<Y.Array<Y.Map<any>> | null>(null);

  // Domain-specific React state
  const [workflow, setWorkflow] = useState<Workflow | null>(null);
  const [jobs, setJobs] = useState<Session.Job[]>([]);
  const [edges, setEdges] = useState<Session.Edge[]>([]);

  const { searchParams, updateSearchParams } = useURLState();
  const selectedJobId = searchParams.get('job');

  const selectJob = (jobId: string | null) => {
    updateSearchParams({ job: jobId });
  };

  // Initialize domain-specific Yjs maps when ydoc is available
  useEffect(() => {
    if (!ydoc) {
      return;
    }

    // Get domain-specific Yjs maps
    const workflowMapInstance = ydoc.getMap('workflow');
    const jobsArrayInstance = ydoc.getArray('jobs');
    const edgesArrayInstance = ydoc.getArray('edges');

    // Sync workflow state to React
    const syncWorkflow = () => {
      const workflowData = workflowMapInstance.toJSON() as Session.Workflow;
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
      const yjsJobs = jobsArrayInstance.toArray() as TypedMap<
        Session.Job & { body: Y.Text }
      >[];
      const jobsData: Session.Job[] = yjsJobs.map(yjsJob => {
        // TODO: try toJSON(), see if it handles the Y.Text case
        const yText = yjsJob.get('body') as Y.Text;
        return {
          id: yjsJob.get('id') as string,
          name: yjsJob.get('name') as string,
          body: yText ? yText.toString() : '', // Convert Y.Text to string for display
        };
      });
      setJobs(jobsData);
    };

    const syncEdges = () => {
      function onEdgeChange() {
        const yjsEdges =
          edgesArrayInstance.toArray() as TypedMap<Session.Edge>[];
        const edgesData: Session.Edge[] = yjsEdges.map(yjsEdge => {
          return yjsEdge.toJSON() as Session.Edge;
        });
        setEdges(edgesData);
      }

      edgesArrayInstance.observe(onEdgeChange);

      return () => {
        edgesArrayInstance.unobserve(onEdgeChange);
        setEdges([]);
      };
    };

    // Set up observers on Y.Text bodies within jobs for real-time updates
    const setupJobBodyObservers = () => {
      const yjsJobs = jobsArrayInstance.toArray() as TypedMap<Session.Job>[];
      yjsJobs.forEach(yjsJob => {
        const ytext = yjsJob.get('body');
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
      // Do we need to re-setup job body observers?
      setupJobBodyObservers();
    });

    setupJobBodyObservers();

    // Store domain state
    setWorkflowMap(workflowMapInstance);
    setJobsArray(jobsArrayInstance);

    // Initial sync
    syncWorkflow();
    syncJobs();

    const cleanupEdges = syncEdges();

    // Cleanup function
    return () => {
      console.debug('WorkflowStore: cleaning up domain maps');
      setWorkflowMap(null);
      setJobsArray(null);
      setWorkflow(null);
      setJobs([]);
      selectJob(null);
      cleanupEdges();
    };
  }, [ydoc]);

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

  // Transform collaborative jobs to Lightning format for WorkflowDiagram
  const getLightningJobs = (): Lightning.JobNode[] => {
    return jobs.map(job => ({
      id: job.id,
      name: job.name,
      workflow_id: workflow?.id || '',
      body: job.body,
      adaptor: 'common',
    }));
  };

  const value: WorkflowStoreContextValue = {
    workflow,
    jobs,
    edges,
    selectedJobId,
    users,
    isConnected,
    isSynced,
    selectJob,
    updateJobName,
    updateJobBody,
    getJobBodyYText,
    getYjsJob,
    // WorkflowDiagram compatibility
    getLightningJobs,
    triggers: [], // Phase 1: empty
    disabled: false, // Phase 1: always enabled
    positions: null, // Phase 1: auto-layout
    updatePositions: () => {
      console.log('Phase 1: updatePositions not implemented');
    },
    updatePosition: () => {
      console.log('Phase 1: updatePosition not implemented');
    },
    undo: () => {
      console.log('Phase 1: undo not implemented');
    },
    redo: () => {
      console.log('Phase 1: redo not implemented');
    },
  };

  return (
    <WorkflowStoreContext.Provider value={value}>
      {children}
    </WorkflowStoreContext.Provider>
  );
};
