import {
  Cell,
  Label,
  Pie,
  PieChart,
  ResponsiveContainer,
  Tooltip,
} from 'recharts';

import { cn } from '#/utils/cn';

/**
 * A part-to-whole donut with the total in the middle and an always-on legend.
 *
 * Takes slices rather than any `Stats` payload, so it renders in a test or on
 * another page without a channel. Callers decide what a slice is and what the
 * shares are of — the outcomes panel's denominator is every finished run, the
 * failure panel's is only the failures.
 */

export interface Slice {
  key: string;
  label: string;
  color: string;
  value: number;
}

interface DonutProps {
  slices: Slice[];
  emptyMessage: string;
}

// The chart's box, drawn whether or not there is a chart to put in it, so an
// empty window is as tall as a full one and the page holds still on a range
// switch. Only the legend below it follows the data.
export const FRAME = 'h-55';

export const Donut = ({ slices, emptyMessage }: DonutProps) => {
  const total = slices.reduce((sum, { value }) => sum + value, 0);

  // A pie of zeroes renders as an empty box in Recharts, which reads as
  // broken rather than empty.
  if (total === 0) {
    return (
      <p
        className={cn(
          FRAME,
          'flex items-center justify-center text-sm text-gray-500'
        )}
      >
        {emptyMessage}
      </p>
    );
  }

  const share = (value: number) => `${((value / total) * 100).toFixed(1)}%`;

  return (
    <>
      <div className={FRAME} aria-hidden="true">
        <ResponsiveContainer width="100%" height={220}>
          <PieChart accessibilityLayer={false}>
            <Tooltip
              formatter={(value, name) => [
                `${Number(value).toLocaleString()} (${share(Number(value))})`,
                name,
              ]}
            />
            {/* `accessibilityLayer` only governs the svg; the pie's own root
                group is a tab stop by default (`rootTabIndex` 0), and
                `aria-hidden` on the frame doesn't take it out of the order. */}
            <Pie
              rootTabIndex={-1}
              data={slices.map(({ label, value }) => ({ name: label, value }))}
              dataKey="value"
              nameKey="name"
              innerRadius={60}
              outerRadius={80}
              stroke="#fff"
              strokeWidth={2}
            >
              {slices.map(({ key, color }) => (
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
      </div>

      {/* Neither palette identifies a slice by hue alone — the outcomes pair
          sits 4.1 CVD ΔE apart and the failure palette's tightest pair 6.1, in
          the band that is legal only with secondary encoding. The labels and
          counts here are that encoding, so the legend is never optional. The
          chart above is hidden from assistive tech; this legend is its
          accessible representation. */}
      <ul className="mt-2 flex flex-col gap-1 text-sm text-gray-700">
        {slices.map(({ key, label, color, value }) => (
          <li key={key} className="flex items-center gap-2">
            <span
              aria-hidden="true"
              className="h-2.5 w-2.5 shrink-0 rounded-full"
              style={{ backgroundColor: color }}
            />
            <span className="grow">{label}</span>
            <span className="tabular-nums">{value.toLocaleString()}</span>
            <span className="w-12 text-right tabular-nums text-gray-500">
              {share(value)}
            </span>
          </li>
        ))}
      </ul>
    </>
  );
};
