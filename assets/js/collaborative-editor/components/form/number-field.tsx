import { FormField, INPUT_CLASSES } from './form-field';

import { useFieldContext } from '.';

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
    const value = e.target.valueAsNumber;
    if (isNaN(value)) {
      // Empty input or invalid → null
      field.handleChange(null);
    } else {
      field.handleChange(value);
    }
  };

  return (
    <FormField
      name={field.name}
      label={label}
      meta={field.state.meta}
      helpText={helpText}
    >
      <input
        type="number"
        id={field.name}
        value={field.state.value === null ? '' : field.state.value}
        onChange={handleChange}
        placeholder={placeholder}
        disabled={disabled}
        min={min}
        max={max}
        className={INPUT_CLASSES}
      />
    </FormField>
  );
}
