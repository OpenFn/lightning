/**
 * Chart colours and formatters for the workflow health screen.
 *
 * Every colour is a step from a Tailwind ramp already in Lightning's theme
 * (`assets/css/app.css`), chosen by running the palette validator rather than
 * by eye. The four failure-kind colours pass the lightness band, chroma floor,
 * colour-vision separation and normal-vision floor on a white surface.
 *
 * Two known relief obligations, both satisfied by the markup:
 *   - `failureKind.crashed` sits just under 3:1 contrast, so every donut
 *     segment carries a labelled legend row with its own count.
 *   - Success green against failure red is the classic red/green collapse
 *     under deuteranopia. It is legal here because these are status colours,
 *     not series identity: the donut states its rate as text in the middle and
 *     the legend labels both slices.
 */

export const chart = {
  /** Status: a run either worked or it did not. */
  success: '#16a34a',
  failure: '#dc2626',

  /** Kinds of failure. Nominal, not ordered. */
  failureKind: {
    failed: '#dc2626',
    crashed: '#ca8a04',
    killed: '#8b5cf6',
    lost: '#0891b2',
    cancelled: '#64748b',
    exception: '#be123c',
  } as Record<string, string>,

  /** Volume over time: total runs, with the failed portion stacked on top. */
  runs: '#818cf8',
  runsFailed: '#ef4444',

  /** Single-series magnitude. */
  duration: '#6366f1',
  stepFailures: '#ef4444',

  /** Chrome. */
  grid: '#e5e7eb',
  axis: '#9ca3af',
  track: '#f1f5f9',
} as const;

/** Any state without its own colour falls back to the neutral slate. */
const UNKNOWN_FAILURE_KIND = '#64748b';

export const failureKindColor = (state: string): string =>
  chart.failureKind[state] ?? UNKNOWN_FAILURE_KIND;

/**
 * Shared Recharts tooltip configuration.
 *
 * The formatter takes `unknown` because Recharts types the value as a union of
 * everything a data key might hold; narrowing here keeps the call sites clean.
 */
export const tooltipStyle = {
  borderRadius: 6,
  border: '1px solid #e5e7eb',
  fontSize: 12,
  padding: '6px 10px',
} as const;

export const tooltipFormatter = (
  value: unknown,
  name: unknown
): [string, string] => [formatCount(Number(value)), String(name)];

/**
 * Shared chrome for the two bar charts, so a styling change lands in one
 * place. Spread these onto the Recharts elements.
 */
export const barChart = {
  margin: { top: 4, right: 4, bottom: 0, left: -8 },

  grid: { stroke: chart.grid, vertical: false } as const,

  xAxis: {
    tick: { fontSize: 10, fill: chart.axis },
    tickLine: false,
    axisLine: { stroke: chart.grid },
  } as const,

  yAxis: {
    tick: { fontSize: 10, fill: chart.axis },
    tickLine: false,
    axisLine: false,
    width: 40,
  } as const,

  tooltip: {
    cursor: { fill: 'rgba(0,0,0,0.04)' },
    formatter: tooltipFormatter,
    contentStyle: tooltipStyle,
  } as const,

  bar: { radius: [2, 2, 0, 0] as [number, number, number, number] },
} as const;

/** Blame styling for the triage table, keyed to the same status vocabulary. */
export const blameStyles: Record<string, string> = {
  user: 'text-amber-700',
  remote: 'text-cyan-700',
  limit: 'text-violet-700',
  platform: 'text-rose-700',
};

export const formatCount = (value: number): string =>
  value.toLocaleString('en-US');

/**
 * Durations read as people say them — "1m 48s", not "108.40s".
 */
export const formatDuration = (seconds: number | null): string => {
  if (seconds == null) return '—';
  if (seconds < 1) return `${Math.round(seconds * 1000)}ms`;
  if (seconds < 60) return `${seconds.toFixed(1)}s`;

  const minutes = Math.floor(seconds / 60);
  const rest = Math.round(seconds % 60);

  return rest === 0 ? `${minutes}m` : `${minutes}m ${rest}s`;
};

/**
 * Bucket labels show the time of day for short windows, where the date would
 * be the same on every tick, and switch to the date once buckets span a day
 * or more.
 */
export const formatBucketTime = (
  iso: string,
  bucketSeconds: number
): string => {
  const date = new Date(iso);

  if (bucketSeconds >= 86_400) {
    return date.toLocaleDateString('en-US', { month: 'short', day: 'numeric' });
  }

  return date.toLocaleTimeString('en-US', {
    hour: '2-digit',
    minute: '2-digit',
    hour12: false,
  });
};
