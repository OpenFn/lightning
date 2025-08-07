/**
 * JobItem - Individual job display component with selection handling
 */

import React from 'react';
import { useWorkflowStore } from '../contexts/WorkflowStoreProvider';
import type { WorkflowJob } from '../types/workflow';

interface JobItemProps {
  job: WorkflowJob;
  index: number;
}

export const JobItem: React.FC<JobItemProps> = ({ job, index }) => {
  const { selectedJobId, selectJob } = useWorkflowStore();

  const isSelected = selectedJobId === job.id;

  const handleClick = () => {
    selectJob(job.id);
  };

  return (
    <div
      onClick={handleClick}
      className={`
        p-4 rounded-lg border cursor-pointer transition-all duration-200
        ${
          isSelected
            ? 'border-blue-500 bg-blue-50 shadow-md'
            : 'border-gray-200 bg-white hover:border-gray-300 hover:shadow-sm'
        }
      `}
    >
      <div className="flex items-start justify-between">
        <div className="flex-1 min-w-0">
          <h4
            className={`font-medium truncate ${
              isSelected ? 'text-blue-900' : 'text-gray-900'
            }`}
          >
            {job.name || `Job ${index + 1}`}
          </h4>
          <p
            className={`text-sm mt-1 ${
              isSelected ? 'text-blue-600' : 'text-gray-500'
            }`}
          >
            ID: {job.id}
          </p>
          {job.body && (
            <div
              className={`mt-2 text-sm ${
                isSelected ? 'text-blue-700' : 'text-gray-600'
              }`}
            >
              <span className="font-medium">Body: </span>
              <span className="font-mono">
                {job.body.substring(0, 80)}
                {job.body.length > 80 && '...'}
              </span>
            </div>
          )}
        </div>

        {/* Selection indicator */}
        <div
          className={`
          flex-shrink-0 ml-3 w-3 h-3 rounded-full border-2 transition-all duration-200
          ${
            isSelected
              ? 'border-blue-500 bg-blue-500'
              : 'border-gray-300 bg-white'
          }
        `}
        >
          {isSelected && (
            <svg
              className="w-full h-full text-white"
              fill="currentColor"
              viewBox="0 0 20 20"
            >
              <path
                fillRule="evenodd"
                d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z"
                clipRule="evenodd"
              />
            </svg>
          )}
        </div>
      </div>
    </div>
  );
};
