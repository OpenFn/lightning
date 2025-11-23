import { useEffect, useRef, useState } from 'react';

import { cn } from '#/utils/cn';

/**
 * ChatInput Component
 *
 * Input form for sending messages to the AI Assistant.
 * Appears at the bottom of the AI Assistant panel in both chat and sessions views.
 *
 * Features:
 * - Auto-resizing textarea
 * - Keyboard shortcuts (Enter to send, Shift+Enter for new line)
 * - Loading states
 * - Warning about sensitive data
 */

interface ChatInputProps {
  onSendMessage?: (content: string) => void | undefined;
  isLoading?: boolean;
}

export function ChatInput({
  onSendMessage,
  isLoading = false,
}: ChatInputProps) {
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
    <div className="flex-none border-t border-gray-200 bg-white">
      <div className="py-4 px-4">
        <form onSubmit={handleSubmit}>
          <div className="relative">
            {/* Textarea Container */}
            <div
              className={cn(
                'rounded-xl border-2 transition-all duration-200',
                'bg-white shadow-sm',
                input.trim()
                  ? 'border-primary-300 shadow-primary-100'
                  : 'border-gray-200 hover:border-gray-300'
              )}
            >
              <textarea
                ref={textareaRef}
                value={input}
                onChange={e => setInput(e.target.value)}
                onKeyDown={handleKeyDown}
                placeholder="Ask me anything..."
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

              {/* Actions Bar */}
              <div className="flex items-center justify-between px-3 py-2 border-t border-gray-100">
                {/* Warning */}
                <div className="flex items-center gap-1.5">
                  <span className="hero-shield-exclamation h-3.5 w-3.5 text-amber-500" />
                  <span className="text-[11px] font-medium text-gray-600">
                    Do not include PII or sensitive data
                  </span>
                </div>

                {/* Send Button */}
                <button
                  type="submit"
                  disabled={!input.trim() || isLoading}
                  className={cn(
                    'inline-flex items-center justify-center',
                    'h-7 w-7 rounded-lg',
                    'transition-all duration-200',
                    'focus:outline-none focus:ring-2 focus:ring-offset-2',
                    input.trim() && !isLoading
                      ? 'bg-primary-600 hover:bg-primary-700 text-white shadow-sm hover:shadow focus:ring-primary-500'
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

            {/* Keyboard Hint */}
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
  );
}
