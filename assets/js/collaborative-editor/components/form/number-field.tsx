import { ErrorMessage } from "./error-message";
import { useFieldContext } from ".";

interface NumberFieldProps {
  label: string;
  placeholder?: string;
  disabled?: boolean;
  min?: number;
  max?: number;
  helpText?: string;
}

/**
 * NumberField - Integer input field for TanStack Forms
 *
 * Handles nullable number fields properly:
 * - Empty string converts to null
 * - Shows placeholder when null
 * - Validates min/max when value present
 *
 * Usage:
 * <form.AppField name="concurrency">
 *   {field => (
 *     <field.NumberField
 *       label="Max Concurrency"
 *       placeholder="Unlimited"
 *       helpText="Maximum concurrent runs"
 *       min={1}
 *     />
 *   )}
 * </form.AppField>
 */
export function NumberField({
  label,
  placeholder,
  disabled = false,
  min,
  max,
  helpText,
}: NumberFieldProps) {
  const field = useFieldContext<number | null>();

  const handleChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const value = e.target.value;
    if (value === "") {
      field.handleChange(null);
    } else {
      const numValue = parseInt(value, 10);
      if (!isNaN(numValue)) {
        field.handleChange(numValue);
      }
    }
  };

  return (
    <div>
      <label
        htmlFor={field.name}
        className="text-sm/6 font-medium text-slate-800 mb-2
          flex items-center gap-2"
      >
        {label}
      </label>
      <input
        type="text"
        inputMode="numeric"
        pattern="[0-9]*"
        id={field.name}
        value={field.state.value === null ? "" : field.state.value}
        onChange={handleChange}
        placeholder={placeholder}
        disabled={disabled}
        min={min}
        max={max}
        className="focus:outline focus:outline-2 focus:outline-offset-1
          block w-full rounded-lg text-slate-900 focus:ring-0 sm:text-sm
          sm:leading-6 phx-no-feedback:border-slate-300
          phx-no-feedback:focus:border-slate-400 disabled:cursor-not-allowed
          disabled:bg-gray-50 disabled:text-gray-500 border-slate-300
          focus:border-slate-400 focus:outline-indigo-600"
      />
      {helpText && (
        <p className="text-xs text-gray-500 mt-1 italic">{helpText}</p>
      )}
      <ErrorMessage meta={field.state.meta} />
    </div>
  );
}
