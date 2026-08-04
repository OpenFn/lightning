import {
  Bar,
  BarChart,
  CartesianGrid,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from 'recharts';

import { barChart, chart } from './theme';
import type { ResponseTime } from './types';

/**
 * How long runs take, as a histogram of duration buckets.
 *
 * A histogram rather than a line: the interesting thing about run durations is
 * their shape — one hump or two, and how heavy the tail is — which an average
 * over time hides completely.
 */
export const ResponseTimeChart = ({ data }: { data: ResponseTime }) => (
  <div className="h-[200px]">
    <ResponsiveContainer width="100%" height="100%">
      <BarChart data={data.histogram} margin={barChart.margin}>
        <CartesianGrid {...barChart.grid} />
        <XAxis dataKey="label" {...barChart.xAxis} />
        <YAxis {...barChart.yAxis} />
        <Tooltip {...barChart.tooltip} />
        <Bar
          dataKey="runs"
          name="Runs"
          fill={chart.duration}
          radius={barChart.bar.radius}
          isAnimationActive={false}
        />
      </BarChart>
    </ResponsiveContainer>
  </div>
);
