import { useEffect, useRef, useState } from 'react';

import { cn } from '#/utils/cn';

import { Tooltip } from './Tooltip';

interface ChatInputProps {
  onSendMessage?:
    | ((content: string, options?: MessageOptions) => void)
    | undefined;
  isLoading?: boolean | undefined;
  /** Disabled state (separate from loading, e.g., due to limits) */
  isDisabled?: boolean | undefined;
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
  /** Selected step ID for attaching I/O data */
  selectedStepId?: string | null;
  /** Selected run ID for attaching logs */
  selectedRunId?: string | null;
  /** Selected job ID for attaching code */
  selectedJobId?: string | null;
}

interface MessageOptions {
  attach_code?: boolean;
  attach_logs?: boolean;
  attach_io_data?: boolean;
  step_id?: string;
}

const MIN_TEXTAREA_HEIGHT = 52;
const MAX_TEXTAREA_HEIGHT = 200;

export function ChatInput({
  onSendMessage,
  isLoading = false,
  isDisabled = false,
  showJobControls = false,
  storageKey,
  enableAutoFocus = false,
  focusTrigger,
  placeholder = 'Ask me anything...',
  disabledMessage,
  selectedStepId,
  selectedRunId,
  selectedJobId,
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

  const [attachIoData, setAttachIoData] = useState(() => {
    if (!storageKey) {
      return false;
    }
    try {
      const key = `${storageKey}:attach-io-data`;
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

    try {
      const ioDataKey = `${storageKey}:attach-io-data`;
      const savedIoData = localStorage.getItem(ioDataKey);
      const ioDataValue = savedIoData === 'true';
      setAttachIoData(ioDataValue);
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
    if (!storageKey) return;
    if (isLoadingFromStorageRef.current) return;
    try {
      localStorage.setItem(
        `${storageKey}:attach-io-data`,
        String(attachIoData)
      );
    } catch {
      // Ignore localStorage errors
    }
  }, [attachIoData, storageKey]);

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
    if (!input.trim() || isLoading || isDisabled) return;

    const options: MessageOptions = {};
    if (showJobControls) {
      if (selectedRunId) {
        options.attach_logs = attachLogs;
      }
      if (selectedJobId) {
        options.attach_code = attachCode;
      }
      if (selectedStepId) {
        options.attach_io_data = attachIoData;
        options.step_id = selectedStepId;
      }
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
          <Tooltip
            content={isLoading || isDisabled ? disabledMessage : undefined}
            side="top"
          >
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
                  disabled={isLoading || isDisabled}
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
                        <Tooltip
                          content={
                            selectedJobId
                              ? undefined
                              : 'Select a job to include code'
                          }
                          side="top"
                        >
                          <label
                            className={cn(
                              'flex items-center gap-1.5 group',
                              selectedJobId
                                ? 'cursor-pointer'
                                : 'cursor-not-allowed opacity-50'
                            )}
                          >
                            <input
                              type="checkbox"
                              // NOTE: Regardless of preferences, we show it
                              // unchecked if no job is selected because code
                              // can't be sent without a job
                              checked={attachCode && !!selectedJobId}
                              onChange={e => setAttachCode(e.target.checked)}
                              disabled={!selectedJobId}
                              className={cn(
                                'w-3.5 h-3.5 rounded border-gray-300 text-primary-600',
                                'focus:ring-primary-500 focus:ring-offset-0',
                                selectedJobId
                                  ? 'cursor-pointer'
                                  : 'cursor-not-allowed'
                              )}
                            />
                            <span
                              className={cn(
                                'text-[11px] font-medium',
                                selectedJobId
                                  ? 'text-gray-600 group-hover:text-gray-900'
                                  : 'text-gray-400'
                              )}
                            >
                              Send code
                            </span>
                          </label>
                        </Tooltip>

                        <Tooltip
                          content={
                            selectedRunId
                              ? undefined
                              : 'Select a run to include logs'
                          }
                          side="top"
                        >
                          <label
                            className={cn(
                              'flex items-center gap-1.5 group',
                              selectedRunId
                                ? 'cursor-pointer'
                                : 'cursor-not-allowed opacity-50'
                            )}
                          >
                            <input
                              type="checkbox"
                              // NOTE: Regardless of preferences, we show it
                              // unchecked if no run is selected because logs
                              // can't be sent without a run
                              checked={attachLogs && !!selectedRunId}
                              onChange={e => setAttachLogs(e.target.checked)}
                              disabled={!selectedRunId}
                              className={cn(
                                'w-3.5 h-3.5 rounded border-gray-300 text-primary-600',
                                'focus:ring-primary-500 focus:ring-offset-0',
                                selectedRunId
                                  ? 'cursor-pointer'
                                  : 'cursor-not-allowed'
                              )}
                            />
                            <span
                              className={cn(
                                'text-[11px] font-medium',
                                selectedRunId
                                  ? 'text-gray-600 group-hover:text-gray-900'
                                  : 'text-gray-400'
                              )}
                            >
                              Send logs
                            </span>
                          </label>
                        </Tooltip>

                        <Tooltip
                          content={
                            selectedStepId
                              ? 'Include scrubbed I/O data structure (values removed)'
                              : 'Select a step to include I/O data'
                          }
                          side="top"
                        >
                          <label
                            className={cn(
                              'flex items-center gap-1.5 group',
                              selectedStepId
                                ? 'cursor-pointer'
                                : 'cursor-not-allowed opacity-50'
                            )}
                          >
                            <input
                              type="checkbox"
                              // NOTE: Regardless of preferences, we show it
                              // unchecked if no step is selected because I/O
                              // can't be sent without a step
                              checked={attachIoData && !!selectedStepId}
                              onChange={e => setAttachIoData(e.target.checked)}
                              disabled={!selectedStepId}
                              className={cn(
                                'w-3.5 h-3.5 rounded border-gray-300 text-primary-600',
                                'focus:ring-primary-500 focus:ring-offset-0',
                                selectedStepId
                                  ? 'cursor-pointer'
                                  : 'cursor-not-allowed'
                              )}
                            />
                            <span
                              className={cn(
                                'text-[11px] font-medium',
                                selectedStepId
                                  ? 'text-gray-600 group-hover:text-gray-900'
                                  : 'text-gray-400'
                              )}
                            >
                              Send scrubbed I/O
                            </span>
                          </label>
                        </Tooltip>
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
                    disabled={!input.trim() || isLoading || isDisabled}
                    className={cn(
                      'inline-flex items-center justify-center',
                      'h-7 w-7 rounded-lg',
                      'transition-all duration-200',
                      'focus:outline-none focus:ring-2 focus:ring-offset-2',
                      input.trim() && !isLoading && !isDisabled
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
