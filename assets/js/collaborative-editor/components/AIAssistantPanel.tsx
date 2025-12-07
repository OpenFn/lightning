import { useEffect, useState, useRef } from 'react';

import { cn } from '#/utils/cn';

import {
  useAIStorageKey,
  useAISessionType,
  useAIJobCodeContext,
  useAIHasSessionContext,
  useAIHasCompletedSessionLoad,
  useAISessionListCommands,
} from '../hooks/useAIAssistant';
import { useSelectedStepId } from '../hooks/useHistory';

import { ChatInput } from './ChatInput';
import { DisclaimerScreen } from './DisclaimerScreen';
import { SessionList } from './SessionList';
import { Tooltip } from './Tooltip';

interface AIAssistantPanelProps {
  isOpen: boolean;
  onClose: () => void;
  onNewConversation?: () => void;
  onSessionSelect?: (sessionId: string) => void;
  onShowSessions?: () => void;
  onSendMessage?: (content: string, options?: MessageOptions) => void;
  children?: React.ReactNode;
  sessionId?: string | null;
  messageCount?: number;
  isLoading?: boolean;
  /**
   * Whether this panel is inside a resizable Panel component (IDE mode)
   * or standalone with fixed width (Canvas mode)
   */
  isResizable?: boolean;
  /**
   * Current session type (job_code or workflow_template)
   * Used to show mode-specific UI
   */
  sessionType?: 'job_code' | 'workflow_template' | null;
  /**
   * Load sessions via Phoenix Channel (preferred over HTTP)
   */
  loadSessions?: (offset?: number, limit?: number) => Promise<void>;
  /**
   * Trigger value that when changed, re-focuses the chat input
   */
  focusTrigger?: number;
  /**
   * Whether to show the disclaimer screen overlay
   */
  showDisclaimer?: boolean;
  /**
   * Handler for when user accepts the disclaimer
   */
  onAcceptDisclaimer?: () => void;
  /**
   * Connection state for showing loading screen
   */
  connectionState?: 'disconnected' | 'connecting' | 'connected' | 'error';
}

interface MessageOptions {
  attach_code?: boolean;
  attach_logs?: boolean;
  attach_io_data?: boolean;
  step_id?: string;
}

/**
 * AI Assistant Panel Component
 *
 * Full-height right-side panel similar to Google Cloud Assistant.
 * Pushes content to the left when open (not an overlay).
 *
 * Design Specifications:
 * - Positioned on the right side, pushes content left when open
 * - Full viewport height
 * - Resizable in IDE mode, fixed 400px width in Canvas mode
 * - Smooth slide-in/out transitions
 * - No backdrop overlay (content pushes instead of overlaying)
 */
