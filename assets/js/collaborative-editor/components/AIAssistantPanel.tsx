import { useEffect, useState } from 'react';

import { cn } from '#/utils/cn';

import type { AIAssistantStore } from '../types/ai-assistant';

import { ChatInput } from './ChatInput';
import { SessionList } from './SessionList';

interface AIAssistantPanelProps {
  isOpen: boolean;
  onClose: () => void;
  onNewConversation?: () => void;
  onSessionSelect?: (sessionId: string) => void;
  onSendMessage?: (content: string) => void;
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
   * AI Assistant store for session list
   */
  store?: AIAssistantStore;
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
 * - Escape key to close
 */
export function AIAssistantPanel({
  isOpen,
  onClose,
  onNewConversation,
  onSessionSelect,
  onSendMessage,
  children,
  sessionId,
  messageCount = 0,
  isLoading = false,
  isResizable = false,
  store,
}: AIAssistantPanelProps) {
  // Start with sessions list if no active session
  const [view, setView] = useState<'chat' | 'sessions'>(
    sessionId ? 'chat' : 'sessions'
  );
  const [isMenuOpen, setIsMenuOpen] = useState(false);
  const [isAboutOpen, setIsAboutOpen] = useState(false);

  // When sessionId changes, update view accordingly
  useEffect(() => {
    if (sessionId && view === 'sessions') {
      setView('chat');
    } else if (!sessionId && view === 'chat') {
      setView('sessions');
    }
  }, [sessionId, view]);

  // Handle escape key to close panel
  useEffect(() => {
    const handleEscape = (event: KeyboardEvent) => {
      if (event.key === 'Escape' && isOpen) {
        onClose();
      }
    };

    document.addEventListener('keydown', handleEscape);
    return () => document.removeEventListener('keydown', handleEscape);
  }, [isOpen, onClose]);

  // Load session list when sessions view opens
  useEffect(() => {
    if (view === 'sessions' && store) {
      store.loadSessionList();
    }
  }, [view, store]);

  const handleShowSessions = () => {
    setView('sessions');
    setIsMenuOpen(false);
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

  const handleBackToChat = () => {
    setView('chat');
  };

  const handleNewConversation = () => {
    if (onNewConversation) {
      onNewConversation();
      setView('chat');
    }
  };

  const handleClose = () => {
    // If we're in a chat session, close it and go to sessions list
    if (view === 'chat' && sessionId && store) {
      // Disconnect from current session to clear sessionId
      store.disconnect();
      // Switch to sessions view
      setView('sessions');
    } else {
      // Otherwise, close the entire panel
      onClose();
    }
  };

  // Close menu when clicking outside
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
    <div
      className={cn(
        'h-full flex flex-col overflow-hidden bg-white',
        !isResizable && [
          'flex-none border-l border-gray-200',
          'transition-all duration-300 ease-in-out',
          isOpen ? 'w-[400px]' : 'w-0 border-l-0',
        ]
      )}
      role="dialog"
      aria-modal="false"
      aria-label="AI Assistant"
    >
      {/* Panel Header */}
      <div className="flex-none bg-white shadow-xs border-b border-gray-200">
        <div className="mx-auto sm:px-6 lg:px-8 py-6 flex items-center justify-between h-20 text-sm">
          <div className="flex items-center gap-2 min-w-0 flex-1">
            {view === 'sessions' && (
              <button
                type="button"
                onClick={handleBackToChat}
                className={cn(
                  'inline-flex items-center justify-center',
                  'h-8 w-8 rounded-md',
                  'text-gray-500 hover:text-gray-700 hover:bg-gray-100',
                  'focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-primary-500',
                  'transition-all duration-150'
                )}
                aria-label="Back to chat"
              >
                <span className="hero-arrow-left h-5 w-5" />
              </button>
            )}
            <img src="/images/logo.svg" alt="OpenFn" className="size-6" />
            <div className="min-w-0 flex-1">
              <h2 className="text-base font-semibold text-gray-900">
                {view === 'sessions' ? 'Chat History' : 'Assistant'}
              </h2>
            </div>
          </div>
          <div className="flex items-center gap-2">
            {onNewConversation && sessionId && (
              <button
                type="button"
                onClick={handleNewConversation}
                className="inline-flex items-center gap-1.5 px-2.5 py-1.5
                    text-sm font-medium text-gray-700 bg-white border
                    border-gray-300 rounded-md hover:bg-gray-50
                    focus:outline-none focus:ring-2 focus:ring-offset-2
                    focus:ring-primary-500 transition-colors"
                aria-label="Start new conversation"
              >
                <span className="hero-plus h-5 w-5" />
                New session
              </button>
            )}
            {/* 3-dot vertical menu */}
            {store && (
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
                {/* Dropdown Menu */}
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
                        onClick={handleShowSessions}
                        className={cn(
                          'group flex items-center w-full',
                          'px-4 py-2.5 text-sm font-medium',
                          'text-gray-700 hover:bg-gray-50',
                          'transition-colors duration-150',
                          view === 'sessions' &&
                            'bg-primary-50 text-primary-700'
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
                        <span className="flex-1 text-left">Chat History</span>
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
                        <span className="flex-1">
                          OpenFn Responsible AI Policy
                        </span>
                        <span className="hero-arrow-top-right-on-square h-4 w-4 ml-2 text-gray-400 group-hover:text-gray-500" />
                      </a>
                    </div>
                  </div>
                )}
              </div>
            )}
            <button
              type="button"
              onClick={handleClose}
              className={cn(
                'rounded-md text-gray-400 hover:text-gray-600',
                'hover:bg-gray-100 transition-colors',
                'focus:outline-none focus:ring-2 focus:ring-primary-500',
                'flex-shrink-0 p-1.5'
              )}
              aria-label={
                view === 'chat' && sessionId
                  ? 'Close session'
                  : 'Close AI Assistant'
              }
            >
              <span className="hero-x-mark h-5 w-5" />
            </button>
          </div>
        </div>
      </div>

      {/* Panel Content - Messages or Sessions */}
      <div className="flex-1 overflow-hidden bg-white">
        {view === 'chat' ? (
          <div className="h-full overflow-y-auto">{children}</div>
        ) : (
          store && (
            <SessionList
              store={store}
              onSessionSelect={handleSessionSelect}
              currentSessionId={sessionId}
            />
          )
        )}
      </div>

      {/* Chat Input - Always visible at bottom */}
      <ChatInput onSendMessage={onSendMessage} isLoading={isLoading} />

      {/* About AI Assistant Modal */}
      {isAboutOpen && (
        <div className="absolute inset-0 z-50 bg-white flex flex-col">
          {/* Modal Header */}
          <div className="flex-none bg-gray-50 px-4 py-3 flex items-center justify-between border-b border-gray-200">
            <h3 className="font-medium text-gray-900">
              About the AI Assistant
            </h3>
            <button
              type="button"
              onClick={() => setIsAboutOpen(false)}
              className={cn(
                'rounded-md text-gray-400 hover:text-gray-600',
                'hover:bg-gray-100 transition-colors',
                'focus:outline-none focus:ring-2 focus:ring-primary-500',
                'p-1'
              )}
              aria-label="Close"
            >
              <span className="hero-x-mark h-5 w-5" />
            </button>
          </div>

          {/* Modal Content */}
          <div className="flex-1 overflow-y-auto p-4 text-sm space-y-4">
            <p>
              The OpenFn AI Assistant provides a chat interface with an AI Model
              to help you build workflows. It can:
            </p>
            <ul className="list-disc list-inside pl-4 space-y-1">
              <li>Create a workflow template for you</li>
              <li>Draft job code for you</li>
              <li>Explain adaptor functions and how they are used</li>
              <li>Proofread and debug your job code</li>
              <li>Help understand why you are seeing an error</li>
            </ul>
            <p>
              Messages are saved unencrypted to the OpenFn database and may be
              monitored for quality control.
            </p>

            <h4 className="font-semibold text-gray-900 pt-2">Usage Tips</h4>
            <ul className="list-disc list-inside pl-4 space-y-1">
              <li>
                All chats are saved to the Project and can be viewed at any time
              </li>
              <li>
                Press{' '}
                <code className="px-1 py-0.5 bg-gray-100 rounded text-xs">
                  CTRL + ENTER
                </code>{' '}
                to send a message
              </li>
              <li>
                The Assistant can see your code and knows about OpenFn - just
                ask a question and don't worry too much about giving it context
              </li>
            </ul>

            <h4 className="font-semibold text-gray-900 pt-2">
              Using The Assistant Safely
            </h4>
            <p>
              The AI assistant uses a third-party model to process chat
              messages. Messages may be saved on OpenFn and Anthropic servers.
            </p>
            <p>
              Although we are constantly monitoring and improving the
              performance of the model, the Assistant can sometimes provide
              incorrect or misleading responses. You should consider the
              responses critically and verify the output where possible.
            </p>
            <p>
              Remember that all responses are generated by an algorithm, and you
              are responsible for how its output is used.
            </p>
            <p>
              Do not deploy autogenerated code in production environments
              without thorough testing.
            </p>
            <p>
              Do not include real user data, personally identifiable
              information, or sensitive business data in your queries.
            </p>

            <h4 className="font-semibold text-gray-900 pt-2">How it works</h4>
            <p>
              The Assistant uses Claude Sonnet 3.7, by{' '}
              <a
                href="https://www.anthropic.com/"
                target="_blank"
                rel="noopener noreferrer"
                className="text-primary-600 hover:text-primary-700"
              >
                Anthropic
              </a>
              , a Large Language Model (LLM) designed with a commitment to
              safety and privacy.
            </p>
            <p>
              Chat is saved with the Step and shared with all users with access
              to the Workflow. All collaborators within a project can see
              questions asked by other users.
            </p>
            <p>
              We include your step code in all queries sent to Claude, including
              some basic documentation, ensuring the model is well informed and
              can see what you can see. We do not send your input data, output
              data or logs to Anthropic.
            </p>
            <p>
              The Assistant uses a mixture of hand-written prompts and
              information from{' '}
              <a
                href="https://docs.openfn.org"
                target="_blank"
                rel="noopener noreferrer"
                className="text-primary-600 hover:text-primary-700"
              >
                docs.openfn.org
              </a>{' '}
              to inform its responses.
            </p>

            <h4 className="font-semibold text-gray-900 pt-2">
              Responsible AI Policy
            </h4>
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
            </p>
          </div>
        </div>
      )}
    </div>
  );
}
