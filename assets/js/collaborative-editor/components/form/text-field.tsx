import { FormField, INPUT_CLASSES } from "./form-field";

import { useFieldContext } from ".";

export function TextField({ label }: { label: string }) {
  const field = useFieldContext<string>();
  return (
    <FormField name={field.name} label={label} meta={field.state.meta}>
      <input
        type="text"
        id={field.name}
        value={field.state.value || ""}
        onChange={e => field.handleChange(e.target.value)}
        className={INPUT_CLASSES}
      />
    </FormField>
  );
}
