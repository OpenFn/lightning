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
 * - Optional job-specific controls (attach code, attach logs)
 */

interface ChatInputProps {
  onSendMessage?:
    | ((content: string, options?: MessageOptions) => void)
    | undefined;
  isLoading?: boolean | undefined;
  /** Show job-specific controls (attach code, attach logs) */
  showJobControls?: boolean | undefined;
  /** Storage key for persisting checkbox preferences */
  storageKey?: string | undefined;
}

interface MessageOptions {
  attach_code?: boolean;
  attach_logs?: boolean;
}

export function ChatInput({
  onSendMessage,
  isLoading = false,
  showJobControls = false,
  storageKey,
}: ChatInputProps) {
  const [input, setInput] = useState('');

  // Initialize checkbox state from localStorage if available
  // Default: attach_code = true, attach_logs = false
  const [attachCode, setAttachCode] = useState(() => {
    if (!storageKey) {
      console.log(
        '[ChatInput] No storageKey, using default attach_code = true'
      );
      return true;
    }
    try {
      const key = `${storageKey}:attach-code`;
      const saved = localStorage.getItem(key);
      console.log('[ChatInput] Loading attach_code from localStorage', {
        key,
        saved,
        willUse: saved === null ? true : saved === 'true',
      });
      // If not set yet, default to true
      return saved === null ? true : saved === 'true';
    } catch (error) {
      console.error(
        '[ChatInput] Error loading attach_code from localStorage',
        error
      );
      return true;
    }
  });

  const [attachLogs, setAttachLogs] = useState(() => {
    if (!storageKey) {
      console.log(
        '[ChatInput] No storageKey, using default attach_logs = false'
      );
      return false;
    }
    try {
      const key = `${storageKey}:attach-logs`;
      const saved = localStorage.getItem(key);
      console.log('[ChatInput] Loading attach_logs from localStorage', {
        key,
        saved,
        willUse: saved === 'true',
      });
      return saved === 'true';
    } catch (error) {
      console.error(
        '[ChatInput] Error loading attach_logs from localStorage',
        error
      );
      return false;
    }
  });

  const textareaRef = useRef<HTMLTextAreaElement>(null);
  const isLoadingFromStorageRef = useRef(false);

  // Auto-resize textarea as content changes
  useEffect(() => {
    const textarea = textareaRef.current;
    if (!textarea) return;

    // Reset height to auto to get the correct scrollHeight
    textarea.style.height = 'auto';
    // Set height to scrollHeight (content height)
    textarea.style.height = `${textarea.scrollHeight}px`;
  }, [input]);

  // Load checkbox preferences from localStorage when storageKey becomes available
  useEffect(() => {
    if (!storageKey) return;

    console.log('[ChatInput] storageKey changed, loading preferences', {
      storageKey,
    });
    isLoadingFromStorageRef.current = true;

    try {
      const codeKey = `${storageKey}:attach-code`;
      const savedCode = localStorage.getItem(codeKey);
      const codeValue = savedCode === null ? true : savedCode === 'true';
      console.log('[ChatInput] Loaded attach_code from localStorage', {
        key: codeKey,
        saved: savedCode,
        value: codeValue,
      });
      setAttachCode(codeValue);
    } catch (error) {
      console.error('[ChatInput] Error loading attach_code', error);
    }

    try {
      const logsKey = `${storageKey}:attach-logs`;
      const savedLogs = localStorage.getItem(logsKey);
      const logsValue = savedLogs === 'true';
      console.log('[ChatInput] Loaded attach_logs from localStorage', {
        key: logsKey,
        saved: savedLogs,
        value: logsValue,
      });
      setAttachLogs(logsValue);
    } catch (error) {
      console.error('[ChatInput] Error loading attach_logs', error);
    }

    // Reset flag after state updates have been applied
    setTimeout(() => {
      isLoadingFromStorageRef.current = false;
    }, 0);
  }, [storageKey]);

  // Persist attachCode to localStorage when it changes
  useEffect(() => {
    if (!storageKey) return;
    if (isLoadingFromStorageRef.current) return; // Skip during load
    try {
      console.log('[ChatInput] Saving attach_code to localStorage', {
        key: `${storageKey}:attach-code`,
        value: attachCode,
      });
      localStorage.setItem(`${storageKey}:attach-code`, String(attachCode));
    } catch (error) {
      console.error('Failed to save attach-code preference', error);
    }
  }, [attachCode, storageKey]);

  // Persist attachLogs to localStorage when it changes
  useEffect(() => {
    if (!storageKey) return;
    if (isLoadingFromStorageRef.current) return; // Skip during load
    try {
      console.log('[ChatInput] Saving attach_logs to localStorage', {
        key: `${storageKey}:attach-logs`,
        value: attachLogs,
      });
      localStorage.setItem(`${storageKey}:attach-logs`, String(attachLogs));
    } catch (error) {
      console.error('Failed to save attach-logs preference', error);
    }
  }, [attachLogs, storageKey]);

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    if (!input.trim() || isLoading) return;

    const options: MessageOptions = {};
    if (showJobControls) {
      options.attach_code = attachCode;
      options.attach_logs = attachLogs;
    }

    onSendMessage?.(input.trim(), options);
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
                {/* Left side - Job controls or Warning */}
                <div className="flex items-center gap-3">
                  {showJobControls ? (
                    <>
                      {/* Attach Code Checkbox */}
                      <label className="flex items-center gap-1.5 cursor-pointer group">
                        <input
                          type="checkbox"
                          checked={attachCode}
                          onChange={e => setAttachCode(e.target.checked)}
                          className="w-3.5 h-3.5 rounded border-gray-300 text-primary-600
                            focus:ring-primary-500 focus:ring-offset-0 cursor-pointer"
                        />
                        <span className="text-[11px] font-medium text-gray-600 group-hover:text-gray-900">
                          Include job code
                        </span>
                      </label>

                      {/* Attach Logs Checkbox */}
                      <label className="flex items-center gap-1.5 cursor-pointer group">
                        <input
                          type="checkbox"
                          checked={attachLogs}
                          onChange={e => setAttachLogs(e.target.checked)}
                          className="w-3.5 h-3.5 rounded border-gray-300 text-primary-600
                            focus:ring-primary-500 focus:ring-offset-0 cursor-pointer"
                        />
                        <span className="text-[11px] font-medium text-gray-600 group-hover:text-gray-900">
                          Include run logs
                        </span>
                      </label>
                    </>
                  ) : (
                    /* Warning */
                    <div className="flex items-center gap-1.5">
                      <span className="hero-shield-exclamation h-3.5 w-3.5 text-amber-500" />
                      <span className="text-[11px] font-medium text-gray-600">
                        Do not include PII or sensitive data
                      </span>
                    </div>
                  )}
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
