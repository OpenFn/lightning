import { FormField, INPUT_CLASSES } from './form-field';

import { useFieldContext } from '.';

export function TextAreaField({
  label,
  disabled = false,
  placeholder,
  rows = 4,
}: {
  label: string;
  disabled?: boolean;
  placeholder?: string;
  rows?: number;
}) {
  const field = useFieldContext<string>();
  return (
    <FormField name={field.name} label={label} meta={field.state.meta}>
      <textarea
        id={field.name}
        value={field.state.value || ''}
        onChange={e => field.handleChange(e.target.value)}
        disabled={disabled}
        placeholder={placeholder}
        rows={rows}
        className={INPUT_CLASSES}
      />
    </FormField>
  );
}
