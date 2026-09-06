import { useEffect, useRef, useState } from 'react';

import { cn } from '#/utils/cn';

import { Tooltip } from '../../components/Tooltip';

import { AIDisclaimerFooter } from './AIDisclaimerFooter';

interface ChatInputProps {
  onSendMessage?:
    | ((content: string, options?: MessageOptions) => void)
    | undefined;
  isLoading?: boolean | undefined;
  /** Disabled state (separate from loading, e.g., due to limits) */
  isDisabled?: boolean | undefined;
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
  /** The run both attachments are scoped to, and what gates them */
  selectedRunId?: string | null;
}

interface MessageOptions {
  attach_logs?: boolean;
  attach_io_data?: boolean;
  follow_run_id?: string;
}

/**
 * What the assistant can be given beyond the workflow, which it always reads.
 * Both are scoped to the run on screen, so both appear and disappear with it.
 */
const ATTACHMENTS = [
  {
    key: 'logs',
    label: 'Send run logs',
    description:
      'Sends every log line from this run, so the assistant can see what ' +
      'actually happened.',
  },
  {
    key: 'data',
    label: 'Send run data',
    description:
      "Sends the shape of every step's input and output. Field names go as " +
      'they are; the values are replaced by their types.',
  },
] as const;

type AttachmentKey = (typeof ATTACHMENTS)[number]['key'];

const MIN_TEXTAREA_HEIGHT = 52;
const MAX_TEXTAREA_HEIGHT = 200;

export function ChatInput({
  onSendMessage,
  isLoading = false,
  isDisabled = false,
  storageKey,
  enableAutoFocus = false,
  focusTrigger,
  placeholder = 'Ask me anything...',
  disabledMessage,
  selectedRunId,
}: ChatInputProps) {
  const [input, setInput] = useState('');

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
      const key = `${storageKey}:attach-run-data`;
      const saved = localStorage.getItem(key);
      return saved === 'true';
    } catch {
      return false;
    }
  });

  const textareaRef = useRef<HTMLTextAreaElement>(null);
  const isLoadingFromStorageRef = useRef(false);

  const attachmentState: Record<AttachmentKey, boolean> = {
    logs: attachLogs,
    data: attachIoData,
  };

  const toggleAttachment = (key: AttachmentKey) => {
    switch (key) {
      case 'logs':
        setAttachLogs(current => !current);
        break;
      case 'data':
        setAttachIoData(current => !current);
        break;
    }
  };

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
      const logsKey = `${storageKey}:attach-logs`;
      const savedLogs = localStorage.getItem(logsKey);
      const logsValue = savedLogs === 'true';
      setAttachLogs(logsValue);
    } catch {
      // Ignore localStorage errors
    }

    try {
      const ioDataKey = `${storageKey}:attach-run-data`;
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
        `${storageKey}:attach-run-data`,
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
    // Both boxes describe the run in front of the user, so both hang off the
    // same id. Sending it is what stops what we promise to attach and what the
    // backend looks up from drifting: useAIMode reads the run from the URL, and
    // LiveView push_patch strips that param.
    if (selectedRunId) {
      options.attach_logs = attachLogs;
      options.attach_io_data = attachIoData;
      options.follow_run_id = selectedRunId;
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
                {selectedRunId && (
                  <div
                    className="flex flex-wrap items-center gap-3 px-3 pt-3"
                    data-testid="attached-context"
                  >
                    {ATTACHMENTS.map(({ key, label, description }) => (
                      <Tooltip key={key} content={description} side="top">
                        <label className="flex items-center gap-1.5 group cursor-pointer">
                          <input
                            type="checkbox"
                            checked={attachmentState[key]}
                            onChange={() => {
                              toggleAttachment(key);
                            }}
                            className={cn(
                              'w-3.5 h-3.5 rounded border-gray-300',
                              'text-primary-600 cursor-pointer',
                              'focus:ring-primary-500 focus:ring-offset-0'
                            )}
                          />
                          <span
                            className={cn(
                              'text-[11px] font-medium text-gray-600',
                              'group-hover:text-gray-900'
                            )}
                          >
                            {label}
                          </span>
                        </label>
                      </Tooltip>
                    ))}
                  </div>
                )}

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

                <div className="flex items-center justify-between gap-3 px-3 pb-2">
                  <div className="min-w-0">
                    <AIDisclaimerFooter />
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
            </div>
          </Tooltip>
        </form>
      </div>
    </div>
  );
}
