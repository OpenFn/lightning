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
  desiredLogLevels: string[];
  setDesiredLogLevels: (desiredLogLevels: string[] | undefined) => void;
}

// check if a log matches the desired log level
function matchesLogFilter(log: LogLine, desiredLogLevels: string[]): boolean {
  if (desiredLogLevels.length === 0) return true;

  return desiredLogLevels.includes(log.level);
}

function findSelectedRanges(
  logs: LogLine[],
  stepId: string | undefined,
  desiredLogLevels: string[]
) {
  if (!stepId) return [];

  const { ranges } = logs.reduce<{
    ranges: { start: number; end: number }[];
    marker: number;
  }>(
    ({ ranges, marker }, log) => {
      // Get the number of newlines in the message, used to determine the end index.
      const newLineCount = [...possiblyPrettify(log.message).matchAll(/\n/g)]
        .length;

      const nextMarker = marker + 1 + newLineCount;

      // Skip logs that don't match the step ID or desired log levels
      if (log.step_id !== stepId || !matchesLogFilter(log, desiredLogLevels)) {
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

function isProbablyJSON(str: string) {
  // Check if the string starts with '{' or '[' and ends with '}' or ']'
  return (
    (str.startsWith('{') && str.endsWith('}')) ||
    (str.startsWith('[') && str.endsWith(']'))
  );
}

function tryPrettyJSON(str: string) {
  try {
    const jsonObj = JSON.parse(str);
    return JSON.stringify(jsonObj, null, 2);
  } catch {
    return str;
  }
}

function possiblyPrettify(str: string | string) {
  if (isProbablyJSON(str)) {
    return tryPrettyJSON(str);
  }
  return str;
}

function formatLogLine(log: LogLine) {
  const { source, message } = log;
  return `${source} ${possiblyPrettify(message)}`;
}

function stringifyLogLines(logLines: LogLine[], desiredLogLevels: string[]) {
  const lines = logLines.reduce((formatted, log) => {
    if (matchesLogFilter(log, desiredLogLevels)) {
      return formatted + (formatted !== '' ? '\n' : '') + formatLogLine(log);
    }
    return formatted;
  }, '');

  return lines;
}

export const createLogStore = () => {
  const createStore = create<LogStore>()(
    subscribeWithSelector((set, get) => ({
      stepId: undefined,
      setStepId: (stepId: string | undefined) => set({ stepId }),
      desiredLogLevels: [],
      setDesiredLogLevels: (desiredLogLevels: string[] | undefined) =>
        set({ desiredLogLevels: desiredLogLevels || [] }),
      highlightedRanges: [],
      logLines: [],
      stepSetAt: undefined,
      formattedLogLines: '',
      addLogLines: newLogs => {
        newLogs = coerceLogs(newLogs);
        const logLines = get().logLines.concat(newLogs);

        logLines.sort((a, b) => a.timestamp.getTime() - b.timestamp.getTime());

        const desiredLogLevels = get().desiredLogLevels;

        set({
          formattedLogLines: stringifyLogLines(logLines, desiredLogLevels),
          logLines,
        });
      },
    }))
  );

  // Subscribe to the store and update the highlighted ranges when the
  // log lines or step ID or log levels changes.
  createStore.subscribe<[LogLine[], undefined | string, string[]]>(
    state => [state.logLines, state.stepId, state.desiredLogLevels],
    (
      [logLines, stepId, desiredLogLevels],
      [_prevLogLines, _prevStepId, prevLogLevels]
    ) => {
      const state = {
        highlightedRanges: findSelectedRanges(
          logLines,
          stepId,
          desiredLogLevels
        ),
      };

      if (prevLogLevels !== desiredLogLevels) {
        state.formattedLogLines = stringifyLogLines(logLines, desiredLogLevels);
      }
      createStore.setState(state);
    },
    {
      equalityFn: (
        [prevLogLines, prevStepId, prevLogLevels],
        [nextLogLines, nextStepId, nextLogLevels]
      ) => {
        return (
          prevLogLines.length === nextLogLines.length &&
          prevStepId === nextStepId &&
          prevLogLevels === nextLogLevels
        );
      },
    }
  );

  return createStore;
};
