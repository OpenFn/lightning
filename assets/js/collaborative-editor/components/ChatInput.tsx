import { useEffect, useRef, useState } from 'react';

import { cn } from '#/utils/cn';

import { Tooltip } from './Tooltip';

interface ChatInputProps {
  onSendMessage?:
    | ((content: string, options?: MessageOptions) => void)
    | undefined;
  isLoading?: boolean | undefined;
  /** Show job-specific controls (attach code, attach logs) */
  showJobControls?: boolean | undefined;
  /** Storage key for persisting checkbox preferences */
  storageKey?: string | undefined;
  /** Enable automatic focus management for the input */
  enableAutoFocus?: boolean | undefined;
  /** Trigger value that when changed, re-focuses the input (e.g., timestamp) */
  focusTrigger?: number | undefined;
  /** Placeholder text for the textarea */
  placeholder?: string | undefined;
  /** Message to show in tooltip when input is disabled */
  disabledMessage?: string | undefined;
}

interface MessageOptions {
  attach_code?: boolean;
  attach_logs?: boolean;
}

const MIN_TEXTAREA_HEIGHT = 52;
const MAX_TEXTAREA_HEIGHT = 200;

export function ChatInput({
  onSendMessage,
  isLoading = false,
  showJobControls = false,
  storageKey,
  enableAutoFocus = false,
  focusTrigger,
  placeholder = 'Ask me anything...',
  disabledMessage,
}: ChatInputProps) {
  const [input, setInput] = useState('');

  const [attachCode, setAttachCode] = useState(() => {
    if (!storageKey) {
      return true;
    }
    try {
      const key = `${storageKey}:attach-code`;
      const saved = localStorage.getItem(key);
      return saved === null ? true : saved === 'true';
    } catch {
      return true;
    }
  });

  const [attachLogs, setAttachLogs] = useState(() => {
    if (!storageKey) {
      return false;
    }
    try {
      const key = `${storageKey}:attach-logs`;
      const saved = localStorage.getItem(key);
      return saved === 'true';
    } catch {
      return false;
    }
  });

  const textareaRef = useRef<HTMLTextAreaElement>(null);
  const isLoadingFromStorageRef = useRef(false);

  useEffect(() => {
    const textarea = textareaRef.current;
    if (!textarea) return;

    textarea.style.height = `${MIN_TEXTAREA_HEIGHT}px`;

    if (input && textarea.scrollHeight > MIN_TEXTAREA_HEIGHT) {
      const newHeight = Math.min(textarea.scrollHeight, MAX_TEXTAREA_HEIGHT);
      textarea.style.height = `${newHeight}px`;
    }
  }, [input]);

  useEffect(() => {
    if (!storageKey) return;

    isLoadingFromStorageRef.current = true;

    try {
      const codeKey = `${storageKey}:attach-code`;
      const savedCode = localStorage.getItem(codeKey);
      const codeValue = savedCode === null ? true : savedCode === 'true';
      setAttachCode(codeValue);
    } catch {
      // Ignore localStorage errors
    }

    try {
      const logsKey = `${storageKey}:attach-logs`;
      const savedLogs = localStorage.getItem(logsKey);
      const logsValue = savedLogs === 'true';
      setAttachLogs(logsValue);
    } catch {
      // Ignore localStorage errors
    }

    setTimeout(() => {
      isLoadingFromStorageRef.current = false;
    }, 0);
  }, [storageKey]);

  useEffect(() => {
    if (!storageKey) return;
    if (isLoadingFromStorageRef.current) return;
    try {
      localStorage.setItem(`${storageKey}:attach-code`, String(attachCode));
    } catch {
      // Ignore localStorage errors
    }
  }, [attachCode, storageKey]);

  useEffect(() => {
    if (!storageKey) return;
    if (isLoadingFromStorageRef.current) return;
    try {
      localStorage.setItem(`${storageKey}:attach-logs`, String(attachLogs));
    } catch {
      // Ignore localStorage errors
    }
  }, [attachLogs, storageKey]);

  useEffect(() => {
    if (enableAutoFocus && textareaRef.current) {
      const timeoutId = setTimeout(() => {
        textareaRef.current?.focus();
      }, 50);
      return () => clearTimeout(timeoutId);
    }
  }, [enableAutoFocus, focusTrigger]);

  const prevIsLoadingRef = useRef(isLoading);
  useEffect(() => {
    if (prevIsLoadingRef.current && !isLoading && enableAutoFocus) {
      textareaRef.current?.focus();
    }
    prevIsLoadingRef.current = isLoading;
  }, [isLoading, enableAutoFocus]);

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
    if (
      e.key === 'Enter' &&
      !e.shiftKey &&
      !e.ctrlKey &&
      !e.metaKey &&
      !e.altKey
    ) {
      e.preventDefault();
      handleSubmit(e);
    }
  };

  return (
    <div className="flex-none border-t border-gray-200 bg-white">
      <div className="py-4 px-4">
        <form onSubmit={handleSubmit}>
          <Tooltip content={isLoading ? disabledMessage : undefined} side="top">
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
                  data-testid="chat-input"
                  value={input}
                  onChange={e => setInput(e.target.value)}
                  onKeyDown={handleKeyDown}
                  placeholder={placeholder}
                  disabled={isLoading}
                  rows={1}
                  className={cn(
                    'block w-full px-4 py-3 bg-transparent resize-none',
                    'text-[15px] text-gray-900 placeholder:text-gray-400',
                    'border-0 outline-none focus:outline-none focus:ring-0',
                    'disabled:text-gray-400 disabled:cursor-not-allowed'
                  )}
                  style={{
                    height: `${MIN_TEXTAREA_HEIGHT}px`,
                    minHeight: `${MIN_TEXTAREA_HEIGHT}px`,
                    maxHeight: `${MAX_TEXTAREA_HEIGHT}px`,
                    overflow: 'hidden',
                    overflowY: 'auto',
                  }}
                />

                <div className="flex items-center justify-between px-3 py-2 border-t border-gray-100">
                  <div className="flex items-center gap-3">
                    {showJobControls ? (
                      <>
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
                      <div className="flex items-center gap-1.5">
                        <span className="hero-shield-exclamation h-3.5 w-3.5 text-amber-500" />
                        <span className="text-[11px] font-medium text-gray-600">
                          Do not include PII or sensitive data
                        </span>
                      </div>
                    )}
                  </div>

                  <button
                    type="submit"
                    data-testid="send-message-button"
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
                      <span
                        className="hero-arrow-path h-4 w-4 animate-spin"
                        data-testid="ai-loading"
                      />
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
          </Tooltip>
        </form>
      </div>
    </div>
  );
}
