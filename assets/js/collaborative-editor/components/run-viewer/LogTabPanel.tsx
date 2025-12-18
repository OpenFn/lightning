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

// Initial messages shown first for each state (before cycling)
const INITIAL_MESSAGES: Record<string, string> = {
  available: 'Waiting for a worker to establish a secure claim...',
  claimed: 'Creating an isolated runtime and installing adaptors...',
};

// Messages to cycle through for each waiting state (after initial message)
const WAITING_MESSAGES: Record<string, string[]> = {
  available: [
    'Runs are claimed the order in which they were added to the queue...',
    'A "wake-up call" is sent to the worker pool when new runs are added...',
    'Concurrency (how many runs at the same time) can be set at project-level and workflow-level...',
    'Check the "History" page to see how many runs are enqueue for this project...',
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
  // Initial message types out first, then stays visible while cycling messages animate below
  const [initialText, setInitialText] = useState(''); // The typed-out initial message
  const [cyclingText, setCyclingText] = useState('');
  const animationRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const currentMessageRef = useRef<string>('');
  const initialTextRef = useRef<string>(''); // Mirror of initialText
  const cyclingTextRef = useRef<string>(''); // Mirror of cyclingText
  const animationPhaseRef = useRef<
    'typing-initial' | 'typing' | 'paused' | 'deleting' | 'waiting'
  >('typing-initial');
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

  // Typewriter animation: types initial message first, then cycles messages below
  useEffect(() => {
    const showAnimation = shouldShowWaiting();
    const waitingState = getWaitingState();
    const initialMessage = INITIAL_MESSAGES[waitingState] ?? '';

    // Clear any existing animation
    if (animationRef.current) {
      clearTimeout(animationRef.current);
      animationRef.current = null;
    }

    // If no animation needed, clear all text
    if (!showAnimation) {
      setInitialText('');
      initialTextRef.current = '';
      setCyclingText('');
      cyclingTextRef.current = '';
      return;
    }

    // Handle state change - reset animation to start with initial message
    if (runStateRef.current !== waitingState) {
      runStateRef.current = waitingState;
      animationPhaseRef.current = 'typing-initial';
      currentMessageRef.current = getRandomMessage(waitingState);
      initialTextRef.current = '';
      setInitialText('');
      cyclingTextRef.current = '';
      setCyclingText('');
    }

    // Initialize cycling message if not set
    if (!currentMessageRef.current) {
      currentMessageRef.current = getRandomMessage(waitingState);
    }

    const animate = () => {
      const currentMessage = currentMessageRef.current;
      const phase = animationPhaseRef.current;

      let nextDelay = TYPING_SPEED;

      // Phase: typing-initial - type out the initial message first
      if (phase === 'typing-initial') {
        const prev = initialTextRef.current;
        if (prev.length < initialMessage.length) {
          const nextText = initialMessage.slice(0, prev.length + 1);
          initialTextRef.current = nextText;
          setInitialText(nextText);
        } else {
          // Initial message complete, start cycling messages
          animationPhaseRef.current = 'typing';
        }
      }
      // Phase: typing - type out the cycling message
      else if (phase === 'typing') {
        const prev = cyclingTextRef.current;
        if (prev.length < currentMessage.length) {
          const nextText = currentMessage.slice(0, prev.length + 1);
          cyclingTextRef.current = nextText;
          setCyclingText(nextText);
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
      // Phase: deleting - delete cycling message characters
      else if (phase === 'deleting') {
        const prev = cyclingTextRef.current;
        if (prev.length > 0) {
          const nextText = prev.slice(0, -1);
          cyclingTextRef.current = nextText;
          setCyclingText(nextText);
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
  }, [shouldShowWaiting, getWaitingState]);

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
  const showWaitingOverlay = !hasLogs && shouldShowWaiting();
  const showFinalMessage =
    !hasLogs && run && isFinalState(run.state) && !shouldShowWaiting();

  // Determine if we're still typing the initial message (cursor goes there)
  const isTypingInitial = animationPhaseRef.current === 'typing-initial';

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
      <div className="relative min-h-0 overflow-hidden">
        {/* Monaco log viewer - only shows real logs */}
        <div ref={containerRef} className="h-full" />

        {/* Waiting message overlay - completely separate from Monaco */}
        {showWaitingOverlay && (
          <div className="absolute inset-0 overflow-hidden bg-slate-700 p-4 font-mono text-sm text-gray-400">
            {/* Initial message (typed out first, then stays) */}
            <div>
              <span>{initialText}</span>
              {isTypingInitial && (
                <span
                  style={{
                    animation: 'cursor-blink 1.8s ease-in-out infinite',
                  }}
                >
                  ▌
                </span>
              )}
            </div>
            {/* Cycling message with cursor (appears after initial is done) */}
            {!isTypingInitial && (
              <div>
                <span>{cyclingText}</span>
                <span
                  style={{
                    animation: 'cursor-blink 1.8s ease-in-out infinite',
                  }}
                >
                  ▌
                </span>
              </div>
            )}
          </div>
        )}
        {/* Final state message */}
        {showFinalMessage && (
          <div className="absolute inset-0 overflow-hidden bg-slate-700 p-4 font-mono text-sm text-gray-400">
            No logs were received for this run.
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
