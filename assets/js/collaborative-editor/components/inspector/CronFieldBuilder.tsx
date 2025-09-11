interface CronFieldBuilderProps {
  value: string;
  onChange: (cronExpression: string) => void;
  onBlur?: () => void;
  disabled?: boolean;
  className?: string;
}

/**
 * Simple cron expression input field with validation using cron-validator.
 * Provides a text input for entering cron expressions directly.
 */
export function CronFieldBuilder({
  value,
  onChange,
  onBlur,
  disabled = false,
  className = "",
}: CronFieldBuilderProps) {
  return (
    <div className={`space-y-2 ${className}`}>
      <div>
        <label
          htmlFor="cron-expression"
          className="block text-xs font-medium text-gray-700 mb-1"
        >
          Cron Expression
        </label>
        <input
          id="cron-expression"
          type="text"
          value={value}
          onChange={e => onChange(e.target.value)}
          onBlur={onBlur}
          disabled={disabled}
          placeholder="0 0 * * * (daily at midnight)"
          className="block w-full px-3 py-2 border border-gray-300 rounded-md text-sm focus:border-indigo-500 focus:ring-indigo-500 focus:outline-none focus:ring-1"
        />
        <p className="mt-1 text-xs text-gray-500">
          Format: minute hour day month weekday (e.g., "0 9 * * 1-5" for
          weekdays at 9am)
        </p>
      </div>
    </div>
  );
}
