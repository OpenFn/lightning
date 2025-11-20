import { useEffect, useRef, useState } from 'react';

import { cn } from '#/utils/cn';

/**
 * ChatInterface Component
 *
 * AI Assistant chat interface for conversing with the AI.
 *
 * Features:
 * - Message list with user and assistant messages
 * - Input field for sending messages
 * - Auto-scroll to latest message
 * - Loading states
 * - Error handling
 */

interface Message {
  id: string;
  content: string;
  role: 'user' | 'assistant';
  status: 'pending' | 'processing' | 'success' | 'error' | 'cancelled';
  code?: string;
  inserted_at: string;
}

interface ChatInterfaceProps {
  messages?: Message[];
  onSendMessage?: (content: string) => void;
  isLoading?: boolean;
}

export function ChatInterface({
  messages = [],
  onSendMessage,
  isLoading = false,
}: ChatInterfaceProps) {
  const [input, setInput] = useState('');
  const textareaRef = useRef<HTMLTextAreaElement>(null);

  // Auto-resize textarea as content changes
  useEffect(() => {
    const textarea = textareaRef.current;
    if (!textarea) return;

    // Reset height to auto to get the correct scrollHeight
    textarea.style.height = 'auto';
    // Set height to scrollHeight (content height)
    textarea.style.height = `${textarea.scrollHeight}px`;
  }, [input]);

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    if (!input.trim() || isLoading) return;

    onSendMessage?.(input.trim());
    setInput('');
  };

  const handleKeyDown = (e: React.KeyboardEvent) => {
    // Submit on Enter (without Shift)
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault();
      handleSubmit(e);
    }
  };

  return (
    <div className="flex flex-col h-full bg-white">
      {/* Messages List */}
      <div className="flex-1 overflow-y-auto p-4 space-y-4">
        {messages.length === 0 && (
          <div className="flex flex-col items-center justify-center h-full text-center">
            <span className="hero-chat-bubble-left-right size-12 text-gray-300 mb-4" />
            <h3 className="text-lg font-semibold text-gray-900 mb-2">
              Start a conversation
            </h3>
            <p className="text-sm text-gray-500 max-w-xs">
              Ask me anything about your workflow, jobs, or how to build with
              OpenFn.
            </p>
          </div>
        )}

        {messages.map(message => (
          <div
            key={message.id}
            className={cn(
              'flex gap-3',
              message.role === 'user' ? 'justify-end' : 'justify-start'
            )}
          >
            {message.role === 'assistant' && (
              <div className="flex-shrink-0 w-8 h-8 rounded-full bg-primary-100 flex items-center justify-center">
                <img
                  src="/images/logo.svg"
                  alt="Assistant"
                  className="w-5 h-5"
                />
              </div>
            )}

            <div
              className={cn(
                'max-w-[80%] rounded-lg px-4 py-2',
                message.role === 'user'
                  ? 'bg-primary-600 text-white'
                  : 'bg-gray-100 text-gray-900'
              )}
            >
              <p className="text-sm whitespace-pre-wrap">{message.content}</p>

              {message.code && (
                <pre className="mt-2 p-2 bg-gray-800 text-gray-100 rounded text-xs overflow-x-auto">
                  <code>{message.code}</code>
                </pre>
              )}

              {message.status === 'error' && (
                <div className="mt-2 text-xs text-red-600">
                  Failed to send message
                </div>
              )}

              {message.status === 'processing' && (
                <div className="mt-2 flex items-center gap-1 text-xs text-gray-500">
                  <span className="inline-block w-1 h-1 bg-gray-400 rounded-full animate-bounce" />
                  <span className="inline-block w-1 h-1 bg-gray-400 rounded-full animate-bounce [animation-delay:0.2s]" />
                  <span className="inline-block w-1 h-1 bg-gray-400 rounded-full animate-bounce [animation-delay:0.4s]" />
                </div>
              )}
            </div>

            {message.role === 'user' && (
              <div className="flex-shrink-0 w-8 h-8 rounded-full bg-gray-200 flex items-center justify-center">
                <span className="hero-user size-5 text-gray-600" />
              </div>
            )}
          </div>
        ))}
      </div>

      {/* Input Area */}
      <div className="flex-none px-4 py-3 bg-white border-t border-gray-200">
        <div className="max-w-4xl mx-auto">
          <form onSubmit={handleSubmit} className="relative">
            <div className="flex flex-col rounded-lg ring-1 ring-gray-200 bg-white focus-within:ring-2 focus-within:ring-primary-600 focus-within:ring-offset-1 transition-all duration-200">
              <textarea
                ref={textareaRef}
                value={input}
                onChange={e => setInput(e.target.value)}
                onKeyDown={handleKeyDown}
                placeholder="Message Assistant..."
                disabled={isLoading}
                rows={1}
                className={cn(
                  'block w-full px-4 py-3 bg-transparent resize-none rounded-lg',
                  'text-sm placeholder:text-gray-500',
                  'border-0 outline-none focus:outline-none focus:ring-0',
                  'disabled:text-gray-400 disabled:cursor-not-allowed'
                )}
                style={{
                  minHeight: '44px',
                  maxHeight: '200px',
                  overflow: 'hidden',
                  overflowY: 'auto',
                }}
              />
              <div className="flex items-center justify-between px-2 pt-2 pb-1 border-t border-gray-100">
                <div className="flex items-center gap-4">
                  <div className="flex items-center gap-1.5">
                    <span className="hero-shield-exclamation size-3.5 text-amber-500" />
                    <span className="text-xs font-semibold text-gray-700">
                      Do not paste PII or sensitive data
                    </span>
                  </div>
                  <div className="flex items-center gap-1.5 text-[10px] text-gray-400">
                    <kbd className="px-1 py-0.5 bg-gray-100 rounded font-medium text-gray-600 border border-gray-200">
                      Enter
                    </kbd>
                    <span>to send</span>
                    <span className="text-gray-300">•</span>
                    <kbd className="px-1 py-0.5 bg-gray-100 rounded font-medium text-gray-600 border border-gray-200">
                      Shift+Enter
                    </kbd>
                    <span>for new line</span>
                  </div>
                </div>
                <button
                  type="submit"
                  disabled={!input.trim() || isLoading}
                  className={cn(
                    'p-1.5 rounded-full transition-all duration-200 flex items-center justify-center h-8 w-8',
                    'focus:outline-none',
                    input.trim() && !isLoading
                      ? 'bg-primary-600 hover:bg-primary-700 text-white shadow-sm hover:shadow focus:ring-2 focus:ring-primary-500 focus:ring-offset-2'
                      : 'bg-gray-200 text-gray-400 cursor-not-allowed'
                  )}
                  aria-label={isLoading ? 'Sending...' : 'Send message'}
                >
                  {isLoading ? (
                    <span className="hero-arrow-path h-4 w-4 animate-spin" />
                  ) : (
                    <span className="hero-paper-airplane-solid h-4 w-4" />
                  )}
                </button>
              </div>
            </div>
          </form>
        </div>
      </div>
    </div>
  );
}
