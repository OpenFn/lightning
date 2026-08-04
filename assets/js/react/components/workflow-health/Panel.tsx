export interface PanelProps {
  title: string;
  /** Small right-aligned note in the header — a unit, a total, a caveat. */
  meta?: React.ReactNode;
  /** Explanatory line under the chart. */
  footnote?: React.ReactNode;
  children: React.ReactNode;
}

export const Panel = ({ title, meta, footnote, children }: PanelProps) => (
  <section className="flex flex-col rounded-lg border border-gray-200 bg-white p-5">
    <header className="mb-4 flex items-baseline justify-between gap-3">
      <h2 className="text-xs font-semibold uppercase tracking-wide text-gray-500">
        {title}
      </h2>
      {meta ? (
        <span className="shrink-0 text-xs text-gray-400">{meta}</span>
      ) : null}
    </header>

    <div className="flex-1">{children}</div>

    {footnote ? (
      <p className="mt-4 text-xs leading-relaxed text-gray-500">{footnote}</p>
    ) : null}
  </section>
);

/**
 * Marks something the screen shows but Lightning cannot compute yet, so a
 * placeholder is never mistaken for a finished feature.
 */
export const ProvisionalBadge = () => (
  <span
    className="rounded-sm bg-amber-100 px-1.5 py-0.5 text-[10px] font-medium uppercase tracking-wide text-amber-800"
    title="Not backed by stored data yet"
  >
    Placeholder
  </span>
);

/**
 * A legend row: swatch, label, count, share. Labels and counts are always
 * present so a reader never has to tell two slices apart by colour alone.
 */
export const LegendRow = ({
  color,
  label,
  count,
  percentage,
}: {
  color: string;
  label: string;
  count: number;
  percentage?: number;
}) => (
  <li className="flex items-center gap-2 text-sm">
    <span
      aria-hidden="true"
      className="size-2.5 shrink-0 rounded-[2px]"
      style={{ backgroundColor: color }}
    />
    <span className="flex-1 truncate text-gray-700">{label}</span>
    <span className="font-medium tabular-nums text-gray-900">
      {count.toLocaleString('en-US')}
    </span>
    {percentage == null ? null : (
      <span className="w-12 text-right tabular-nums text-gray-400">
        {percentage.toFixed(1)}%
      </span>
    )}
  </li>
);
