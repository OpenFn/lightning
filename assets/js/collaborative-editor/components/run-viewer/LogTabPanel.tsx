import { useCallback, useEffect, useRef, useState } from 'react';

import { mount as mountLogViewer } from '../../../log-viewer/component';
import { createLogStore } from '../../../log-viewer/store';
import { channelRequest } from '../../hooks/useChannel';
import { useActiveRun, useSelectedStepId } from '../../hooks/useHistory';
import { useSession } from '../../hooks/useSession';
import { isFinalState } from '../../types/history';

import { LogLevelFilter } from './LogLevelFilter';

const TYPING_SPEED = 30; // ms per character when typing
const PAUSE_AT_END = 2000; // ms to pause when message fully typed
const PAUSE_AT_BASE = 500; // ms to pause before typing next suffix

// Messages to cycle through for each waiting state (mix of informative and playful)
const WAITING_MESSAGES: Record<string, string[]> = {
  available: [
    'Workers claim runs in the order in which they were added to the queue...',
    'A wake-up call is sent to the worker pool when new runs are added...',
    'Hang tight. Still looking for an available worker...',
    'Workers must establish encrypted connections before they can start work on a run...',
    'You can adjust concurrency (how many runs can run at once) at both the project level and the workflow level...',
    'You can see how many runs are enqueued for this project on the project dashboard, or by filtering to status "Enqueued" in the history page...',
    'If this is taking a really long time, talk to your instance admin about adding more workers...',
  ],
  claimed: [
    'Your runtime is spinning up...',
    'Dependencies are being installed...',
    'Adaptors are being loaded...',
    'A secure sandbox is initializing...',
    'Input data is being transferred securely...',
    'The execution engine is warming up...',
  ],
  default: [
    'Nothing yet...',
    'Hang tight...',
    'Any moment now...',
    'Standing by...',
  ],
};

const getRandomMessage = (state: string | undefined): string => {
  const messages =
    WAITING_MESSAGES[state ?? 'default'] ?? WAITING_MESSAGES.default;
  return messages[Math.floor(Math.random() * messages.length)];
};

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
  const animationRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const currentMessageRef = useRef<string>('');
  const displayedTextRef = useRef<string>(''); // Mirror of displayedText for animation loop
  const animationPhaseRef = useRef<
    'typing' | 'paused' | 'deleting' | 'waiting'
  >('typing');
  const runStateRef = useRef<string | undefined>(undefined);

  // Handle log level change
  const handleLogLevelChange = (
    newLevel: 'debug' | 'info' | 'warn' | 'error'
  ) => {
    storeRef.current.getState().setDesiredLogLevel(newLevel);
    setLogLevel(newLevel);
  };

  // Determine if we should show the waiting animation
  const shouldShowWaiting = useCallback((): boolean => {
    if (hasLogs) return false;
    if (!run) return true;
    if (isFinalState(run.state)) return false; // Show static message instead
    return true;
  }, [run, hasLogs]);

  // Get the waiting state key for message selection
  const getWaitingState = useCallback((): string => {
    if (!run) return 'default';
    if (run.state === 'available') return 'available';
    if (run.state === 'claimed') return 'claimed';
    return 'default';
  }, [run]);

  // Typewriter animation with cycling messages
  useEffect(() => {
    const showAnimation = shouldShowWaiting();
    const waitingState = getWaitingState();

    // Clear any existing animation
    if (animationRef.current) {
      clearTimeout(animationRef.current);
      animationRef.current = null;
    }

    // If no animation needed, clear and show static message if needed
    if (!showAnimation) {
      // Show static message for final state with no logs
      if (!hasLogs && run && isFinalState(run.state)) {
        setDisplayedText('No logs were received for this run.');
        displayedTextRef.current = 'No logs were received for this run.';
      } else {
        setDisplayedText('');
        displayedTextRef.current = '';
      }
      return;
    }

    // Handle state change - reset animation
    if (runStateRef.current !== waitingState) {
      runStateRef.current = waitingState;
      animationPhaseRef.current = 'typing';
      currentMessageRef.current = getRandomMessage(waitingState);
      displayedTextRef.current = '';
      setDisplayedText('');
    }

    // Initialize message if not set
    if (!currentMessageRef.current) {
      currentMessageRef.current = getRandomMessage(waitingState);
    }

    const animate = () => {
      const currentMessage = currentMessageRef.current;
      const phase = animationPhaseRef.current;
      const prev = displayedTextRef.current;

      let nextText = prev;
      let nextDelay = TYPING_SPEED;

      // Phase: typing - type out the message
      if (phase === 'typing') {
        if (prev.length < currentMessage.length) {
          nextText = currentMessage.slice(0, prev.length + 1);
        } else {
          // Message complete, pause before deleting
          animationPhaseRef.current = 'paused';
          nextDelay = PAUSE_AT_END;
        }
      }
      // Phase: paused - wait is done via delay, now start deleting
      else if (phase === 'paused') {
        animationPhaseRef.current = 'deleting';
      }
      // Phase: deleting - delete characters
      else if (phase === 'deleting') {
        if (prev.length > 0) {
          nextText = prev.slice(0, -1);
        } else {
          // Fully deleted, wait before typing new message
          animationPhaseRef.current = 'waiting';
          nextDelay = PAUSE_AT_BASE;
        }
      }
      // Phase: waiting - pick new message and start typing
      else if (phase === 'waiting') {
        currentMessageRef.current = getRandomMessage(runStateRef.current);
        animationPhaseRef.current = 'typing';
      }

      // Update displayed text (both ref and state)
      displayedTextRef.current = nextText;
      setDisplayedText(nextText);

      // Schedule next frame
      animationRef.current = setTimeout(animate, nextDelay);
    };

    animationRef.current = setTimeout(animate, TYPING_SPEED);

    return () => {
      if (animationRef.current) {
        clearTimeout(animationRef.current);
        animationRef.current = null;
      }
    };
  }, [shouldShowWaiting, getWaitingState, hasLogs, run]);

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
  // Show overlay when waiting (even with empty text during animation) or showing static final message
  const showWaitingOverlay =
    !hasLogs && (shouldShowWaiting() || displayedText.length > 0);

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
            <span
              className="inline-block"
              style={{
                animation: 'cursor-blink 1.8s ease-in-out infinite',
              }}
            >
              ▌
            </span>
          </div>
        )}
        <style>{`
          @keyframes cursor-blink {
            0%, 100% { opacity: 0; }
            50% { opacity: 1; }
          }
        `}</style>
      </div>
    </div>
  );
}
