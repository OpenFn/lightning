import {
  Bar,
  BarChart,
  CartesianGrid,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from 'recharts';

import { barChart, chart, formatBucketTime } from './theme';
import type { VolumeOverTime } from './types';

/**
 * Runs over time, with failures stacked on top of successes.
 *
 * Stacked rather than overlaid so the bar height stays the run count — the
 * question is "how busy was it, and how much of that went wrong", and an
 * overlay would answer neither cleanly.
 */
export const VolumeChart = ({ data }: { data: VolumeOverTime }) => {
  const rows = data.buckets.map(bucket => ({
    time: formatBucketTime(bucket.started_at, data.bucket_seconds),
    succeeded: bucket.runs - bucket.failed,
    failed: bucket.failed,
  }));

  return (
    <div className="h-[200px]">
      <ResponsiveContainer width="100%" height="100%">
        <BarChart data={rows} margin={barChart.margin}>
          <CartesianGrid {...barChart.grid} />
          <XAxis
            dataKey="time"
            {...barChart.xAxis}
            interval="preserveStartEnd"
            minTickGap={24}
          />
          <YAxis {...barChart.yAxis} />
          <Tooltip {...barChart.tooltip} />
          <Bar
            dataKey="succeeded"
            name="Succeeded"
            stackId="runs"
            fill={chart.runs}
            isAnimationActive={false}
          />
          <Bar
            dataKey="failed"
            name="Failed"
            stackId="runs"
            fill={chart.runsFailed}
            radius={barChart.bar.radius}
            isAnimationActive={false}
          />
        </BarChart>
      </ResponsiveContainer>
    </div>
  );
};
