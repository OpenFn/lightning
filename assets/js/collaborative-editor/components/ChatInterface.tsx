import { useState } from 'react';

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
      <div className="flex-none border-t border-gray-200 p-4">
        <form onSubmit={handleSubmit} className="flex gap-2">
          <textarea
            value={input}
            onChange={e => setInput(e.target.value)}
            onKeyDown={handleKeyDown}
            placeholder="Ask me anything..."
            disabled={isLoading}
            rows={1}
            className={cn(
              'flex-1 resize-none rounded-lg border border-gray-300 px-3 py-2',
              'text-sm placeholder:text-gray-400',
              'focus:outline-none focus:ring-2 focus:ring-primary-500 focus:border-transparent',
              'disabled:bg-gray-50 disabled:text-gray-500 disabled:cursor-not-allowed',
              'max-h-32 overflow-y-auto'
            )}
            style={{
              minHeight: '40px',
              height: 'auto',
            }}
          />
          <button
            type="submit"
            disabled={!input.trim() || isLoading}
            className={cn(
              'flex-shrink-0 rounded-lg px-4 py-2',
              'text-sm font-semibold text-white',
              'bg-primary-600 hover:bg-primary-500',
              'focus:outline-none focus:ring-2 focus:ring-primary-500 focus:ring-offset-2',
              'disabled:bg-gray-300 disabled:cursor-not-allowed disabled:hover:bg-gray-300',
              'transition-colors'
            )}
          >
            {isLoading ? (
              <span className="hero-arrow-path size-5 animate-spin" />
            ) : (
              <span className="hero-paper-airplane size-5" />
            )}
          </button>
        </form>
        <p className="mt-2 text-xs text-gray-500">
          Press{' '}
          <kbd className="px-1 py-0.5 bg-gray-100 border border-gray-300 rounded text-xs">
            Enter
          </kbd>{' '}
          to send,{' '}
          <kbd className="px-1 py-0.5 bg-gray-100 border border-gray-300 rounded text-xs">
            Shift+Enter
          </kbd>{' '}
          for new line
        </p>
      </div>
    </div>
  );
}
