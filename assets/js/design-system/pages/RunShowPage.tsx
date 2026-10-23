import {
  type LogLine,
  RunShowPage as DesignSystemRunShowPage,
  type RunShowPageProps,
  type StepDataclip,
} from '@openfn/ui';
import { useEffect, useRef, useState } from 'react';

import { fetchDataclipBody } from '../dataclip-body';
import { designSystemPage } from '../page';

/** What RunLive.Show puts in `data-props`: the page's props minus the log and the handlers. */
export type Props = Omit<
  RunShowPageProps,
  'logs' | 'onCancel' | 'onLogLevelChange'
>;

/** A log line as the LiveView pushes it (Lightning.Invocation.LogLine). */
interface PushedLogLine {
  id: string;
  source: string;
  level: string;
  message: string;
  timestamp: string | number;
  step_id: string | null;
}

/** A line with the instant it was logged, for ordering. */
interface Entry {
  at: number;
  line: LogLine;
}

const entryOf = (line: PushedLogLine): Entry => ({
  at:
    typeof line.timestamp === 'number'
      ? line.timestamp
      : Date.parse(line.timestamp),
  line: {
    timestamp: String(line.timestamp),
    source: line.source,
    level: line.level,
    message: line.message,
    stepId: line.step_id,
  },
});

/**
 * The design system's run page, fed by RunLive.Show. The island keeps the
 * log lines the LiveView pushes (deduplicated and in time order, as the old
 * viewer's store did) and fetches dataclip bodies from the browser, as the
 * old viewer did: a body can be megabytes and never travels in props.
 */
export const RunShowPage = designSystemPage(
  'RunShowPage',
  DesignSystemRunShowPage,
  ['/projects/:project_id/runs/:id'],
  (props: Props, { send, subscribe }) => {
    const [logs, setLogs] = useState<LogLine[]>([]);
    const entries = useRef<Entry[]>([]);
    const seen = useRef(new Set<string>());
    const [bodies, setBodies] = useState<Record<string, string>>({});

    useEffect(() => {
      const unsubscribe = subscribe<{ logs: PushedLogLine[] }>(
        `logs-${props.runId}`,
        ({ logs: pushed }) => {
          const fresh = pushed.filter(line => !seen.current.has(line.id));
          if (fresh.length === 0) return;
          for (const line of fresh) seen.current.add(line.id);
          const last = entries.current[entries.current.length - 1];
          const next = entries.current.concat(fresh.map(entryOf));
          // Lines arrive in order except when a live line beats the first
          // load; only then is a sort needed.
          if (last && fresh.some(line => entryOf(line).at < last.at))
            next.sort((a, b) => a.at - b.at);
          entries.current = next;
          setLogs(next.map(entry => entry.line));
        }
      );
      // Only now can a pushed line be heard; the LiveView streams the
      // stored lines on this, so none are lost to a late subscription.
      void send('logs_ready').catch(() => {});
      return () => {
        unsubscribe();
        entries.current = [];
        seen.current = new Set();
        setLogs([]);
      };
    }, [props.runId, subscribe, send]);

    const wanted = [props.inputDataclip, props.outputDataclip]
      .filter((d): d is StepDataclip => d !== null && !d.wiped)
      .map(d => d.id);
    const wantedKey = wanted.join(',');
    useEffect(() => {
      for (const id of wanted) {
        if (id in bodies) continue;
        void fetchDataclipBody(id).then(body =>
          setBodies(current => ({ ...current, [id]: body }))
        );
      }
      // Only new ids matter; `bodies` changing must not refetch.
      // eslint-disable-next-line react-hooks/exhaustive-deps
    }, [wantedKey]);

    const withBody = (dataclip: StepDataclip | null) =>
      dataclip && dataclip.id in bodies
        ? { ...dataclip, body: bodies[dataclip.id] }
        : dataclip;

    return {
      ...props,
      inputDataclip: withBody(props.inputDataclip),
      outputDataclip: withBody(props.outputDataclip),
      logs,
      onCancel: () => send('cancel_run'),
      // The old filter saved silently too; a failed save only means the
      // next visit starts on the previous level.
      onLogLevelChange: level => {
        void send('save_log_level', { level }).catch(() => {});
      },
    };
  }
);
