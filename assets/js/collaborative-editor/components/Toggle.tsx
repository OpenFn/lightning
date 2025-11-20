interface ToggleProps {
  id: string;
  checked: boolean;
  onChange: (checked: boolean) => void;
  label: string;
  disabled?: boolean;
}

/**
 * Toggle switch component matching the LiveView toggle style.
 * iOS-style toggle with sliding circle.
 */
export function Toggle({
  id,
  checked,
  onChange,
  label,
  disabled = false,
}: ToggleProps) {
  return (
    <div className="flex items-center gap-3">
      <label className="relative inline-flex items-center cursor-pointer">
        <input
          type="checkbox"
          id={id}
          checked={checked}
          onChange={e => onChange(e.target.checked)}
          disabled={disabled}
          className="sr-only peer"
        />
        <div
          className={`
            relative inline-flex w-11 h-6 rounded-full transition-colors duration-200 ease-in-out border-2 border-transparent
            focus-within:outline-none focus-within:ring-2 focus-within:ring-offset-2 focus-within:ring-indigo-500
            ${checked ? 'bg-indigo-600' : 'bg-slate-200'}
            ${disabled ? 'opacity-50 cursor-not-allowed' : 'cursor-pointer'}
          `}
        >
          <span
            className={`
              pointer-events-none absolute h-5 w-5 inline-block transform rounded-full bg-white shadow ring-0 transition duration-200 ease-in-out
              ${checked ? 'translate-x-5' : 'translate-x-0'}
            `}
          />
        </div>
      </label>
      <label
        htmlFor={id}
        className={`text-sm font-medium ${disabled ? 'text-slate-400' : 'text-slate-700'} ${
          disabled ? 'cursor-not-allowed' : 'cursor-pointer'
        }`}
      >
        {label}
      </label>
    </div>
  );
}
