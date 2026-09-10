import type { TooltipContentProps } from 'recharts';

import { cn } from '#/utils/cn';

/**
 * Hover panel for the health charts, in the page's own card chrome.
 *
 * Recharts' default panel is a square-cornered box of coloured text, which
 * matches nothing else here. This one borrows the card it floats over
 * (`WorkflowHealth.tsx:178` — white, `rounded-lg`, a shadow) and lays its rows
 * out like the legends under the charts: swatch, name, count. The swatch is
 * what carries the series colour, so the counts stay readable rather than
 * trading contrast for identity.
 */

interface ChartTooltipProps
  extends Partial<TooltipContentProps<number, string>> {
  /** Renders the axis label — the bar's slot, say, rather than its start. */
  formatLabel?: (label: string) => string;
  /** Renders one row's count, for panels that add a share to it. */
  formatValue?: (value: number) => string;
  /** Flips the rows, for a stack whose bars are declared bottom-up. */
  reverse?: boolean;
}

export const ChartTooltip = ({
  active,
  payload,
  label,
  reverse,
  formatLabel,
  formatValue = value => value.toLocaleString(),
}: ChartTooltipProps) => {
  if (!active || !payload?.length) return null;

  const rows = reverse ? [...payload].reverse() : payload;

  // A lone row has no column to line up against and nothing to stand out
  // from, so the treatment that reads a column — counts pushed right, and
  // weighted — is only earned once there are several. The donut shows one
  // slice at a time.
  const column = rows.length > 1;

  return (
    <div className="rounded-lg border border-gray-200 bg-white text-xs shadow-lg">
      {label != null && (
        <p className="border-b border-gray-100 px-3 py-2 font-medium text-gray-900">
          {formatLabel ? formatLabel(String(label)) : String(label)}
        </p>
      )}
      <ul className="flex flex-col gap-1.5 px-3 py-2 text-gray-700">
        {rows.map(({ dataKey, name, value, color }) => (
          <li key={String(name ?? dataKey)} className="flex items-center gap-2">
            <span
              className="h-2 w-2 shrink-0 rounded-full"
              style={{ backgroundColor: color }}
            />
            <span className={column ? 'grow pr-4' : ''}>{name}</span>
            <span
              className={cn(
                'tabular-nums text-gray-900',
                column && 'font-medium'
              )}
            >
              {formatValue(Number(value))}
            </span>
          </li>
        ))}
      </ul>
    </div>
  );
};
