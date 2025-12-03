/**
 * ValidationErrorDisplay - Error banner component
 *
 * Displays validation errors with shake animations.
 * Uses normal flow positioning - parent is responsible for placement.
 */

import { useState, useEffect } from 'react';

import {
  WorkflowError,
  formatWorkflowError,
} from '../../../yaml/workflow-errors';

interface ValidationErrorDisplayProps {
  errors: WorkflowError[];
  onDismiss?: () => void;
}

export function ValidationErrorDisplay({
  errors,
  onDismiss,
}: ValidationErrorDisplayProps) {
  const [shouldShake, setShouldShake] = useState(false);

  // Trigger shake animation when errors change
  useEffect(() => {
    if (errors.length > 0) {
      setShouldShake(true);
      const timer = setTimeout(() => setShouldShake(false), 800);
      return () => clearTimeout(timer);
    }
    return undefined;
  }, [errors]);

  if (errors.length === 0) return null;

  return (
    <div
      className={`bg-danger-100/80 border border-danger-200 text-danger-800 px-4 py-3 rounded-lg flex items-start gap-3 shadow-sm
        ${shouldShake ? 'error-shake' : ''}
        error-slide-in`}
    >
      <div className="flex-grow">
        <h3 className="text-sm font-semibold text-danger-800 mb-1">
          Validation Error{errors.length > 1 ? 's' : ''}
        </h3>
        {errors.map((error, idx) => (
          <div key={idx} className="text-sm text-danger-800 mb-1">
            <span className="font-mono text-xs bg-danger-200 px-1.5 py-0.5 rounded mr-2">
              {error.code}
            </span>
            {formatWorkflowError(error)}
            {error.details.path && (
              <span className="block text-xs mt-1 text-danger-700">
                Path: {error.details.path}
              </span>
            )}
          </div>
        ))}
      </div>
      {onDismiss && (
        <button
          onClick={onDismiss}
          className="shrink-0 text-danger-800 hover:text-danger-900"
          aria-label="Dismiss"
        >
          <span className="hero-x-mark w-5 h-5" />
        </button>
      )}
    </div>
  );
}
