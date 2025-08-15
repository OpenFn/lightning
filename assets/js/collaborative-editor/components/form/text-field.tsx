import { useFieldContext } from ".";
import { ErrorMessage } from "./error-message";

export function TextField({ label }: { label: string }) {
  const field = useFieldContext<string>();
  return (
    <div>
      <label htmlFor={field.name} className="text-xs text-gray-500 mb-1 block">
        {label}
      </label>
      <input
        type="text"
        id={field.name}
        value={field.state.value}
        onChange={(e) => field.handleChange(e.target.value)}
        className="focus:outline focus:outline-2 focus:outline-offset-1 block w-full rounded-lg text-slate-900 focus:ring-0 sm:text-sm sm:leading-6 phx-no-feedback:border-slate-300 phx-no-feedback:focus:border-slate-400 disabled:cursor-not-allowed disabled:bg-gray-50 disabled:text-gray-500 border-slate-300 focus:border-slate-400 focus:outline-indigo-600"
      />
      <ErrorMessage meta={field.state.meta} />
    </div>
  );
}
