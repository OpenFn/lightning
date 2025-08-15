import { useFieldContext } from ".";
import { ErrorMessage } from "./error-message";

interface SelectOption {
  value: string;
  label: string;
}

export function SelectField({
  label,
  options,
  placeholder,
}: {
  label: string;
  options: SelectOption[];
  placeholder?: string;
}) {
  const field = useFieldContext<string>();
  return (
    <div>
      <label
        htmlFor={field.name}
        className="text-sm/6 font-medium text-slate-800 mb-2"
      >
        {label}
      </label>
      <select
        id={field.name}
        value={field.state.value}
        onChange={(e) => field.handleChange(e.target.value)}
        className="block w-full rounded-md border-secondary-300 shadow-xs sm:text-sm focus:border-primary-300 focus:ring focus:ring-primary-200/50 disabled:cursor-not-allowed"
      >
        {placeholder && <option value="">{placeholder}</option>}
        {options.map((option) => (
          <option key={option.value} value={option.value}>
            {option.label}
          </option>
        ))}
      </select>
      <ErrorMessage meta={field.state.meta} />
    </div>
  );
}
