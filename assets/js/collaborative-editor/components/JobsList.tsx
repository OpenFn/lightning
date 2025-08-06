/**
 * JobsList - List of jobs with selection capabilities
 */

import React from 'react';
import { useWorkflowStore } from '../contexts/WorkflowStoreProvider';
import { JobItem } from './JobItem';

export const JobsList: React.FC = () => {
  const { jobs, selectedJobId, selectJob } = useWorkflowStore();

  const clearSelection = () => {
    selectJob(null);
  };

  return (
    <div className="mb-6">
      <div className="flex items-center justify-between mb-4">
        <h3 className="text-lg font-semibold text-gray-900">
          Jobs ({jobs.length})
        </h3>
        {selectedJobId && (
          <button
            onClick={clearSelection}
            className="text-sm text-blue-600 hover:text-blue-800 underline"
          >
            Clear Selection
          </button>
        )}
      </div>

      {selectedJobId && (
        <div className="mb-4 p-3 bg-blue-50 border border-blue-200 rounded-lg">
          <div className="flex items-center text-sm">
            <svg
              className="w-4 h-4 text-blue-500 mr-2"
              fill="currentColor"
              viewBox="0 0 20 20"
            >
              <path
                fillRule="evenodd"
                d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7-4a1 1 0 11-2 0 1 1 0 012 0zM9 9a1 1 0 000 2v3a1 1 0 001 1h1a1 1 0 100-2v-3a1 1 0 00-1-1H9z"
                clipRule="evenodd"
              />
            </svg>
            <span className="text-blue-700">
              Selected job: <strong>{selectedJobId}</strong>
            </span>
          </div>
        </div>
      )}

      {jobs.length === 0 ? (
        <div className="text-center py-12 text-gray-500">
          <svg
            className="w-12 h-12 mx-auto mb-3 text-gray-300"
            fill="none"
            stroke="currentColor"
            viewBox="0 0 24 24"
          >
            <path
              strokeLinecap="round"
              strokeLinejoin="round"
              strokeWidth={2}
              d="M19 11H5m14 0a2 2 0 012 2v6a2 2 0 01-2 2H5a2 2 0 01-2-2v-6a2 2 0 012-2m14 0V9a2 2 0 00-2-2M5 9a2 2 0 012-2m0 0V5a2 2 0 012-2h6a2 2 0 012 2v2M7 7h10"
            />
          </svg>
          <p>No jobs in this workflow yet.</p>
          <p className="text-sm mt-1">
            Jobs will appear here when they are added to the workflow.
          </p>
        </div>
      ) : (
        <div className="space-y-3">
          {jobs.map((job, index) => (
            <JobItem key={job.id} job={job} index={index} />
          ))}
        </div>
      )}
    </div>
  );
};
