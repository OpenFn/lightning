import { createFormHook, createFormHookContexts } from "@tanstack/react-form";
import { TextField } from "./text-field";

export const { fieldContext, formContext, useFieldContext } =
  createFormHookContexts();

export const { useAppForm } = createFormHook({
  fieldContext,
  formContext,
  fieldComponents: {
    TextField,
  },
  formComponents: {},
});
