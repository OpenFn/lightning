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

  useEffect(() => {
    const textarea = textareaRef.current;
    if (!textarea) return;

    textarea.style.height = 'auto';
    textarea.style.height = `${textarea.scrollHeight}px`;
  }, [input]);

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    if (!input.trim() || isLoading) return;

    onSendMessage?.(input.trim());
    setInput('');
  };

  const handleKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault();
      handleSubmit(e);
    }
  };

  return (
    <div className="flex flex-col h-full">
      <div className="flex-1 overflow-y-auto">
        {messages.length === 0 && (
          <div className="flex flex-col items-center justify-center h-full text-center px-4">
            <div className="w-16 h-16 rounded-2xl bg-gradient-to-br from-primary-50 to-primary-100 flex items-center justify-center mb-6">
              <img src="/images/logo.svg" alt="OpenFn" className="w-9 h-9" />
            </div>
            <h3 className="text-xl font-semibold text-gray-900 mb-2">
              How can I help you today?
            </h3>
            <p className="text-sm text-gray-600 max-w-md leading-relaxed">
              I can help you build workflows, write job code, debug errors, and
              answer questions about OpenFn adaptors.
            </p>
          </div>
        )}

        {messages.map((message, index) => (
          <div
            key={message.id}
            className={cn(
              'group px-6 py-4',
              message.role === 'assistant' ? 'bg-gray-50/50' : 'bg-white'
            )}
          >
            <div className="max-w-3xl mx-auto">
              {message.role === 'assistant' ? (
                <div>
                  <div className="space-y-3">
                    <div className="text-[15px] text-gray-900 leading-7 whitespace-pre-wrap">
                      {message.content}
                    </div>

                    {message.code && (
                      <div className="rounded-lg overflow-hidden border border-gray-200 bg-white">
                        <div className="px-4 py-2 bg-gray-50 border-b border-gray-200 flex items-center justify-between">
                          <span className="text-xs font-medium text-gray-700">
                            Workflow YAML
                          </span>
                          <button
                            type="button"
                            className="text-xs text-gray-600 hover:text-gray-900 font-medium transition-colors"
                          >
                            Copy
                          </button>
                        </div>
                        <pre className="p-4 text-xs text-gray-900 overflow-x-auto font-mono leading-relaxed">
                          <code>{message.code}</code>
                        </pre>
                      </div>
                    )}

                    {message.status === 'error' && (
                      <div className="flex items-center gap-2 px-3 py-2 rounded-lg bg-red-50 border border-red-200">
                        <span className="hero-exclamation-circle h-4 w-4 text-red-600 flex-shrink-0" />
                        <span className="text-sm text-red-700">
                          Failed to send message. Please try again.
                        </span>
                      </div>
                    )}

                    {message.status === 'processing' && (
                      <div className="flex items-center gap-2 text-gray-600">
                        <div className="flex items-center gap-1">
                          <span className="inline-block w-1.5 h-1.5 bg-gray-400 rounded-full animate-bounce" />
                          <span className="inline-block w-1.5 h-1.5 bg-gray-400 rounded-full animate-bounce [animation-delay:0.15s]" />
                          <span className="inline-block w-1.5 h-1.5 bg-gray-400 rounded-full animate-bounce [animation-delay:0.3s]" />
                        </div>
                      </div>
                    )}
                  </div>
                </div>
              ) : (
                <div className="flex justify-end">
                  <div className="flex flex-col items-end max-w-[85%]">
                    <div className="rounded-2xl bg-gray-100 border border-gray-200 px-4 py-3">
                      <div className="text-[15px] text-gray-900 leading-6 whitespace-pre-wrap">
                        {message.content}
                      </div>
                    </div>

                    {message.status === 'error' && (
                      <div className="flex items-center gap-2 mt-2 px-3 py-1.5 rounded-lg bg-red-50 border border-red-200">
                        <span className="hero-exclamation-circle h-3.5 w-3.5 text-red-600" />
                        <span className="text-xs text-red-700">
                          Failed to send
                        </span>
                      </div>
                    )}
                  </div>
                </div>
              )}
            </div>
          </div>
        ))}
      </div>

      <div className="flex-none border-t border-gray-200 bg-white">
        <div className="py-4 px-4">
          <form onSubmit={handleSubmit}>
            <div className="relative">
              <div
                className={cn(
                  'rounded-xl border-2 transition-all duration-200',
                  'bg-white',
                  input.trim()
                    ? 'border-primary-300'
                    : 'border-gray-200 hover:border-gray-300'
                )}
              >
                <textarea
                  ref={textareaRef}
                  value={input}
                  onChange={e => setInput(e.target.value)}
                  onKeyDown={handleKeyDown}
                  placeholder="Message Assistant..."
                  disabled={isLoading}
                  rows={1}
                  className={cn(
                    'block w-full px-4 py-3 bg-transparent resize-none',
                    'text-[15px] text-gray-900 placeholder:text-gray-400',
                    'border-0 outline-none focus:outline-none focus:ring-0',
                    'disabled:text-gray-400 disabled:cursor-not-allowed'
                  )}
                  style={{
                    minHeight: '52px',
                    maxHeight: '200px',
                    overflow: 'hidden',
                    overflowY: 'auto',
                  }}
                />

                <div className="flex items-center justify-between px-3 py-2 border-t border-gray-100">
                  <div className="flex items-center gap-1.5">
                    <span className="hero-shield-exclamation h-3.5 w-3.5 text-amber-500" />
                    <span className="text-[11px] font-medium text-gray-600">
                      Do not include PII or sensitive data
                    </span>
                  </div>

                  <button
                    type="submit"
                    disabled={!input.trim() || isLoading}
                    className={cn(
                      'inline-flex items-center justify-center',
                      'h-7 w-7 rounded-lg',
                      'transition-all duration-200',
                      'focus:outline-none focus:ring-2 focus:ring-offset-2',
                      input.trim() && !isLoading
                        ? 'bg-primary-600 hover:bg-primary-700 text-white focus:ring-primary-500'
                        : 'bg-gray-100 text-gray-400 cursor-not-allowed'
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

              <div className="mt-2 text-center">
                <span className="text-[11px] text-gray-500">
                  Press{' '}
                  <kbd className="px-1 py-0.5 bg-gray-100 rounded text-[10px] font-medium border border-gray-200">
                    Enter
                  </kbd>{' '}
                  to send,{' '}
                  <kbd className="px-1 py-0.5 bg-gray-100 rounded text-[10px] font-medium border border-gray-200">
                    Shift + Enter
                  </kbd>{' '}
                  for new line
                </span>
              </div>
            </div>
          </form>
        </div>
      </div>
    </div>
  );
}
