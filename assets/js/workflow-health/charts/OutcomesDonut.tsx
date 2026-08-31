import {
  Cell,
  Label,
  Pie,
  PieChart,
  ResponsiveContainer,
  Tooltip,
} from 'recharts';

/**
 * Completed work order outcomes as a donut, with the total in the middle.
 *
 * Takes counts rather than the `Stats` payload, so it renders in a test or on
 * another page without a channel. Pending is not a slice: work still in flight
 * has no outcome yet.
 */

// Status colors, not a categorical palette — these are states.
const SLICES = [
  { key: 'success', label: 'Success', color: '#0ca30c' },
  { key: 'failed', label: 'Failed', color: '#d03b3b' },
] as const;

interface OutcomesDonutProps {
  counts: { success: number; failed: number };
  emptyMessage: string;
}

export const OutcomesDonut = ({ counts, emptyMessage }: OutcomesDonutProps) => {
  // Derived here rather than passed in, so the centre total can never disagree
  // with the slices — the chart excludes pending, the page header doesn't.
  const total = counts.success + counts.failed;

  // A pie of zeroes renders as an empty box in Recharts, which reads as
  // broken rather than empty.
  if (total === 0) {
    return <p className="text-sm text-gray-500">{emptyMessage}</p>;
  }

  const data = SLICES.map(({ key, label }) => ({
    name: label,
    value: counts[key],
  }));

  return (
    <>
      <ResponsiveContainer width="100%" height={220}>
        <PieChart>
          <Tooltip
            formatter={(value, name) => [
              `${Number(value).toLocaleString()} (${
                Math.round((Number(value) / total) * 1000) / 10
              }%)`,
              name,
            ]}
          />
          <Pie
            data={data}
            dataKey="value"
            nameKey="name"
            innerRadius={60}
            outerRadius={80}
            stroke="#fff"
            strokeWidth={2}
          >
            {SLICES.map(({ key, color }) => (
              <Cell key={key} fill={color} />
            ))}
            <Label
              value={total.toLocaleString()}
              position="center"
              className="fill-gray-900 text-2xl font-semibold"
            />
          </Pie>
        </PieChart>
      </ResponsiveContainer>

      {/* A status color never carries meaning alone, so the legend is always on. */}
      <ul className="mt-2 flex flex-wrap gap-x-6 gap-y-1 text-sm text-gray-700">
        {SLICES.map(({ key, label, color }) => (
          <li key={key} className="flex items-center gap-2">
            <span
              aria-hidden="true"
              className="h-2.5 w-2.5 rounded-full"
              style={{ backgroundColor: color }}
            />
            {label} {counts[key].toLocaleString()}
          </li>
        ))}
      </ul>
    </>
  );
};
