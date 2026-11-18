import { FormField, INPUT_CLASSES } from './form-field';

import { useFieldContext } from '.';

export function TextField({
  label,
  disabled = false,
  placeholder,
  tourAnchor,
}: {
  label: string;
  disabled?: boolean;
  placeholder?: string;
  /**
   * Rendered as `data-tour-anchor` on the input so the guided tour runner
   * can spotlight it. Anchors must be unique in the DOM, so set it per call
   * site rather than per field type.
   */
  tourAnchor?: string;
}) {
  const field = useFieldContext<string>();
  return (
    <FormField name={field.name} label={label} meta={field.state.meta}>
      <input
        type="text"
        id={field.name}
        value={field.state.value || ''}
        onChange={e => field.handleChange(e.target.value)}
        disabled={disabled}
        placeholder={placeholder}
        autoComplete="off"
        data-tour-anchor={tourAnchor}
        className={INPUT_CLASSES}
      />
    </FormField>
  );
}
