import { createFormHook, createFormHookContexts } from "@tanstack/react-form";

import { NumberField } from "./number-field";
import { SelectField } from "./select-field";
import { TextField } from "./text-field";
import { ToggleField } from "./toggle-field";

export const { fieldContext, formContext, useFieldContext } =
  createFormHookContexts();

export const { useAppForm } = createFormHook({
  fieldContext,
  formContext,
  fieldComponents: {
    TextField,
    SelectField,
    ToggleField,
    NumberField,
  },
  formComponents: {},
});
