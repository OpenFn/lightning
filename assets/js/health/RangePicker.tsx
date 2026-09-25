import { Radio, RadioGroup } from '@headlessui/react';

import { Tooltip } from '#/components/Tooltip';

// The server validates its own copy of this list — add to both. Its own
// default matches `DEFAULT_DAYS` below too.
export const RANGES = [
  { days: '1', label: 'Last 24 hours' },
  { days: '7', label: 'Last 7 days' },
  { days: '30', label: 'Last 30 days' },
] as const;

export const DEFAULT_DAYS = '7';

interface RangePickerProps {
  days: string;
  onChange: (days: string) => void;
  retentionDays: number | null;
}

// Radio group, not tabs — this picks a value, it doesn't swap panels.
export const RangePicker = ({
  days,
  onChange,
  retentionDays,
}: RangePickerProps) => (
  <RadioGroup
    value={days}
    onChange={onChange}
    aria-label="Time range"
    className="flex gap-1"
  >
    {RANGES.map(range => {
      const disabled =
        retentionDays !== null && Number(range.days) > retentionDays;

      return (
        // A disabled `Radio` drops its event handlers, so the tooltip hangs
        // off a wrapper that still gets the hover.
        <Tooltip
          key={range.days}
          content={
            disabled &&
            `Only ${retentionDays} days of history are kept for this project.`
          }
        >
          <span className="flex">
            <Radio
              value={range.days}
              disabled={disabled}
              className="cursor-pointer rounded-md px-3 py-1.5 text-sm font-medium text-gray-500 data-hover:text-gray-900 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary-600 data-checked:bg-white data-checked:text-primary-700 data-checked:shadow-xs data-checked:inset-ring data-checked:inset-ring-gray-200 data-disabled:cursor-not-allowed data-disabled:text-gray-300"
            >
              {range.label}
            </Radio>
          </span>
        </Tooltip>
      );
    })}
  </RadioGroup>
);
