import { ErrorMessage } from './error-message';

import { useFieldContext } from '.';

interface ToggleFieldProps {
  label: string;
  description?: string;
  disabled?: boolean;
}

/**
 * ToggleField - Boolean toggle switch for TanStack Forms
 *
 * Usage:
 * <form.AppField name="enable_job_logs">
 *   {field => (
 *     <field.ToggleField
 *       label="Allow console.log() usage"
 *       description="Control what's printed in run logs"
 *     />
 *   )}
 * </form.AppField>
 */
export function ToggleField({
  label,
  description,
  disabled = false,
}: ToggleFieldProps) {
  const field = useFieldContext<boolean>();
  const isChecked = field.state.value;

  return (
    <div>
      <div className="flex items-start justify-between">
        <div className="flex-1">
          <label
            htmlFor={field.name}
            className="text-sm font-medium text-gray-900 block mb-1"
          >
            {label}
          </label>
          {description && (
            <p className="text-sm text-gray-600 mb-3">{description}</p>
          )}
        </div>
        <div className="relative">
          <input
            type="checkbox"
            id={field.name}
            checked={isChecked}
            disabled={disabled}
            onChange={e => field.handleChange(e.target.checked)}
            className="sr-only"
          />
          <div
            onClick={() => !disabled && field.handleChange(!isChecked)}
            className={`w-11 h-6 rounded-full relative
              transition-colors cursor-pointer ${
                isChecked ? 'bg-indigo-600' : 'bg-gray-300'
              } ${disabled ? 'opacity-50 cursor-not-allowed' : ''}`}
          >
            <div
              className={`absolute top-1 w-4 h-4 bg-white rounded-full
                transition-all ${
                  isChecked ? 'right-1' : 'left-1'
                } flex items-center justify-center`}
            >
              {isChecked && (
                <div className="hero-check w-3 h-3 text-indigo-600" />
              )}
            </div>
          </div>
        </div>
      </div>
      <ErrorMessage meta={field.state.meta} />
    </div>
  );
}
