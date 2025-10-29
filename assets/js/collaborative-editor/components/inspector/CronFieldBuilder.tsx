import { cn } from "../../../utils/cn";
import { useState, useEffect, useMemo } from "react";

interface CronFieldBuilderProps {
  value: string;
  onChange: (cronExpression: string) => void;
  onBlur?: () => void;
  disabled?: boolean;
  className?: string;
}

interface CronData {
  frequency: "hourly" | "daily" | "weekly" | "monthly" | "custom";
  minute: string;
  hour: string;
  weekday: string;
  monthday: string;
}

/**
 * Cron expression builder with visual fields matching the LiveView CronSetupComponent.
 * Provides frequency dropdown with conditional fields for minute/hour/day selection.
 */
export function CronFieldBuilder({
  value,
  onChange,
  onBlur,
  disabled = false,
  className = "",
}: CronFieldBuilderProps) {
  // Parse initial cron expression to determine frequency and field values
  const parseCronExpression = (expr: string): CronData => {
    if (!expr) {
      return {
        frequency: "daily",
        minute: "00",
        hour: "00",
        weekday: "01",
        monthday: "01",
      };
    }

    // Hourly: "30 * * * *" (minute only)
    const hourlyMatch = expr.match(/^(\d{1,2}) \* \* \* \*$/);
    if (hourlyMatch) {
      return {
        frequency: "hourly",
        minute: hourlyMatch[1].padStart(2, "0"),
        hour: "00",
        weekday: "01",
        monthday: "01",
      };
    }

    // Daily: "30 9 * * *" (minute hour)
    const dailyMatch = expr.match(/^(\d{1,2}) (\d{1,2}) \* \* \*$/);
    if (dailyMatch) {
      return {
        frequency: "daily",
        minute: dailyMatch[1].padStart(2, "0"),
        hour: dailyMatch[2].padStart(2, "0"),
        weekday: "01",
        monthday: "01",
      };
    }

    // Weekly: "30 9 * * 1" (minute hour * * weekday)
    const weeklyMatch = expr.match(/^(\d{1,2}) (\d{1,2}) \* \* (\d{1,2})$/);
    if (weeklyMatch) {
      return {
        frequency: "weekly",
        minute: weeklyMatch[1].padStart(2, "0"),
        hour: weeklyMatch[2].padStart(2, "0"),
        weekday: weeklyMatch[3].padStart(2, "0"),
        monthday: "01",
      };
    }

    // Monthly: "30 9 15 * *" (minute hour monthday * *)
    const monthlyMatch = expr.match(/^(\d{1,2}) (\d{1,2}) (\d{1,2}) \* \*$/);
    if (monthlyMatch) {
      return {
        frequency: "monthly",
        minute: monthlyMatch[1].padStart(2, "0"),
        hour: monthlyMatch[2].padStart(2, "0"),
        weekday: "01",
        monthday: monthlyMatch[3].padStart(2, "0"),
      };
    }

    // Custom (doesn't match any pattern)
    return {
      frequency: "custom",
      minute: "00",
      hour: "00",
      weekday: "01",
      monthday: "01",
    };
  };

  const [cronData, setCronData] = useState<CronData>(() =>
    parseCronExpression(value)
  );
  const [showAdvanced, setShowAdvanced] = useState(false);

  // Sync with external value changes - always keep UI in sync
  useEffect(() => {
    setCronData(parseCronExpression(value));
  }, [value]);

  // Build cron expression from current state
  const buildCronExpression = (data: CronData): string => {
    switch (data.frequency) {
      case "hourly":
        return `${data.minute} * * * *`;
      case "daily":
        return `${data.minute} ${data.hour} * * *`;
      case "weekly":
        return `${data.minute} ${data.hour} * * ${data.weekday}`;
      case "monthly":
        return `${data.minute} ${data.hour} ${data.monthday} * *`;
      case "custom":
      default:
        return value; // Keep current value for custom
    }
  };

  // Update a field and rebuild expression
  const updateField = (
    field: keyof CronData,
    fieldValue: string | CronData["frequency"]
  ) => {
    const newData = { ...cronData, [field]: fieldValue };
    setCronData(newData);

    // Only build expression if not custom (custom is manually edited)
    if (field === "frequency" && fieldValue === "custom") {
      // Don't change the expression when switching to custom
      return;
    }

    const newExpression = buildCronExpression(newData);
    onChange(newExpression);
  };

  // Generate options
  const minuteOptions = useMemo(
    () => Array.from({ length: 60 }, (_, i) => i.toString().padStart(2, "0")),
    []
  );

  const hourOptions = useMemo(
    () => Array.from({ length: 24 }, (_, i) => i.toString().padStart(2, "0")),
    []
  );

  const monthdayOptions = useMemo(
    () =>
      Array.from({ length: 31 }, (_, i) => (i + 1).toString().padStart(2, "0")),
    []
  );

  return (
    <div className={cn("space-y-2", className)}>
      <div>
        <label
          htmlFor="cron-frequency"
          className="block text-sm font-medium text-slate-800 mb-1"
        >
          Frequency
        </label>
        <select
          id="cron-frequency"
          value={cronData.frequency}
          onChange={e =>
            updateField("frequency", e.target.value as CronData["frequency"])
          }
          disabled={disabled}
          className="block w-full px-3 py-2 border border-slate-300 rounded-md text-sm focus:border-indigo-500 focus:ring-indigo-500"
        >
          <option value="hourly">Every hour</option>
          <option value="daily">Every day</option>
          <option value="weekly">Every week</option>
          <option value="monthly">Every month</option>
          <option value="custom">Custom</option>
        </select>
      </div>

      {/* Conditional fields based on frequency */}
      {cronData.frequency === "hourly" && (
        <div>
          <label
            htmlFor="cron-minute"
            className="block text-sm font-medium text-slate-800 mb-1"
          >
            Minute
          </label>
          <select
            id="cron-minute"
            value={cronData.minute}
            onChange={e => updateField("minute", e.target.value)}
            disabled={disabled}
            className="block w-full px-3 py-2 border border-slate-300 rounded-md text-sm focus:border-indigo-500 focus:ring-indigo-500"
          >
            {minuteOptions.map(min => (
              <option key={min} value={min}>
                {min}
              </option>
            ))}
          </select>
        </div>
      )}

      {cronData.frequency === "daily" && (
        <div className="grid grid-cols-2 gap-2">
          <div>
            <label
              htmlFor="cron-hour"
              className="block text-sm font-medium text-slate-800 mb-1"
            >
              Hour
            </label>
            <select
              id="cron-hour"
              value={cronData.hour}
              onChange={e => updateField("hour", e.target.value)}
              disabled={disabled}
              className="block w-full px-3 py-2 border border-slate-300 rounded-md text-sm focus:border-indigo-500 focus:ring-indigo-500"
            >
              {hourOptions.map(hr => (
                <option key={hr} value={hr}>
                  {hr}
                </option>
              ))}
            </select>
          </div>
          <div>
            <label
              htmlFor="cron-minute"
              className="block text-sm font-medium text-slate-800 mb-1"
            >
              Minute
            </label>
            <select
              id="cron-minute"
              value={cronData.minute}
              onChange={e => updateField("minute", e.target.value)}
              disabled={disabled}
              className="block w-full px-3 py-2 border border-slate-300 rounded-md text-sm focus:border-indigo-500 focus:ring-indigo-500"
            >
              {minuteOptions.map(min => (
                <option key={min} value={min}>
                  {min}
                </option>
              ))}
            </select>
          </div>
        </div>
      )}

      {cronData.frequency === "weekly" && (
        <div className="grid grid-cols-2 gap-2">
          <div className="col-span-2">
            <label
              htmlFor="cron-weekday"
              className="block text-sm font-medium text-slate-800 mb-1"
            >
              Day
            </label>
            <select
              id="cron-weekday"
              value={cronData.weekday}
              onChange={e => updateField("weekday", e.target.value)}
              disabled={disabled}
              className="block w-full px-3 py-2 border border-slate-300 rounded-md text-sm focus:border-indigo-500 focus:ring-indigo-500"
            >
              <option value="01">Monday</option>
              <option value="02">Tuesday</option>
              <option value="03">Wednesday</option>
              <option value="04">Thursday</option>
              <option value="05">Friday</option>
              <option value="06">Saturday</option>
              <option value="07">Sunday</option>
            </select>
          </div>
          <div>
            <label
              htmlFor="cron-hour"
              className="block text-sm font-medium text-slate-800 mb-1"
            >
              Hour
            </label>
            <select
              id="cron-hour"
              value={cronData.hour}
              onChange={e => updateField("hour", e.target.value)}
              disabled={disabled}
              className="block w-full px-3 py-2 border border-slate-300 rounded-md text-sm focus:border-indigo-500 focus:ring-indigo-500"
            >
              {hourOptions.map(hr => (
                <option key={hr} value={hr}>
                  {hr}
                </option>
              ))}
            </select>
          </div>
          <div>
            <label
              htmlFor="cron-minute"
              className="block text-sm font-medium text-slate-800 mb-1"
            >
              Minute
            </label>
            <select
              id="cron-minute"
              value={cronData.minute}
              onChange={e => updateField("minute", e.target.value)}
              disabled={disabled}
              className="block w-full px-3 py-2 border border-slate-300 rounded-md text-sm focus:border-indigo-500 focus:ring-indigo-500"
            >
              {minuteOptions.map(min => (
                <option key={min} value={min}>
                  {min}
                </option>
              ))}
            </select>
          </div>
        </div>
      )}

      {cronData.frequency === "monthly" && (
        <div className="grid grid-cols-3 gap-2">
          <div>
            <label
              htmlFor="cron-monthday"
              className="block text-sm font-medium text-slate-800 mb-1"
            >
              Day
            </label>
            <select
              id="cron-monthday"
              value={cronData.monthday}
              onChange={e => updateField("monthday", e.target.value)}
              disabled={disabled}
              className="block w-full px-3 py-2 border border-slate-300 rounded-md text-sm focus:border-indigo-500 focus:ring-indigo-500"
            >
              {monthdayOptions.map(day => (
                <option key={day} value={day}>
                  {day}
                </option>
              ))}
            </select>
          </div>
          <div>
            <label
              htmlFor="cron-hour"
              className="block text-sm font-medium text-slate-800 mb-1"
            >
              Hour
            </label>
            <select
              id="cron-hour"
              value={cronData.hour}
              onChange={e => updateField("hour", e.target.value)}
              disabled={disabled}
              className="block w-full px-3 py-2 border border-slate-300 rounded-md text-sm focus:border-indigo-500 focus:ring-indigo-500"
            >
              {hourOptions.map(hr => (
                <option key={hr} value={hr}>
                  {hr}
                </option>
              ))}
            </select>
          </div>
          <div>
            <label
              htmlFor="cron-minute"
              className="block text-sm font-medium text-slate-800 mb-1"
            >
              Minute
            </label>
            <select
              id="cron-minute"
              value={cronData.minute}
              onChange={e => updateField("minute", e.target.value)}
              disabled={disabled}
              className="block w-full px-3 py-2 border border-slate-300 rounded-md text-sm focus:border-indigo-500 focus:ring-indigo-500"
            >
              {minuteOptions.map(min => (
                <option key={min} value={min}>
                  {min}
                </option>
              ))}
            </select>
          </div>
        </div>
      )}

      {/* Advanced section (collapsible) */}
      <div className="pt-2">
        <button
          type="button"
          onClick={() => setShowAdvanced(!showAdvanced)}
          disabled={disabled}
          className="flex items-center gap-1.5 text-xs text-slate-500 hover:text-slate-700 disabled:opacity-50 disabled:cursor-not-allowed"
        >
          <span
            className={`hero-chevron-right h-3 w-3 transition-transform ${
              showAdvanced ? "rotate-90" : ""
            }`}
          />
          {showAdvanced ? "Hide" : "View"} cron expression
        </button>

        {showAdvanced && (
          <div className="mt-2">
            <input
              id="cron-expression"
              type="text"
              value={value}
              onChange={e => {
                onChange(e.target.value);
                // The useEffect will automatically update cronData from the new value
              }}
              onBlur={onBlur}
              disabled={disabled}
              placeholder="0 0 * * *"
              className="block w-full px-3 py-2 border border-slate-300 rounded-md text-sm focus:border-indigo-500 focus:ring-indigo-500 font-mono text-slate-600"
            />
          </div>
        )}
      </div>
    </div>
  );
}
