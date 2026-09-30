import {
  Bar,
  BarChart,
  CartesianGrid,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from 'recharts';

import { historyUrl } from '../historyUrl';
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
 * zero-filled from `Stats.runs/3` — one row per bar, one key per run state,
 * which is the shape Recharts takes as `data` — on a grid cut to the reader's
 * calendar, so every label here follows `timezone` rather than the browser.
 */

// A run has no `rejected` state — a work order rejected on arrival never
// produced one. Narrowed off the donut's list so a state added there reaches
// both.
type RunFailureState = Exclude<FailureState, 'rejected'>;

export const RUN_FAILURE_STATES = FAILURE_STATES.filter(
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
  /** The clock the server cut the grid on. Every label follows it. */
  timezone: string;
  /** Bar width, in wall-clock hours on that clock: 2, 12 or 24. */
  bucket_hours: number;
  buckets: RunBucket[];
}

// Top to bottom, as the legend and the spoken totals read. The bars draw from
// the reverse of it, since Recharts puts the first `Bar` on the axis.
//
// `states` is what the band actually stacked, and is what its history link
// filters on — the red one folds five, and it is the only place those five can
// be named.
const SERIES = [
  { key: 'success', label: 'Success', color: SUCCESS, states: ['success'] },
  {
    key: 'cancelled',
    label: 'Cancelled',
    color: CANCELLED,
    states: ['cancelled'],
  },
  { key: 'failed', label: 'Failed', color: FAILED, states: RUN_FAILURE_STATES },
] as const;

interface VolumeBarsProps {
  buckets: RunBucket[];
  timezone: string;
  hours: number;
  emptyMessage: string;
  projectId: string;
  workflowId: string;
}

export const VolumeBars = ({
  buckets,
  timezone,
  hours,
  emptyMessage,
  projectId,
  workflowId,
}: VolumeBarsProps) => {
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
              tickFormatter={at => tickLabel(at as string, hours, timezone)}
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
                  formatLabel={at => rangeLabel(at, hours, timezone)}
                />
              }
            />
            {/* Reversed, so failures land on the axis and can be read against
                a fixed baseline day to day rather than judged by thickness.

                Each band links to its own states rather than the chart
                carrying one link for the whole column: the red band is the
                answer most readers came for, and a column-wide link would
                make them filter the failures out again on arrival. Clicking
                is a mouse affordance only — the frame is `aria-hidden`, and
                up to a month of bars times three bands is not a link list. */}
            {[...totals]
              .reverse()
              .map(({ key, label: name, color, states }) => (
                <Bar
                  key={key}
                  dataKey={key}
                  name={name}
                  stackId="runs"
                  maxBarSize={64}
                  fill={color}
                  className="cursor-pointer"
                  onClick={(_bar, index) => {
                    const href = bucketUrl(
                      projectId,
                      workflowId,
                      buckets,
                      index,
                      states
                    );
                    if (href) window.open(href, '_blank');
                  }}
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

/**
 * The card's meta line: the bar width this range draws, and the clock it is
 * drawn on.
 *
 * Names the timezone because the grid is cut on the reader's own clock rather
 * than UTC, and a bar labelled `Mar 3` is only unambiguous once the reader
 * knows whose `Mar 3` it is.
 */
export const bucketMeta = ({ timezone, bucket_hours: hours }: RunVolume) =>
  `${hours >= 24 ? 'daily' : `${hours}-hour`} buckets · ${timezone}`;

/**
 * The history link for one band of one bar: the work orders with a run
 * created inside the bar's slot that settled in one of the band's states.
 *
 * Half-open, and the slot's end is the *next* bar's start rather than its own
 * plus a width: no timezone arithmetic happens here, and a bar spanning a
 * clock change is 11 or 13 real hours wide. The newest bar has no upper bound
 * — it is still filling.
 */
export const bucketUrl = (
  projectId: string,
  workflowId: string,
  buckets: RunBucket[],
  index: number,
  states: readonly string[]
) => {
  const bucket = buckets[index];

  if (!bucket) return null;

  return historyUrl(projectId, workflowId, {
    run_date_after: bucket.at,
    run_date_before: buckets[index + 1]?.at,
    run_status: states,
  });
};

const TICK_FILL = '#6b7280';

// In the timezone the server cut the grid on, not the browser's own: a bar
// starts at a local whole hour there, so a Delhi bar opening at UTC 18:30
// labels as 00:00 and no label ever needs minutes.
const dayLabel = (date: Date, timezone: string) =>
  date.toLocaleDateString(undefined, {
    month: 'short',
    day: 'numeric',
    timeZone: timezone,
  });

// `hourCycle` rather than `hour12: false` because it is the explicit way to
// ask for 00-23 and does not depend on the locale's own preference. Every
// boundary is a local whole hour, so no label ever needs minutes.
const localHour = (date: Date, timezone: string) =>
  Number(
    date.toLocaleString('en-GB', {
      hour: '2-digit',
      hourCycle: 'h23',
      timeZone: timezone,
    })
  );

const hourLabel = (hour: number) => `${String(hour).padStart(2, '0')}:00`;

export const tickLabel = (at: string, hours: number, timezone: string) => {
  const date = new Date(at);

  if (hours >= 24) return dayLabel(date, timezone);

  // Two bars to a day at this width, so the date goes on the morning bar,
  // where the day starts, and the afternoon is left blank. A window opening
  // mid-day leaves that first bar unlabelled, which is honest — its morning
  // is outside the window — and keeps every date two bars from the last.
  if (hours >= 12) {
    return localHour(date, timezone) < 12 ? dayLabel(date, timezone) : '';
  }

  return hourLabel(localHour(date, timezone));
};

// The axis is thinned and its labels name only where a bucket starts, so the
// tooltip names the whole slot rather than leaving the reader to add the width
// to the start. No timezone suffix: the card's meta line names it once, and
// repeating it on every hover is noise.
export const rangeLabel = (at: string, hours: number, timezone: string) => {
  const start = new Date(at);

  // A daily bar is a whole local day, and `00:00 – 00:00` invites the question
  // of whether the closing midnight is inside the bar or the next one. It is
  // also the branch that keeps a 25-hour clock-change day honest, by printing
  // no end at all.
  if (hours >= 24) return dayLabel(start, timezone);

  // The end hour is the start's plus the width on the wall clock, not
  // `start + hours` in real time: a bar spanning a clock change is 11 or 13
  // real hours, and only the wall clock closes it where the next bar opens.
  const from = localHour(start, timezone);

  return `${dayLabel(start, timezone)}, ${hourLabel(from)} – ${hourLabel((from + hours) % 24)}`;
};
