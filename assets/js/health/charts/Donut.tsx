import { Pie, PieChart, ResponsiveContainer, Tooltip } from 'recharts';

import { ChartTooltip } from './ChartTooltip';

/**
 * A part-to-whole donut with a headline figure in the middle, chosen by the
 * caller, and an always-on legend.
 *
 * Takes slices rather than any `Stats` payload, so it renders in a test or on
 * another page without a fetch. Callers decide what a slice is, what the
 * shares are of — the outcomes panel's denominator is every finished run, the
 * failure panel's is only the failures — and where a slice leads.
 */

export interface Slice {
  key: string;
  label: string;
  color: string;
  value: number;
  /** Where the rows this slice counts can be read. */
  href: string;
}

interface DonutProps {
  slices: Slice[];
  emptyMessage: string;
  /** What the middle of the ring says, given the total of the slices. */
  centre: (total: number) => { value: string; label: string };
}

// The chart's box, drawn whether or not there is a chart to put in it, so an
// empty window is as tall as a full one and the page holds still on a range
// switch. Only the legend below it follows the data.
export const FRAME = 'h-55';

// An empty panel fills the card and centres its one line in it.
export const EMPTY =
  'flex min-h-55 flex-1 items-center justify-center text-center text-sm text-gray-500';

// A share to one decimal place, except where rounding would hide a failure: one
// failed work order in 2,500 would otherwise read 0.0%, and the successes
// beside it 100.0%.
export const percent = (value: number, total: number) => {
  const share = (value / total) * 100;
  if (value > 0 && share < 0.05) return '<0.1%';
  if (value < total && share >= 99.95) return '<100%';
  return `${share.toFixed(1)}%`;
};

export const Donut = ({ slices, emptyMessage, centre }: DonutProps) => {
  const total = slices.reduce((sum, { value }) => sum + value, 0);

  // A pie of zeroes renders as an empty box in Recharts, which reads as
  // broken rather than empty.
  if (total === 0) {
    return <p className={EMPTY}>{emptyMessage}</p>;
  }

  const middle = centre(total);

  return (
    // Donut and legend read as one unit, centred, rather than a small ring
    // floating in a card that is wider than the chart needs.
    <div className="mx-auto w-full max-w-sm">
      <div className={`${FRAME} relative`}>
        <div className="h-full" aria-hidden="true">
          <ResponsiveContainer width="100%" height="100%">
            <PieChart accessibilityLayer={false}>
              {/* Recharts transitions the panel's transform, so it slides
                diagonally across the plot as the pointer moves between
                slices. */}
              <Tooltip
                isAnimationActive={false}
                content={
                  <ChartTooltip
                    formatValue={value =>
                      `${value.toLocaleString()} (${percent(value, total)})`
                    }
                  />
                }
              />
              {/* `accessibilityLayer` only governs the svg; the pie's own root
                group is a tab stop by default (`rootTabIndex` 0), and
                `aria-hidden` on the frame doesn't take it out of the order.
                So clicking a wedge is a mouse affordance only — the legend
                rows below carry the same links reachably. */}
              <Pie
                rootTabIndex={-1}
                onClick={(_, index) =>
                  window.open(slices[index]?.href, '_blank')
                }
                className="cursor-pointer"
                // `fill` per entry rather than a `<Cell>` child — Cell is
                // deprecated and goes in Recharts 4.
                data={slices.map(({ label, value, color }) => ({
                  name: label,
                  value,
                  fill: color,
                }))}
                dataKey="value"
                nameKey="name"
                innerRadius={60}
                outerRadius={80}
                stroke="#fff"
                strokeWidth={2}
              />
            </PieChart>
          </ResponsiveContainer>
        </div>
        {/* Over the chart rather than a Recharts `Label`, which can only draw
            one line of svg text. The pie is centred in this box, so this lines
            up with the ring's hole. It sits outside the `aria-hidden` chart, so
            screen readers read it too. */}
        <div className="pointer-events-none absolute inset-0 flex flex-col items-center justify-center">
          <span className="text-2xl font-semibold text-gray-900">
            {middle.value}
          </span>
          <span className="text-xs text-gray-500">{middle.label}</span>
        </div>
      </div>

      {/* Neither palette identifies a slice by hue alone — the outcomes pair
          sits 4.1 CVD ΔE apart and the failure palette's tightest pair 6.1, in
          the band that is legal only with secondary encoding. The labels and
          counts here are that encoding, so the legend is never optional. The
          chart above is hidden from assistive tech; this legend is its
          accessible representation. */}
      <ul className="mt-2 flex flex-wrap justify-center gap-x-6 gap-y-1 text-sm text-gray-700">
        {slices.map(({ key, label, color, value, href }) => (
          <li key={key}>
            <a
              href={href}
              target="_blank"
              rel="noopener noreferrer"
              className="flex items-center gap-1.5 rounded-xs focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary-600"
            >
              <span
                aria-hidden="true"
                className="h-2.5 w-2.5 shrink-0 rounded-full"
                style={{ backgroundColor: color }}
              />
              <span className="capitalize">{label}</span>{' '}
              <span className="font-medium tabular-nums text-gray-900">
                {value.toLocaleString()}
              </span>{' '}
              {/* The share is otherwise only in the hover tooltip. */}
              <span className="sr-only">({percent(value, total)})</span>{' '}
              <span className="sr-only">(opens in a new tab)</span>
            </a>
          </li>
        ))}
      </ul>
    </div>
  );
};
