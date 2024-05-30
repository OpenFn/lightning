import { create } from 'zustand';

export type LogLine = {
  id: string;
  message: string;
  source: string;
  level: string;
  step_id: string;
  timestamp: string;
};

type LogStore = {
  logLines: LogLine[];
  addLogLines: (newLogs: LogLine[]) => void;
};

// The VER logs are multiline
function splitLogMessages(logs: LogLine[]): LogLine[] {
  const newLogs: LogLine[] = [];

  logs.forEach(log => {
    // Split the message on every newline.
    const messages = log.message.split('\n');
    messages.forEach(message => {
      // Create a new log entry for each line, copying other attributes.
      newLogs.push({
        ...log,
        message: message,
      });
    });
  });

  return newLogs;
}

export const useLogStore = create<LogStore>(set => ({
  logLines: [],
  addLogLines: newLogs =>
    set(state => {
      const splitLogs = splitLogMessages(newLogs);
      const logs = [...state.logLines, ...splitLogs];

      logs.sort(
        (a, b) =>
          new Date(a.timestamp).getTime() - new Date(b.timestamp).getTime()
      );
      return { logLines: logs };
    }),
}));
