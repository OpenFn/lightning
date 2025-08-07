/**
 * WorkflowEditor - Main workflow editing component
 * Replaces TodoList with workflow-specific functionality
 */

import React from 'react';
import { useWorkflowStore } from '../contexts/WorkflowStoreProvider';
import { useSession } from '../contexts/SessionProvider';
import { WorkflowHeader } from './WorkflowHeader';
import { UserAwareness } from './UserAwareness';
import { JobsList } from './JobsList';
import { CollaborativeMonaco } from './CollaborativeMonaco';

export const WorkflowEditor: React.FC = () => {
  const { workflow, jobs, selectedJobId, getJobBodyYText } = useWorkflowStore();
  const { awareness } = useSession();

  const selectedJob = selectedJobId
    ? jobs.find(job => job.id === selectedJobId)
    : null;

  const selectedJobYText = selectedJobId
    ? getJobBodyYText(selectedJobId)
    : null;

  return (
    <div className="flex flex-col h-full">
      {/* Header Section */}
      <div className="flex-none p-4 border-b border-gray-200">
        {/* Workflow Header */}
        <WorkflowHeader />

        {/* User awareness */}
        <UserAwareness />
      </div>

      {/* Main Content */}
      <div className="flex flex-1 min-h-0">
        {/* Jobs List Sidebar */}
        <div className="flex-none w-80 border-r border-gray-200 overflow-y-auto">
          <JobsList />

          {/* Workflow statistics */}
          {workflow && (
            <div className="p-4 border-t border-gray-200">
              <div className="flex justify-between text-sm text-gray-500">
                <span>Workflow: {workflow.name}</span>
                <span>{jobs.length} jobs</span>
              </div>
            </div>
          )}
        </div>

        {/* Job Editor */}
        <div className="flex-1 min-w-0">
          {selectedJob && selectedJobYText && awareness ? (
            <CollaborativeMonaco
              ytext={selectedJobYText}
              awareness={awareness}
              adaptor="common"
              disabled={false}
              className="h-full w-full"
            />
          ) : (
            <div className="flex items-center justify-center h-full text-gray-500">
              <div className="text-center">
                <p className="text-lg">Select a job to edit</p>
                <p className="text-sm">
                  Choose a job from the sidebar to start editing with the
                  collaborative Monaco editor
                </p>
              </div>
            </div>
          )}
        </div>
      </div>
    </div>
  );
};
