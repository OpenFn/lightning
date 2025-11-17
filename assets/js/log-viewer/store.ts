import { subscribeWithSelector } from 'zustand/middleware';
import { createStore } from 'zustand/vanilla';

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
  desiredLogLevel: string;
  setDesiredLogLevel: (desiredLogLevel: string | undefined) => void;
}

// get score for log level
function logLevelScore(level: string): number {
  switch (level) {
    case 'debug':
      return 0;
    case 'info':
      return 1;
    case 'warn':
      return 2;
    case 'error':
      return 3;
    default:
      return 4;
  }
}

// check if a log matches the desired log level
function matchesLogFilter(log: LogLine, desiredLogLevel: string): boolean {
  return logLevelScore(log.level) >= logLevelScore(desiredLogLevel);
}

function findSelectedRanges(
  logs: LogLine[],
  stepId: string | undefined,
  desiredLogLevel: string
) {
  if (!stepId) return [];

  const { ranges } = logs.reduce<{
    ranges: { start: number; end: number }[];
    marker: number;
  }>(
    ({ ranges, marker }, log) => {
      // Skip logs that don't match the desired log levels
      if (!matchesLogFilter(log, desiredLogLevel)) {
        return { ranges, marker: marker };
      }

      // Get the number of newlines in the message, used to determine the end index.
      const newLineCount = [...possiblyPrettify(log.message).matchAll(/\n/g)]
        .length;

      const nextMarker = marker + 1 + newLineCount;

      // Skip logs that don't match the step ID
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
  return logs.map(log => {
    return {
      ...log,
      timestamp: new Date(log.timestamp),
    };
  });
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

function possiblyPrettify(str: string) {
  if (isProbablyJSON(str)) {
    return tryPrettyJSON(str);
  }
  return str;
}

function formatLogLine(log: LogLine) {
  const { source, message } = log;
  return `${source} ${possiblyPrettify(message)}`;
}

function stringifyLogLines(logLines: LogLine[], desiredLogLevel: string) {
  const lines = logLines.reduce((formatted, log) => {
    if (matchesLogFilter(log, desiredLogLevel)) {
      return formatted + (formatted !== '' ? '\n' : '') + formatLogLine(log);
    }
    return formatted;
  }, '');

  return lines;
}

export const createLogStore = () => {
  const logStore = createStore<LogStore>()(
    subscribeWithSelector((set, get) => ({
      stepId: undefined,
      setStepId: (stepId: string | undefined) => set({ stepId }),
      desiredLogLevel: 'info',
      setDesiredLogLevel: (desiredLogLevel: string | undefined) =>
        set({ desiredLogLevel: desiredLogLevel || 'info' }),
      highlightedRanges: [],
      logLines: [],
      stepSetAt: undefined,
      formattedLogLines: '',
      addLogLines: newLogs => {
        newLogs = coerceLogs(newLogs);

        // Deduplicate logs by ID
        const existingIds = new Set(get().logLines.map(log => log.id));
        const uniqueNewLogs = newLogs.filter(log => !existingIds.has(log.id));

        const logLines = get().logLines.concat(uniqueNewLogs);

        logLines.sort((a, b) => a.timestamp.getTime() - b.timestamp.getTime());

        const desiredLogLevel = get().desiredLogLevel;
        const formatted = stringifyLogLines(logLines, desiredLogLevel);

        set({
          formattedLogLines: formatted,
          logLines,
        });
      },
    }))
  );

  // Subscribe to the store and update the highlighted ranges when the
  // log lines or step ID or log levels changes.
  logStore.subscribe<[LogLine[], undefined | string, string]>(
    state => [state.logLines, state.stepId, state.desiredLogLevel],
    (
      [logLines, stepId, desiredLogLevel],
      [_prevLogLines, _prevStepId, prevLogLevel]
    ) => {
      const state: Partial<LogStore> = {
        highlightedRanges: findSelectedRanges(
          logLines,
          stepId,
          desiredLogLevel
        ),
      };

      if (prevLogLevel !== desiredLogLevel) {
        state.formattedLogLines = stringifyLogLines(logLines, desiredLogLevel);
      }
      logStore.setState(state);
    },
    {
      equalityFn: (
        [prevLogLines, prevStepId, prevLogLevel],
        [nextLogLines, nextStepId, nextLogLevel]
      ) => {
        return (
          prevLogLines.length === nextLogLines.length &&
          prevStepId === nextStepId &&
          prevLogLevel === nextLogLevel
        );
      },
    }
  );

  return logStore;
};
