import { useEffect, useRef, useState } from 'react';

import { mount as mountLogViewer } from '../../../log-viewer/component';
import { createLogStore } from '../../../log-viewer/store';
import { channelRequest } from '../../hooks/useChannel';
import { useActiveRun, useSelectedStepId } from '../../hooks/useHistory';
import { useSession } from '../../hooks/useSession';

import { LogLevelFilter } from './LogLevelFilter';

export function LogTabPanel() {
  const run = useActiveRun();
  const selectedStepId = useSelectedStepId();
  const { provider } = useSession();

  const containerRef = useRef<HTMLDivElement>(null);
  const storeRef = useRef(createLogStore());
  const viewerInstanceRef = useRef<ReturnType<typeof mountLogViewer> | null>(
    null
  );
  const mountedRef = useRef(false);

  // Track log level state from store
  const [logLevel, setLogLevel] = useState<'debug' | 'info' | 'warn' | 'error'>(
    () => storeRef.current.getState().desiredLogLevel as any
  );

  // Handle log level change
  const handleLogLevelChange = (
    newLevel: 'debug' | 'info' | 'warn' | 'error'
  ) => {
    storeRef.current.getState().setDesiredLogLevel(newLevel);
    setLogLevel(newLevel);
  };

  // Mount log viewer on first render
  useEffect(() => {
    if (!containerRef.current) {
      return;
    }

    // Prevent double-mounting in React Strict Mode
    if (mountedRef.current) {
      return;
    }

    try {
      mountedRef.current = true;
      viewerInstanceRef.current = mountLogViewer(
        containerRef.current,
        storeRef.current
      );
    } catch (error) {
      console.error('[LogTabPanel] Failed to mount log viewer:', error);
      mountedRef.current = false;
    }

    return () => {
      // Don't actually unmount - let the component stay mounted
      // Only unmount when the component is truly destroyed
    };
  }, []);

  // Update selected step in log store
  useEffect(() => {
    storeRef.current.getState().setStepId(selectedStepId ?? undefined);
  }, [selectedStepId]);

  // Subscribe to log events via existing run channel
  useEffect(() => {
    if (!run || !provider?.socket) {
      return undefined;
    }

    const channels = (provider.socket as any).channels;
    const channel = channels?.find((ch: any) => ch.topic === `run:${run.id}`);

    if (!channel) {
      console.warn('[LogTabPanel] Run channel not found for logs', {
        runId: run.id,
      });
      return undefined;
    }

    // Fetch initial logs
    void channelRequest<{ logs: unknown }>(channel, 'fetch:logs', {})
      .then(response => {
        if (!response.logs || !Array.isArray(response.logs)) {
          return;
        }

        const logStore = storeRef.current.getState();
        logStore.addLogLines(response.logs as any);
      })
      .catch(error => {
        console.error('[LogTabPanel] Failed to fetch logs', error);
      });

    // Listen for new logs
    const logHandler = (payload: { logs: unknown[] }) => {
      const logStore = storeRef.current.getState();
      logStore.addLogLines(payload.logs as any);
    };

    channel.on('logs', logHandler);

    return () => {
      channel.off('logs', logHandler);
    };
  }, [run, provider]);

  return (
    <div className="grid h-full grid-rows-[auto_1fr] bg-slate-700 font-mono text-gray-200">
      {/* Log level filter header */}
      <div className="border-b border-slate-500">
        <div className="mx-auto px-2">
          <div className="flex h-6 flex-row-reverse items-center">
            <LogLevelFilter
              selectedLevel={logLevel}
              onLevelChange={handleLogLevelChange}
            />
          </div>
        </div>
      </div>

      {/* Log viewer */}
      <div ref={containerRef} className="min-h-0" />
    </div>
  );
}
