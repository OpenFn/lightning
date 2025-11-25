import { useState, useEffect, useMemo } from 'react';

import { cn } from '../../../utils/cn';

interface CronFieldBuilderProps {
  value: string;
  onChange: (cronExpression: string) => void;
  onBlur?: () => void;
  disabled?: boolean;
  className?: string;
}

interface CronData {
  frequency:
    | 'every_n_minutes'
    | 'every_n_hours'
    | 'hourly'
    | 'daily'
    | 'weekly'
    | 'weekdays'
    | 'monthly'
    | 'specific_months'
    | 'custom';
  minute: string;
  hour: string;
  weekday: string | string[]; // Support multiple weekdays
  monthday: string;
  months?: string[]; // For specific months
  interval?: string; // For "every N minutes/hours"
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
  className = '',
}: CronFieldBuilderProps) {
  // Parse initial cron expression to determine frequency and field values
  const parseCronExpression = (expr: string): CronData => {
    if (!expr) {
      return {
        frequency: 'daily',
        minute: '00',
        hour: '00',
        weekday: '01',
        monthday: '01',
      };
    }

    // Every N minutes: "*/15 * * * *"
    const everyNMinutesMatch = expr.match(/^\*\/(\d+) \* \* \* \*$/);
    if (everyNMinutesMatch) {
      return {
        frequency: 'every_n_minutes',
        minute: '00',
        hour: '00',
        weekday: '01',
        monthday: '01',
        interval: everyNMinutesMatch[1],
      };
    }

    // Every N hours: "0 */6 * * *"
    const everyNHoursMatch = expr.match(/^0 \*\/(\d+) \* \* \*$/);
    if (everyNHoursMatch) {
      return {
        frequency: 'every_n_hours',
        minute: '00',
        hour: '00',
        weekday: '01',
        monthday: '01',
        interval: everyNHoursMatch[1],
      };
    }

    // Weekdays: "30 9 * * 1-5" (Monday-Friday)
    const weekdaysMatch = expr.match(/^(\d{1,2}) (\d{1,2}) \* \* 1-5$/);
    if (weekdaysMatch) {
      return {
        frequency: 'weekdays',
        minute: weekdaysMatch[1].padStart(2, '0'),
        hour: weekdaysMatch[2].padStart(2, '0'),
        weekday: '1-5',
        monthday: '01',
      };
    }

    // Hourly: "30 * * * *" (minute only)
    const hourlyMatch = expr.match(/^(\d{1,2}) \* \* \* \*$/);
    if (hourlyMatch) {
      return {
        frequency: 'hourly',
        minute: hourlyMatch[1].padStart(2, '0'),
        hour: '00',
        weekday: '01',
        monthday: '01',
      };
    }

    // Daily: "30 9 * * *" (minute hour)
    const dailyMatch = expr.match(/^(\d{1,2}) (\d{1,2}) \* \* \*$/);
    if (dailyMatch) {
      return {
        frequency: 'daily',
        minute: dailyMatch[1].padStart(2, '0'),
        hour: dailyMatch[2].padStart(2, '0'),
        weekday: '01',
        monthday: '01',
      };
    }

    // Weekly with multiple days: "30 9 * * 1,3,5" (Mon, Wed, Fri)
    const multiWeeklyMatch = expr.match(/^(\d{1,2}) (\d{1,2}) \* \* ([\d,]+)$/);
    if (multiWeeklyMatch) {
      return {
        frequency: 'weekly',
        minute: multiWeeklyMatch[1].padStart(2, '0'),
        hour: multiWeeklyMatch[2].padStart(2, '0'),
        weekday: multiWeeklyMatch[3].split(','),
        monthday: '01',
      };
    }

    // Weekly: "30 9 * * 1" (minute hour * * weekday)
    const weeklyMatch = expr.match(/^(\d{1,2}) (\d{1,2}) \* \* (\d{1,2})$/);
    if (weeklyMatch) {
      return {
        frequency: 'weekly',
        minute: weeklyMatch[1].padStart(2, '0'),
        hour: weeklyMatch[2].padStart(2, '0'),
        weekday: weeklyMatch[3].padStart(2, '0'),
        monthday: '01',
      };
    }

    // Specific months: "30 9 15 1,6 *" (Jan 15 and Jun 15)
    const specificMonthsMatch = expr.match(
      /^(\d{1,2}) (\d{1,2}) (\d{1,2}) (\d+(?:-\d+)?(?:,\d+(?:-\d+)?)*) \*$/
    );

    if (specificMonthsMatch) {
      return {
        frequency: 'specific_months',
        minute: specificMonthsMatch[1].padStart(2, '0'),
        hour: specificMonthsMatch[2].padStart(2, '0'),
        weekday: '01',
        monthday: specificMonthsMatch[3].padStart(2, '0'),
        months: specificMonthsMatch[4]
          .split(',')
          .map(v => {
            const out = [];
            if (Number.isFinite(Number(v))) out.push(v);
            else if (v.indexOf('-') > -1) {
              const [from, to] = v.split('-').map(Number);
              for (let i = from; i <= to; i++) out.push(i);
            }
            return out;
          })
          .flat()
          .map(String),
      };
    }

    // Monthly: "30 9 15 * *" (minute hour monthday * *)
    const monthlyMatch = expr.match(/^(\d{1,2}) (\d{1,2}) (\d{1,2}) \* \*$/);
    if (monthlyMatch) {
      return {
        frequency: 'monthly',
        minute: monthlyMatch[1].padStart(2, '0'),
        hour: monthlyMatch[2].padStart(2, '0'),
        weekday: '01',
        monthday: monthlyMatch[3].padStart(2, '0'),
      };
    }

    // Custom (doesn't match any pattern)
    return {
      frequency: 'custom',
      minute: '00',
      hour: '00',
      weekday: '01',
      monthday: '01',
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
      case 'every_n_minutes':
        return `*/${data.interval || '15'} * * * *`;
      case 'every_n_hours':
        return `0 */${data.interval || '6'} * * *`;
      case 'hourly':
        return `${data.minute} * * * *`;
      case 'daily':
        return `${data.minute} ${data.hour} * * *`;
      case 'weekdays':
        return `${data.minute} ${data.hour} * * 1-5`;
      case 'weekly': {
        const days = Array.isArray(data.weekday)
          ? data.weekday.join(',')
          : Number.isFinite(Number(data.weekday))
            ? data.weekday
            : '01';
        return `${data.minute} ${data.hour} * * ${days}`;
      }
      case 'monthly':
        return `${data.minute} ${data.hour} ${data.monthday} * *`;
      case 'specific_months': {
        const months = data.months?.join(',') || '1';
        return `${data.minute} ${data.hour} ${data.monthday} ${months} *`;
      }
      case 'custom':
      default:
        return value; // Keep current value for custom
    }
  };

  // Update a field and rebuild expression
  const updateField = (
    field: keyof CronData,
    fieldValue: string | string[] | CronData['frequency']
  ) => {
    const newData = { ...cronData, [field]: fieldValue };
    setCronData(newData);

    // Only build expression if not custom (custom is manually edited)
    if (field === 'frequency' && fieldValue === 'custom') {
      // Don't change the expression when switching to custom
      return;
    }

    const newExpression = buildCronExpression(newData);
    onChange(newExpression);
  };

  // Generate options
  const minuteOptions = useMemo(
    () => Array.from({ length: 60 }, (_, i) => i.toString().padStart(2, '0')),
    []
  );

  const hourOptions = useMemo(
    () => Array.from({ length: 24 }, (_, i) => i.toString().padStart(2, '0')),
    []
  );

  const monthdayOptions = useMemo(
    () =>
      Array.from({ length: 31 }, (_, i) => (i + 1).toString().padStart(2, '0')),
    []
  );

  // Base select styling with disabled states
  const selectClassName =
    'block w-full px-3 py-2 border border-slate-300 rounded-md text-sm focus:border-indigo-500 focus:ring-indigo-500 disabled:opacity-50 disabled:cursor-not-allowed disabled:bg-gray-50';

  return (
    <div className={cn('space-y-2', className)}>
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
            updateField('frequency', e.target.value as CronData['frequency'])
          }
          disabled={disabled}
          className={selectClassName}
        >
          <option value="every_n_minutes">Every N minutes</option>
          <option value="every_n_hours">Every N hours</option>
          <option value="hourly">Every hour</option>
          <option value="daily">Every day</option>
          <option value="weekdays">Every weekday (Mon-Fri)</option>
          <option value="weekly">Every week</option>
          <option value="monthly">Every month</option>
          <option value="specific_months">Specific months</option>
          <option value="custom">Custom</option>
        </select>
      </div>

      {/* Conditional fields based on frequency */}
      {cronData.frequency === 'every_n_minutes' && (
        <div>
          <label
            htmlFor="cron-interval-minutes"
            className="block text-sm font-medium text-slate-800 mb-1"
          >
            Every
          </label>
          <select
            id="cron-interval-minutes"
            value={cronData.interval || '15'}
            onChange={e => updateField('interval', e.target.value)}
            disabled={disabled}
            className={selectClassName}
          >
            {cronData.interval &&
            [5, 10, 15, 20, 30].includes(parseInt(cronData.interval)) ? null : (
              <option value={cronData.interval}>
                {cronData.interval} minute
                {cronData.interval && parseInt(cronData.interval) !== 1
                  ? 's'
                  : ''}
              </option>
            )}
            <option value="5">5 minutes</option>
            <option value="10">10 minutes</option>
            <option value="15">15 minutes</option>
            <option value="20">20 minutes</option>
            <option value="30">30 minutes</option>
          </select>
        </div>
      )}

      {cronData.frequency === 'every_n_hours' && (
        <div>
          <label
            htmlFor="cron-interval-hours"
            className="block text-sm font-medium text-slate-800 mb-1"
          >
            Every
          </label>
          <select
            id="cron-interval-hours"
            value={cronData.interval || '6'}
            onChange={e => updateField('interval', e.target.value)}
            disabled={disabled}
            className={selectClassName}
          >
            {cronData.interval &&
            [2, 3, 4, 6, 8, 12].includes(parseInt(cronData.interval)) ? null : (
              <option value={cronData.interval}>
                {cronData.interval} hour
                {cronData.interval && parseInt(cronData.interval) !== 1
                  ? 's'
                  : ''}
              </option>
            )}
            <option value="2">2 hours</option>
            <option value="3">3 hours</option>
            <option value="4">4 hours</option>
            <option value="6">6 hours</option>
            <option value="8">8 hours</option>
            <option value="12">12 hours</option>
          </select>
        </div>
      )}

      {cronData.frequency === 'hourly' && (
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
            onChange={e => updateField('minute', e.target.value)}
            disabled={disabled}
            className={selectClassName}
          >
            {minuteOptions.map(min => (
              <option key={min} value={min}>
                {min}
              </option>
            ))}
          </select>
        </div>
      )}

      {cronData.frequency === 'daily' && (
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
              onChange={e => updateField('hour', e.target.value)}
              disabled={disabled}
              className={selectClassName}
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
              onChange={e => updateField('minute', e.target.value)}
              disabled={disabled}
              className={selectClassName}
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

      {cronData.frequency === 'weekdays' && (
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
              onChange={e => updateField('hour', e.target.value)}
              disabled={disabled}
              className={selectClassName}
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
              onChange={e => updateField('minute', e.target.value)}
              disabled={disabled}
              className={selectClassName}
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

      {cronData.frequency === 'weekly' && (
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
              onChange={e => updateField('weekday', e.target.value)}
              disabled={disabled}
              className={selectClassName}
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
              onChange={e => updateField('hour', e.target.value)}
              disabled={disabled}
              className={selectClassName}
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
              onChange={e => updateField('minute', e.target.value)}
              disabled={disabled}
              className={selectClassName}
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

      {cronData.frequency === 'monthly' && (
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
              onChange={e => updateField('monthday', e.target.value)}
              disabled={disabled}
              className={selectClassName}
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
              onChange={e => updateField('hour', e.target.value)}
              disabled={disabled}
              className={selectClassName}
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
              onChange={e => updateField('minute', e.target.value)}
              disabled={disabled}
              className={selectClassName}
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

      {cronData.frequency === 'specific_months' && (
        <div className="space-y-4">
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
                onChange={e => updateField('monthday', e.target.value)}
                disabled={disabled}
                className={selectClassName}
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
                onChange={e => updateField('hour', e.target.value)}
                disabled={disabled}
                className={selectClassName}
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
                onChange={e => updateField('minute', e.target.value)}
                disabled={disabled}
                className={selectClassName}
              >
                {minuteOptions.map(min => (
                  <option key={min} value={min}>
                    {min}
                  </option>
                ))}
              </select>
            </div>
          </div>
          <div>
            <label className="block text-sm font-medium text-slate-800 mb-2">
              Months
            </label>
            <div className="grid grid-cols-3 gap-2">
              {[
                { value: '1', label: 'Jan' },
                { value: '2', label: 'Feb' },
                { value: '3', label: 'Mar' },
                { value: '4', label: 'Apr' },
                { value: '5', label: 'May' },
                { value: '6', label: 'Jun' },
                { value: '7', label: 'Jul' },
                { value: '8', label: 'Aug' },
                { value: '9', label: 'Sep' },
                { value: '10', label: 'Oct' },
                { value: '11', label: 'Nov' },
                { value: '12', label: 'Dec' },
              ].map(month => (
                <label
                  key={month.value}
                  className="flex items-center text-sm text-slate-700 cursor-pointer"
                >
                  <input
                    type="checkbox"
                    checked={(cronData.months || []).includes(month.value)}
                    onChange={e => {
                      const months = cronData.months || [];
                      const newMonths = e.target.checked
                        ? [...months, month.value]
                        : months.filter(m => m !== month.value);
                      updateField('months', newMonths);
                    }}
                    disabled={disabled}
                    className="mr-2 h-4 w-4 text-indigo-600 border-slate-300 rounded focus:ring-indigo-500 disabled:opacity-50 disabled:cursor-not-allowed"
                  />
                  {month.label}
                </label>
              ))}
            </div>
          </div>
        </div>
      )}

      {/* Advanced section (collapsible) */}
      <div className="pt-6 border-t border-slate-200">
        <button
          type="button"
          onClick={() => setShowAdvanced(!showAdvanced)}
          disabled={disabled}
          className="flex items-center gap-1 text-xs font-semibold text-slate-700 uppercase tracking-wide hover:text-slate-900 disabled:opacity-50 disabled:cursor-not-allowed"
        >
          <span
            className={`hero-chevron-right h-3 w-3 transition-transform ${
              showAdvanced ? 'rotate-90' : ''
            }`}
          />
          Cron Expression
        </button>

        {showAdvanced && (
          <div className="mt-3">
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
              className="block w-full px-3 py-2 border border-slate-300 rounded-md text-sm focus:border-indigo-500 focus:ring-indigo-500 focus:outline-none focus:ring-1 font-mono text-slate-700 disabled:opacity-50 disabled:cursor-not-allowed disabled:bg-gray-50"
            />
          </div>
        )}
      </div>
    </div>
  );
}
