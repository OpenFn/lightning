import { useCallback, useEffect, useRef, useState } from 'react';

import { mount as mountLogViewer } from '../../../log-viewer/component';
import { createLogStore } from '../../../log-viewer/store';
import { channelRequest } from '../../hooks/useChannel';
import { useActiveRun, useSelectedStepId } from '../../hooks/useHistory';
import { useSession } from '../../hooks/useSession';
import { isFinalState } from '../../types/history';

import { LogLevelFilter } from './LogLevelFilter';

const TYPING_SPEED = 30; // ms per character when typing

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
  const prevRunIdRef = useRef<string | null>(null);

  // Track log level state from store
  const [logLevel, setLogLevel] = useState<'debug' | 'info' | 'warn' | 'error'>(
    () => storeRef.current.getState().desiredLogLevel as any
  );

  // Track whether we have received any logs
  const [hasLogs, setHasLogs] = useState(false);

  // Typewriter animation state - rendered as React overlay, NOT in Monaco
  const [displayedText, setDisplayedText] = useState('');
  const targetMessageRef = useRef<string | null>(null);
  const animationRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  // Handle log level change
  const handleLogLevelChange = (
    newLevel: 'debug' | 'info' | 'warn' | 'error'
  ) => {
    storeRef.current.getState().setDesiredLogLevel(newLevel);
    setLogLevel(newLevel);
  };

  // Determine waiting message based on run state
  const getWaitingMessage = useCallback((): string | null => {
    if (hasLogs) return null;
    if (!run) return 'Nothing yet...';
    if (run.state === 'available') return 'Waiting for worker...';
    if (run.state === 'claimed')
      return 'Creating runtime & installing adaptors...';
    if (isFinalState(run.state)) return 'No logs were received for this run.';
    return 'Nothing yet...';
  }, [run, hasLogs]);

  // Typewriter animation - only updates React state, never touches the store
  useEffect(() => {
    const target = getWaitingMessage();
    targetMessageRef.current = target;

    // Clear any existing animation
    if (animationRef.current) {
      clearTimeout(animationRef.current);
      animationRef.current = null;
    }

    // If no target (logs arrived), clear immediately
    if (target === null) {
      setDisplayedText('');
      return;
    }

    // Animate typing
    const animate = () => {
      const currentTarget = targetMessageRef.current;
      if (currentTarget === null) {
        setDisplayedText('');
        return;
      }

      setDisplayedText(prev => {
        // If target changed and doesn't start with current, reset
        if (!currentTarget.startsWith(prev) && prev.length > 0) {
          animationRef.current = setTimeout(animate, TYPING_SPEED);
          return prev.slice(0, -1);
        }

        // Type towards target
        if (prev.length < currentTarget.length) {
          animationRef.current = setTimeout(animate, TYPING_SPEED);
          return currentTarget.slice(0, prev.length + 1);
        }

        return prev;
      });
    };

    animationRef.current = setTimeout(animate, TYPING_SPEED);

    return () => {
      if (animationRef.current) {
        clearTimeout(animationRef.current);
        animationRef.current = null;
      }
    };
  }, [getWaitingMessage]);

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

    // Only clear logs when the run actually changes, not when provider changes
    const runChanged = prevRunIdRef.current !== run.id;
    if (runChanged) {
      storeRef.current.getState().clearLogs();
      setHasLogs(false);
      prevRunIdRef.current = run.id;
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
        if (response.logs.length > 0) {
          setHasLogs(true);
        }
      })
      .catch(error => {
        console.error('[LogTabPanel] Failed to fetch logs', error);
      });

    // Listen for new logs
    const logHandler = (payload: { logs: unknown[] }) => {
      const logStore = storeRef.current.getState();
      logStore.addLogLines(payload.logs as any);
      if (payload.logs.length > 0) {
        setHasLogs(true);
      }
    };

    channel.on('logs', logHandler);

    return () => {
      channel.off('logs', logHandler);
    };
  }, [run, provider]);

  // Show waiting overlay when no logs yet
  const showWaitingOverlay = !hasLogs && displayedText.length > 0;

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

      {/* Log viewer container */}
      <div className="relative min-h-0">
        {/* Monaco log viewer - only shows real logs */}
        <div ref={containerRef} className="h-full" />

        {/* Waiting message overlay - completely separate from Monaco */}
        {showWaitingOverlay && (
          <div className="absolute inset-0 flex items-start bg-slate-700 p-4 font-mono text-sm text-gray-400">
            {displayedText}
            <span className="animate-pulse">▌</span>
          </div>
        )}
      </div>
    </div>
  );
}
