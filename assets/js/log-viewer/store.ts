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

export const useLogStore = create<LogStore>(set => ({
  logLines: [],
  addLogLines: newLogs =>
    set(state => {
      const logs = [...state.logLines, ...newLogs];

      logs.sort(
        (a, b) =>
          new Date(a.timestamp).getTime() - new Date(b.timestamp).getTime()
      );
      return { logLines: logs };
    }),
}));
