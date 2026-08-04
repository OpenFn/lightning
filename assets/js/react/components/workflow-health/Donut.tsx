import { Cell, Pie, PieChart, ResponsiveContainer, Tooltip } from 'recharts';

import { tooltipFormatter, tooltipStyle } from './theme';

export interface DonutSlice {
  key: string;
  label: string;
  value: number;
  color: string;
}

export interface DonutProps {
  slices: DonutSlice[];
  /** Large figure in the hole — the one number the panel exists to show. */
  centerValue: string;
  centerLabel: string;
}

/**
 * A two-to-six slice donut with the headline figure in the middle.
 *
 * The centre figure is the point of the chart; the ring shows how the whole
 * divides. A 2px surface-coloured stroke separates touching segments so the
 * boundary never depends on the two hues being distinguishable.
 */
export const Donut = ({ slices, centerValue, centerLabel }: DonutProps) => {
  const total = slices.reduce((sum, slice) => sum + slice.value, 0);

  if (total === 0) {
    return (
      <div className="flex h-[180px] items-center justify-center text-sm text-gray-400">
        No runs in this window
      </div>
    );
  }

  return (
    <div className="relative h-[180px]">
      <ResponsiveContainer width="100%" height="100%">
        <PieChart>
          <Pie
            data={slices}
            dataKey="value"
            nameKey="label"
            innerRadius={58}
            outerRadius={84}
            paddingAngle={0}
            stroke="#ffffff"
            strokeWidth={2}
            isAnimationActive={false}
          >
            {slices.map(slice => (
              <Cell key={slice.key} fill={slice.color} />
            ))}
          </Pie>
          <Tooltip
            cursor={false}
            formatter={tooltipFormatter}
            contentStyle={tooltipStyle}
          />
        </PieChart>
      </ResponsiveContainer>

      <div className="pointer-events-none absolute inset-0 flex flex-col items-center justify-center">
        <span className="text-2xl font-semibold text-gray-900">
          {centerValue}
        </span>
        <span className="text-[10px] font-medium uppercase tracking-wide text-gray-500">
          {centerLabel}
        </span>
      </div>
    </div>
  );
};
