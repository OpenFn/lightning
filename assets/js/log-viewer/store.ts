import { create } from 'zustand';
import { subscribeWithSelector } from 'zustand/middleware';

export type LogLine = {
  id: string;
  message: string;
  source: string;
  level: string;
  step_id: string;
  timestamp: Date;
};

interface LogStore {
  stepId: string | undefined;
  setStepId: (stepId: string | undefined) => void;
  logLines: LogLine[];
  formattedLogLines: string;
  addLogLines: (newLogs: LogLine[]) => void;
  highlightedRanges: { start: number; end: number }[];
}

function findSelectedRanges(logs: LogLine[], stepId: string | undefined) {
  if (!stepId) return [];

  const { ranges } = logs.reduce<{
    ranges: { start: number; end: number }[];
    marker: number;
  }>(
    ({ ranges, marker }, log) => {
      // Get the number of newlines in the message, used to determine the end index.
      const newLineCount = [...log.message.matchAll(/\n/g)].length;
      const nextMarker = marker + 1 + newLineCount;

      if (log.step_id !== stepId) {
        return { ranges, marker: nextMarker };
      }

      const last = ranges[ranges.length - 1];

      if (!last) {
        return {
          ranges: [{ start: marker, end: nextMarker }],
          marker: nextMarker,
        };
      }

      if (last.end <= nextMarker) {
        last.end = nextMarker;
      } else {
        ranges.push({ start: marker, end: nextMarker });
      }

      return { ranges, marker: nextMarker };
    },
    { ranges: [], marker: 0 }
  );

  return ranges;
}

function coerceLogs(logs: LogLine[]): LogLine[] {
  return logs.map(log => ({
    ...log,
    timestamp: new Date(log.timestamp),
  }));
}

function formatLogLine(log: LogLine) {
  return `${log.source} ${log.message}`;
}

export const createLogStore = () => {
  const createStore = create<LogStore>()(
    subscribeWithSelector((set, get) => ({
      stepId: undefined,
      setStepId: (stepId: string | undefined) => set({ stepId }),
      highlightedRanges: [],
      logLines: [],
      stepSetAt: undefined,
      formattedLogLines: '',
      addLogLines: newLogs => {
        newLogs = coerceLogs(newLogs);
        const logLines = get().logLines.concat(newLogs);

        logLines.sort((a, b) => a.timestamp.getTime() - b.timestamp.getTime());

        set({
          formattedLogLines: logLines.map(formatLogLine).join('\n'),
          logLines,
        });
      },
    }))
  );

  // Subscribe to the store and update the highlighted ranges when the
  // log lines or step ID changes.
  createStore.subscribe<[LogLine[], undefined | string]>(
    state => [state.logLines, state.stepId],
    ([logLines, stepId], _) => {
      createStore.setState({
        highlightedRanges: findSelectedRanges(logLines, stepId),
      });
    },
    {
      equalityFn: ([prevLogLines, prevStepId], [nextLogLines, nextStepId]) => {
        return (
          prevLogLines.length === nextLogLines.length &&
          prevStepId === nextStepId
        );
      },
    }
  );

  return createStore;
};