export function AIAssistantPanel({
  isOpen,
  onClose,
  onNewConversation: _onNewConversation,
  onSessionSelect,
  onShowSessions,
  onSendMessage,
  children,
  sessionId,
  messageCount: _messageCount = 0,
  isLoading = false,
  isResizable = false,
  sessionType = null,
  loadSessions: _loadSessions,
  focusTrigger,
  showDisclaimer = false,
  onAcceptDisclaimer,
  connectionState = 'connected',
}: AIAssistantPanelProps) {
  const [view, setView] = useState<'chat' | 'sessions'>(
    sessionId ? 'chat' : 'sessions'
  );
  const [isMenuOpen, setIsMenuOpen] = useState(false);
  const [isAboutOpen, setIsAboutOpen] = useState(false);

  const [internalFocusTrigger, setInternalFocusTrigger] = useState(0);
  const prevViewRef = useRef(view);

  // Use hooks to get state from AI Assistant store
  const storageKey = useAIStorageKey();
  const storeSessionType = useAISessionType();
  const jobCodeContext = useAIJobCodeContext();
  const hasSessionContext = useAIHasSessionContext();
  const hasCompletedSessionLoad = useAIHasCompletedSessionLoad();
  const { loadSessionList } = useAISessionListCommands();
  const selectedStepId = useSelectedStepId();

  useEffect(() => {
    if (prevViewRef.current !== view) {
      setInternalFocusTrigger(prev => prev + 1);
    }
    prevViewRef.current = view;
  }, [view]);

  useEffect(() => {
    if (sessionId && view === 'sessions') {
      setView('chat');
    } else if (!sessionId && view === 'chat') {
      setView('sessions');
    }
  }, [sessionId, view]);

  const placeholderText =
    sessionType === 'job_code'
      ? 'Ask me anything about this job...'
      : sessionType === 'workflow_template'
        ? 'Ask me anything about this workflow...'
        : 'Ask me anything...';

  const disabledMessage =
    view === 'sessions' && (!hasSessionContext || !hasCompletedSessionLoad)
      ? 'Loading conversations...'
      : view === 'chat' && connectionState !== 'connected'
        ? 'Connecting...'
        : undefined;

  // Load session list when viewing sessions
  useEffect(() => {
    if (!isOpen || view !== 'sessions' || !storeSessionType) return;

    if (!hasSessionContext) {
      return;
    }

    void loadSessionList();
  }, [
    isOpen,
    view,
    storeSessionType,
    jobCodeContext?.job_id,
    hasSessionContext,
    loadSessionList,
  ]);

  // Re-fetch session list when tab becomes visible (handles browser tab sleep)
  useEffect(() => {
    if (!isOpen || view !== 'sessions' || !hasSessionContext) return;

    const handleVisibilityChange = () => {
      if (document.visibilityState === 'visible') {
        void loadSessionList();
      }
    };

    document.addEventListener('visibilitychange', handleVisibilityChange);
    return () => {
      document.removeEventListener('visibilitychange', handleVisibilityChange);
    };
  }, [isOpen, view, hasSessionContext, loadSessionList]);

  const handleShowSessions = () => {
    setView('sessions');
    setIsMenuOpen(false);

    if (onShowSessions) {
      onShowSessions();
    }
  };

  const handleToggleMenu = () => {
    setIsMenuOpen(prev => !prev);
  };

  const handleOpenAbout = () => {
    setIsAboutOpen(true);
    setIsMenuOpen(false);
  };

  const handleSessionSelect = (selectedSessionId: string) => {
    if (onSessionSelect) {
      onSessionSelect(selectedSessionId);
      setView('chat');
    }
  };

  const handleClose = () => {
    if (sessionId) {
      if (onShowSessions) {
        onShowSessions();
      }
    } else {
      onClose();
    }
  };

  useEffect(() => {
    if (!isMenuOpen) return;

    const handleClickOutside = (event: MouseEvent) => {
      const target = event.target as HTMLElement;
      if (
        !target.closest('[data-menu-trigger]') &&
        !target.closest('[data-menu-content]')
      ) {
        setIsMenuOpen(false);
      }
    };

    document.addEventListener('mousedown', handleClickOutside);
    return () => document.removeEventListener('mousedown', handleClickOutside);
  }, [isMenuOpen]);

  return (
    <aside
      data-testid="ai-assistant-panel"
      data-session-type={sessionType || undefined}
      className={cn(
        'h-full flex flex-col overflow-hidden bg-white relative',
        !isResizable && [
          'flex-none border-l border-gray-200',
          'transition-[width,border] duration-300 ease-in-out',
          isOpen ? 'w-[400px]' : 'w-0 border-l-0',
        ]
      )}
      aria-label="AI Assistant"
    >
      <div className="flex-none bg-white shadow-xs border-b border-gray-200">
        <div className="mx-auto px-6 py-6 flex items-center justify-between h-20 text-sm">
          <div className="flex items-center gap-2 min-w-0 flex-1">
            <img src="/images/logo.svg" alt="OpenFn" className="size-6" />
            <div className="min-w-0 flex-1">
              <div className="flex items-center gap-2">
                <h2 className="text-base font-semibold text-gray-900">
                  Assistant
                </h2>
                {sessionType && (
                  <span
                    className={cn(
                      'inline-flex items-center px-2 py-0.5 rounded text-xs font-medium',
                      sessionType === 'job_code'
                        ? 'bg-blue-100 text-blue-800'
                        : 'bg-purple-100 text-purple-800'
                    )}
                  >
                    {sessionType === 'job_code' ? 'Job' : 'Workflow'}
                  </span>
                )}
              </div>
            </div>
          </div>
          <div className="flex items-center gap-2">
            <div className="relative">
              <button
                type="button"
                onClick={handleToggleMenu}
                data-menu-trigger
                className={cn(
                  'inline-flex items-center justify-center',
                  'h-8 w-8 rounded-md',
                  'text-gray-500 hover:text-gray-700 hover:bg-gray-100',
                  'focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-primary-500',
                  'transition-all duration-150',
                  isMenuOpen && 'bg-gray-100 text-gray-700'
                )}
                aria-label="More options"
                aria-expanded={isMenuOpen}
              >
                <span className="hero-ellipsis-vertical h-5 w-5" />
              </button>
              {isMenuOpen && (
                <div
                  data-menu-content
                  className={cn(
                    'absolute right-0 mt-2 w-64 origin-top-right',
                    'rounded-lg shadow-xl',
                    'bg-white ring-1 ring-gray-900/10',
                    'divide-y divide-gray-100',
                    'z-50',
                    'animate-in fade-in-0 zoom-in-95 duration-100'
                  )}
                >
                  <div className="py-1.5">
                    <button
                      type="button"
                      data-testid="sessions-button"
                      onClick={handleShowSessions}
                      className={cn(
                        'group flex items-center w-full',
                        'px-4 py-2.5 text-sm font-medium',
                        'text-gray-700 hover:bg-gray-50',
                        'transition-colors duration-150',
                        view === 'sessions' && 'bg-primary-50 text-primary-700'
                      )}
                    >
                      <span
                        className={cn(
                          'hero-chat-bubble-left-right h-5 w-5 mr-3',
                          view === 'sessions'
                            ? 'text-primary-600'
                            : 'text-gray-400 group-hover:text-gray-500'
                        )}
                      />
                      <span className="flex-1 text-left">Conversations</span>
                      {view === 'sessions' && (
                        <span className="hero-check h-4 w-4 text-primary-600 ml-2" />
                      )}
                    </button>
                  </div>
                  <div className="py-1.5">
                    <button
                      type="button"
                      onClick={handleOpenAbout}
                      className={cn(
                        'group flex items-center w-full',
                        'px-4 py-2.5 text-sm',
                        'text-gray-700 hover:bg-gray-50',
                        'transition-colors duration-150'
                      )}
                    >
                      <span className="hero-information-circle h-5 w-5 mr-3 text-gray-400 group-hover:text-gray-500" />
                      <span>About the AI Assistant</span>
                    </button>
                    <a
                      href="https://www.openfn.org/ai"
                      target="_blank"
                      rel="noopener noreferrer"
                      className={cn(
                        'group flex items-center w-full',
                        'px-4 py-2.5 text-sm',
                        'text-gray-700 hover:bg-gray-50',
                        'transition-colors duration-150'
                      )}
                    >
                      <span className="hero-document-text h-5 w-5 mr-3 text-gray-400 group-hover:text-gray-500" />
                      <span className="flex-1">Responsible AI Policy</span>
                      <span className="hero-arrow-top-right-on-square h-4 w-4 ml-2 text-gray-400 group-hover:text-gray-500" />
                    </a>
                  </div>
                </div>
              )}
            </div>
            <Tooltip
              content={sessionId ? 'Close current session' : 'Close assistant'}
            >
              <button
                type="button"
                onClick={handleClose}
                className={cn(
                  'inline-flex items-center justify-center',
                  'h-8 w-8 rounded-md',
                  'text-gray-400 hover:text-gray-600 hover:bg-gray-100',
                  'focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-primary-500',
                  'transition-all duration-150',
                  'flex-shrink-0'
                )}
                aria-label={
                  sessionId ? 'Close current session' : 'Close assistant'
                }
              >
                <span className="hero-x-mark h-5 w-5" />
              </button>
            </Tooltip>
          </div>
        </div>
      </div>

      {/* Panel Content - Messages or Sessions */}
      <div className="flex-1 overflow-hidden bg-white">
        {view === 'chat' ? (
          <div className="h-full overflow-y-auto">{children}</div>
        ) : (
          <SessionList
            onSessionSelect={handleSessionSelect}
            currentSessionId={sessionId}
          />
        )}
      </div>

      <ChatInput
        onSendMessage={onSendMessage}
        isLoading={
          isLoading ||
          (view === 'chat' && connectionState !== 'connected') ||
          (view === 'sessions' &&
            (!hasSessionContext || !hasCompletedSessionLoad))
        }
        showJobControls={sessionType === 'job_code'}
        storageKey={storageKey}
        enableAutoFocus={
          isOpen &&
          !isAboutOpen &&
          (view === 'sessions' || connectionState === 'connected')
        }
        focusTrigger={(focusTrigger ?? 0) + internalFocusTrigger}
        placeholder={placeholderText}
        disabledMessage={disabledMessage}
        selectedStepId={selectedStepId}
      />

      {/* About AI Assistant Modal */}
      {isAboutOpen && (
        <div
          className="absolute inset-0 z-50 bg-white flex flex-col"
          role="dialog"
          aria-modal="true"
          aria-labelledby="about-modal-title"
        >
          {/* Modal Header */}
          <div className="flex-none bg-white shadow-xs border-b border-gray-200">
            <div className="mx-auto px-6 py-6 flex items-center justify-between h-20 text-sm">
              <h3
                id="about-modal-title"
                className="text-base font-semibold text-gray-900"
              >
                About the AI Assistant
              </h3>
              <button
                type="button"
                onClick={() => setIsAboutOpen(false)}
                className={cn(
                  'inline-flex items-center justify-center',
                  'h-8 w-8 rounded-md',
                  'text-gray-400 hover:text-gray-600 hover:bg-gray-100',
                  'focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-primary-500',
                  'transition-all duration-150'
                )}
                aria-label="Close"
              >
                <span className="hero-x-mark h-5 w-5" />
              </button>
            </div>
          </div>

          {/* Modal Content */}
          <div className="flex-1 overflow-y-auto px-6 py-4 text-sm space-y-4">
            <p>
              The OpenFn AI Assistant helps you build workflows and write job
              code. It can:
            </p>
            <ul className="list-disc list-inside pl-4 space-y-1">
              <li>Generate complete workflow templates</li>
              <li>Write and explain job code for any adaptor</li>
              <li>Debug errors and explain what went wrong</li>
              <li>Answer questions about OpenFn and adaptors</li>
              <li>Suggest improvements to your code</li>
            </ul>
            <p className="text-gray-600">
              Messages are saved unencrypted to the OpenFn database and may be
              monitored for quality control.
            </p>

            <h4 className="font-semibold text-gray-900 pt-2">Usage Tips</h4>
            <ul className="list-disc list-inside pl-4 space-y-1">
              <li>
                Chat sessions are saved to your project and can be revisited
                anytime
              </li>
              <li>
                Sessions are separated by context - job sessions and workflow
                sessions are kept separate
              </li>
              <li>
                Press{' '}
                <code className="px-1 py-0.5 bg-gray-100 rounded text-xs font-mono">
                  Enter
                </code>{' '}
                to send,{' '}
                <code className="px-1 py-0.5 bg-gray-100 rounded text-xs font-mono">
                  Shift + Enter
                </code>{' '}
                for a new line
              </li>
              <li>
                For jobs, you can choose to include your code and run logs with
                each message
              </li>
              <li>
                Generated workflows appear as artifacts with Apply and Copy
                buttons
              </li>
              <li>
                Generated job code appears as artifacts with Add and Copy
                buttons
              </li>
            </ul>

            <h4 className="font-semibold text-gray-900 pt-2">
              Using The Assistant Safely
            </h4>
            <p>
              The AI assistant uses Claude by Anthropic, a third-party AI model.
              Messages are saved on OpenFn and Anthropic servers.
            </p>
            <p>
              Although we continuously monitor and improve the model, the
              Assistant can sometimes provide incorrect or misleading responses.
              Always review and verify the output.
            </p>
            <p>
              Remember that all responses are generated by an algorithm. You are
              responsible for how its output is used.
            </p>
            <p>
              <strong>Important:</strong> Do not deploy auto-generated code in
              production without thorough testing. Do not include real user
              data, personally identifiable information, or sensitive business
              data in your queries.
            </p>

            <h4 className="font-semibold text-gray-900 pt-2">How it works</h4>
            <p>
              The Assistant uses{' '}
              <a
                href="https://www.anthropic.com/"
                target="_blank"
                rel="noopener noreferrer"
                className="text-primary-600 hover:text-primary-700"
              >
                Claude by Anthropic
              </a>
              , a large language model designed with a commitment to safety and
              privacy.
            </p>
            <p>
              <strong>For workflow sessions:</strong> Your project context is
              automatically included. Generated workflows can be applied
              directly to the canvas with one click.
            </p>
            <p>
              <strong>For job sessions:</strong> You control what the Assistant
              sees. Use the checkboxes to optionally include your job code and
              run logs. By default, job code is included but logs are not.
            </p>
            <p>
              All chat sessions are shared with project collaborators. Everyone
              with access to the workflow or job can see the conversation
              history.
            </p>
            <p>
              The Assistant combines hand-written prompts with information from{' '}
              <a
                href="https://docs.openfn.org"
                target="_blank"
                rel="noopener noreferrer"
                className="text-primary-600 hover:text-primary-700"
              >
                docs.openfn.org
              </a>{' '}
              to provide accurate, context-aware responses.
            </p>

            <h4 className="font-semibold text-gray-900 pt-2">Learn More</h4>
            <p>
              Read about our approach to AI in the{' '}
              <a
                href="https://www.openfn.org/ai"
                target="_blank"
                rel="noopener noreferrer"
                className="text-primary-600 hover:text-primary-700"
              >
                OpenFn Responsible AI Policy
              </a>
              .
            </p>
          </div>
        </div>
      )}

      {connectionState === 'connecting' && (
        <div className="absolute inset-0 z-50 bg-white flex items-center justify-center">
          <div className="flex items-center gap-2 text-gray-600">
            <span className="hero-arrow-path h-5 w-5 animate-spin" />
            <span className="text-sm">
              {sessionId ? 'Loading messages...' : 'Loading conversations...'}
            </span>
          </div>
        </div>
      )}

      {showDisclaimer && (
        <div
          className="absolute inset-0 z-50 bg-white"
          role="dialog"
          aria-modal="true"
          aria-label="AI Assistant Terms"
        >
          <DisclaimerScreen
            onAccept={onAcceptDisclaimer || (() => {})}
            disabled={!onAcceptDisclaimer}
          />
        </div>
      )}
    </aside>
  );
}
