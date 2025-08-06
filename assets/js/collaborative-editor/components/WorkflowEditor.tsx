/**
 * WorkflowEditor - Main workflow editing component
 * Replaces TodoList with workflow-specific functionality
 */

import React from 'react';
import { useWorkflowStore } from '../contexts/WorkflowStoreProvider';
import { WorkflowHeader } from './WorkflowHeader';
import { UserAwareness } from './UserAwareness';
import { JobsList } from './JobsList';

export const WorkflowEditor: React.FC = () => {
  const { workflow, jobs, selectedJobId } = useWorkflowStore();

  const selectedJob = selectedJobId
    ? jobs.find(job => job.id === selectedJobId)
    : null;

  return (
    <div className="w-full max-w-4xl mx-auto p-4">
      {/* Workflow Header */}
      <WorkflowHeader />

      {/* User awareness */}
      <UserAwareness />

      {/* Jobs List */}
      <JobsList />

      {/* Selected Job Details */}
      {selectedJob && (
        <div className="mb-6">
          <h3 className="text-lg font-semibold text-gray-900 mb-4">
            Selected Job Details
          </h3>
          <div className="bg-blue-50 border border-blue-200 rounded-lg p-6">
            <h4 className="text-xl font-medium text-blue-900 mb-2">
              {selectedJob.name || 'Untitled Job'}
            </h4>
            <p className="text-sm text-blue-600 mb-4">ID: {selectedJob.id}</p>

            <div className="mb-4">
              <label className="block text-sm font-medium text-blue-800 mb-2">
                Job Body:
              </label>
              <div className="bg-white border border-blue-300 rounded-md p-4">
                <pre className="text-sm text-gray-800 whitespace-pre-wrap font-mono">
                  {selectedJob.body || '(No job body defined)'}
                </pre>
              </div>
            </div>

            <p className="text-xs text-blue-600">
              💡 This job body will be editable with Monaco editor in the next
              phase
            </p>
          </div>
        </div>
      )}

      {/* Workflow statistics */}
      {workflow && (
        <div className="mt-6 pt-4 border-t border-gray-200">
          <div className="flex justify-between text-sm text-gray-500">
            <span>Workflow: {workflow.name}</span>
            <span>{jobs.length} jobs</span>
          </div>
        </div>
      )}
    </div>
  );
};
