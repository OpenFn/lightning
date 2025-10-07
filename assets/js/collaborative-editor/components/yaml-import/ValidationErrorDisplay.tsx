/**
 * ValidationErrorDisplay - Error banner component
 *
 * Displays validation errors in a prominent banner at the top of the panel
 */

import { WorkflowError, formatWorkflowError } from '../../../yaml/workflow-errors';

interface ValidationErrorDisplayProps {
  errors: WorkflowError[];
}

export function ValidationErrorDisplay({ errors }: ValidationErrorDisplayProps) {
  if (errors.length === 0) return null;

  return (
    <div className="bg-red-50 border-l-4 border-red-400 p-4">
      <div className="flex">
        <div className="shrink-0">
          <svg
            className="h-5 w-5 text-red-400"
            viewBox="0 0 20 20"
            fill="currentColor"
            aria-hidden="true"
          >
            <path
              fillRule="evenodd"
              d="M10 18a8 8 0 100-16 8 8 0 000 16zM8.28 7.22a.75.75 0 00-1.06 1.06L8.94 10l-1.72 1.72a.75.75 0 101.06 1.06L10 11.06l1.72 1.72a.75.75 0 101.06-1.06L11.06 10l1.72-1.72a.75.75 0 00-1.06-1.06L10 8.94 8.28 7.22z"
              clipRule="evenodd"
            />
          </svg>
        </div>
        <div className="ml-3 flex-1">
          <h3 className="text-sm font-medium text-red-800">
            Validation Error{errors.length > 1 ? 's' : ''}
          </h3>
          <div className="mt-2 text-sm text-red-700">
            <ul className="list-disc space-y-1 pl-5">
              {errors.map((error, index) => (
                <li key={index}>
                  <span className="font-mono text-xs bg-red-100 px-1 py-0.5 rounded">
                    {error.code}
                  </span>
                  : {formatWorkflowError(error)}
                  {error.details.path && (
                    <span className="block text-xs mt-1 text-red-600">
                      Path: {error.details.path}
                    </span>
                  )}
                </li>
              ))}
            </ul>
          </div>
        </div>
      </div>
    </div>
  );
}
