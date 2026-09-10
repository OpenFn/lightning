import {
  Bar,
  BarChart,
  CartesianGrid,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from 'recharts';

import type { FailureState } from '../types';
import { FAILURE_STATES } from '../types';

import { ChartTooltip } from './ChartTooltip';
import { EMPTY } from './Donut';
import { CANCELLED, FAILED, SUCCESS } from './OutcomesDonut';

/**
 * Run volume over the window, stacked by outcome.
 *
 * Counts runs where the donuts beside it count work orders, so the two differ
 * on purpose and the card carries no total. Buckets arrive already counted and
 * zero-filled from `Stats.runs/2` — one row per bar, one key per run state,
 * which is the shape Recharts takes as `data`.
 */

// A run has no `rejected` state — a work order rejected on arrival never
// produced one. Narrowed off the donut's list so a state added there reaches
// both.
type RunFailureState = Exclude<FailureState, 'rejected'>;

const RUN_FAILURE_STATES = FAILURE_STATES.filter(
  (state): state is RunFailureState => state !== 'rejected'
);

/** One bar: when its slot starts, and the run counts that landed in it. */
export interface RunBucket {
  at: string;
  success: number;
  cancelled: number;
  failed: number;
  crashed: number;
  killed: number;
  exception: number;
  lost: number;
}

export interface RunVolume {
  window: { from: string; to: string };
  buckets: RunBucket[];
}

// Top to bottom, as the legend and the spoken totals read. The bars draw from
// the reverse of it, since Recharts puts the first `Bar` on the axis.
const SERIES = [
  { key: 'success', label: 'Success', color: SUCCESS },
  { key: 'cancelled', label: 'Cancelled', color: CANCELLED },
  { key: 'failed', label: 'Failed', color: FAILED },
] as const;

interface VolumeBarsProps {
  buckets: RunBucket[];
  emptyMessage: string;
}

export const VolumeBars = ({ buckets, emptyMessage }: VolumeBarsProps) => {
  const rows = buckets.map(bucket => ({
    at: bucket.at,
    success: bucket.success,
    cancelled: bucket.cancelled,
    failed: RUN_FAILURE_STATES.reduce((sum, state) => sum + bucket[state], 0),
  }));

  // Cancelled is drawn only when it happened — a "Cancelled 0" row on every
  // healthy workflow is noise. Success and Failed stay put at zero.
  const totals = SERIES.map(series => ({
    ...series,
    value: rows.reduce((sum, row) => sum + row[series.key], 0),
  })).filter(({ key, value }) => key !== 'cancelled' || value > 0);

  // Recharts draws a bare axis for an all-zero window, which reads as broken
  // rather than empty.
  if (totals.every(({ value }) => value === 0)) {
    return <p className={EMPTY}>{emptyMessage}</p>;
  }

  const hours = bucketHours(buckets);

  return (
    <>
      {/* The donut's `FRAME` is a fixed box and gains nothing from extra
          room; the bars have a time axis to spread along. `flex-1` takes the
          height the grid row stretches the card to, floored at the donut's
          own height so a short row still lines the two up. */}
      <div className="min-h-55 flex-1" aria-hidden="true">
        <ResponsiveContainer width="100%" height="100%">
          <BarChart
            data={rows}
            accessibilityLayer={false}
            margin={{ top: 4, right: 4, bottom: 0, left: -20 }}
          >
            <CartesianGrid vertical={false} stroke="#f3f4f6" />
            {/* The blank afternoon labels count against the gap rule, so left
                to thin the axis itself Recharts drops named bars too. */}
            <XAxis
              dataKey="at"
              tickFormatter={at => tickLabel(at as string, hours)}
              tickLine={false}
              axisLine={false}
              interval={hours >= 12 && hours < 24 ? 0 : 'preserveEnd'}
              minTickGap={16}
              tick={{ fontSize: 11, fill: TICK_FILL }}
            />
            {/* Recharts ends the axis at the tallest bar, so that bar finishes
                flush against the top gridline and reads as clipped. A tenth of
                headroom puts the ceiling above the data. */}
            <YAxis
              allowDecimals={false}
              domain={[0, (max: number) => Math.ceil(max * 1.1)]}
              tickLine={false}
              axisLine={false}
              width={44}
              tick={{ fontSize: 11, fill: TICK_FILL }}
            />
            {/* Recharts transitions the panel's transform, so it slides
                diagonally across the plot as the pointer moves between bars.
                Its rows arrive in `Bar` declaration order, the reverse of the
                stack, so the panel is flipped back into `SERIES` order. */}
            <Tooltip
              isAnimationActive={false}
              cursor={{ fill: '#f9fafb' }}
              content={
                <ChartTooltip
                  reverse
                  formatLabel={at => rangeLabel(at, hours)}
                />
              }
            />
            {/* Reversed, so failures land on the axis and can be read against
                a fixed baseline day to day rather than judged by thickness. */}
            {[...totals].reverse().map(({ key, label: name, color }) => (
              <Bar
                key={key}
                dataKey={key}
                name={name}
                stackId="runs"
                maxBarSize={64}
                fill={color}
              />
            ))}
          </BarChart>
        </ResponsiveContainer>
      </div>

      {/* The chart is hidden from assistive tech and these totals are its
          accessible representation, named as totals because a sum says nothing
          about when anything happened. Per-bucket would be ninety-odd cells.
          The legend below repeats the labels, so it is hidden there. */}
      <p className="sr-only">
        {`Window totals: ${totals
          .map(({ label: name, value }) => `${name} ${value.toLocaleString()}`)
          .join(', ')}.`}
      </p>

      {/* A key, no counts — those are on the y-axis and in the tooltip. It
          stays a key because cancelled is a thin grey band between the green
          and the red, and nothing about that stripe says what it is. */}
      <ul
        aria-hidden="true"
        className="mt-2 flex flex-wrap justify-center gap-x-6 gap-y-1 text-sm text-gray-700"
      >
        {totals.map(({ key, label: name, color }) => (
          <li key={key} className="flex items-center gap-2">
            <span
              className="h-2.5 w-2.5 shrink-0 rounded-full"
              style={{ backgroundColor: color }}
            />
            <span>{name}</span>
          </li>
        ))}
      </ul>
    </>
  );
};

// Read off the data rather than passed in, so nothing naming the bucket width
// can disagree with the bars under it. A window too short to measure reads as
// daily, which only ever costs a coarser label.
const bucketHours = (buckets: RunBucket[]) => {
  const [first, second] = buckets;

  return first && second
    ? (Date.parse(second.at) - Date.parse(first.at)) / 3_600_000
    : 24;
};

/** The card's meta line, measured off the same buckets the chart draws. */
export const bucketMeta = (buckets: RunBucket[]) => {
  const hours = bucketHours(buckets);

  return hours >= 24 ? 'daily buckets' : `${hours}-hour buckets`;
};

const TICK_FILL = '#6b7280';

// Rendered in UTC because that is where the buckets are: the server lays the
// grid on the raw epoch, so a day starts at UTC midnight — 03:00 in Nairobi,
// 05:30 in Delhi. The tooltip says UTC for the same reason.
const dayLabel = (date: Date) =>
  date.toLocaleDateString(undefined, {
    month: 'short',
    day: 'numeric',
    timeZone: 'UTC',
  });

const hourLabel = (date: Date) => `${date.getUTCHours()}:00`;

export const tickLabel = (at: string, hours: number) => {
  const date = new Date(at);

  if (hours >= 24) return dayLabel(date);

  // Two bars to a day at this width, so the date goes on the morning bar,
  // where the day starts, and the afternoon is left blank. A window opening
  // mid-day leaves that first bar unlabelled, which is honest — its morning
  // is outside the window — and keeps every date two bars from the last.
  if (hours >= 12) return date.getUTCHours() < 12 ? dayLabel(date) : '';

  return hourLabel(date);
};

// The axis is thinned and its labels name only where a bucket starts, so the
// tooltip names the whole slot rather than leaving the reader to add the width
// to the start.
export const rangeLabel = (at: string, hours: number) => {
  const start = new Date(at);

  // A daily bar is a whole UTC day, and `00:00 – 00:00` invites the question
  // of whether the closing midnight is inside the bar or the next one.
  if (hours >= 24) return `${dayLabel(start)} UTC`;

  const end = new Date(start.getTime() + hours * 3_600_000);

  return `${dayLabel(start)}, ${hourLabel(start)} – ${hourLabel(end)} UTC`;
};
