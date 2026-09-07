import { Radio, RadioGroup } from '@headlessui/react';

// The server validates its own copy of this list — add to both.
export const RANGES = [
  { days: '1', label: 'Last 24 hours' },
  { days: '7', label: 'Last 7 days' },
  { days: '30', label: 'Last 30 days' },
] as const;

export const DEFAULT_DAYS = '30';

interface RangePickerProps {
  days: string;
  onChange: (days: string) => void;
}

// Radio group, not tabs — this picks a value, it doesn't swap panels.
export const RangePicker = ({ days, onChange }: RangePickerProps) => (
  <RadioGroup
    value={days}
    onChange={onChange}
    aria-label="Time range"
    className="flex gap-1"
  >
    {RANGES.map(range => (
      <Radio
        key={range.days}
        value={range.days}
        className="cursor-pointer rounded-md px-3 py-1.5 text-sm font-medium text-gray-500 hover:text-gray-900 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary-600 data-checked:bg-white data-checked:text-primary-700 data-checked:shadow-xs data-checked:inset-ring data-checked:inset-ring-gray-200"
      >
        {range.label}
      </Radio>
    ))}
  </RadioGroup>
);
