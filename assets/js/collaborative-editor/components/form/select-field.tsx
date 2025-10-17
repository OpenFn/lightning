import { useMemo } from "react";

import { ErrorMessage } from "./error-message";

import { useFieldContext } from ".";

interface SelectOption {
  value: string;
  label: string;
  group?: string;
}

export function SelectField({
  label,
  options,
  placeholder,
  disabled = false,
}: {
  label: string;
  options: SelectOption[];
  placeholder?: string;
  disabled?: boolean;
}) {
  const groups = useMemo(() => {
    return options.reduce<Record<string, SelectOption[]>>((acc, option) => {
      if (option.group) {
        acc[option.group] = [...(acc[option.group] || []), option];
      } else {
        acc[""] = [...(acc[""] || []), option];
      }
      return acc;
    }, {});
  }, [options]);

  const field = useFieldContext<string>();

  return (
    <div className="mb-4">
      <label
        htmlFor={field.name}
        className="text-sm/6 font-medium text-slate-800 mb-2"
      >
        {label}
      </label>
      <select
        id={field.name}
        disabled={disabled}
        value={field.state.value || ""}
        onChange={e => field.handleChange(e.target.value)}
        className="block w-full rounded-md border-secondary-300 shadow-xs sm:text-sm focus:border-primary-300 focus:ring focus:ring-primary-200/50 disabled:cursor-not-allowed"
      >
        {placeholder && <option value="">{placeholder}</option>}
        {Object.entries(groups).map(([group, options]) =>
          group ? (
            <optgroup key={group} label={group}>
              {options.map(option => (
                <option key={option.value} value={option.value}>
                  {option.label}
                </option>
              ))}
            </optgroup>
          ) : (
            options.map(option => (
              <option key={option.value} value={option.value}>
                {option.label}
              </option>
            ))
          )
        )}
      </select>
      <ErrorMessage meta={field.state.meta} />
    </div>
  );
}
