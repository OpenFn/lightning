import { useEffect, useRef, useState } from 'react';

import { cn } from '#/utils/cn';

import truncateUid from '../../utils/truncateUID';

import { Tooltip } from '../../components/Tooltip';
import { useSlashCommand } from '../hooks/useSlashCommand';
import type { AISkill } from '../types/sessionContext';

import { AIDisclaimerFooter } from './AIDisclaimerFooter';
import { SkillCommand } from './SkillCommand';
import { SkillMenu } from './SkillMenu';

interface ChatInputProps {
  onSendMessage?:
    | ((content: string, options?: MessageOptions) => void)
    | undefined;
  isLoading?: boolean | undefined;
  /** Disabled state (separate from loading, e.g., due to limits) */
  isDisabled?: boolean | undefined;
  /** Enable automatic focus management for the input */
  enableAutoFocus?: boolean | undefined;
  /** Trigger value that when changed, re-focuses the input (e.g., timestamp) */
  focusTrigger?: number | undefined;
  /** Placeholder text for the textarea */
  placeholder?: string | undefined;
  /** Message to show in tooltip when input is disabled */
  disabledMessage?: string | undefined;
  /** The run whose logs and data are attached to every message */
  selectedRunId?: string | null;
  /** Skills a leading slash command can invoke */
  skills?: AISkill[] | undefined;
}

interface MessageOptions {
  attach_logs?: boolean;
  attach_io_data?: boolean;
  follow_run_id?: string;
}

const ATTACHED_RUN_DESCRIPTION =
  "The assistant sees this run's logs and the structure of each step's " +
  'input and output, not the values.';

const MIN_TEXTAREA_HEIGHT = 52;
const MAX_TEXTAREA_HEIGHT = 200;

// Mirrors ChatMessage.max_content_length/0.
const MAX_MESSAGE_LENGTH = 10_000;

// An always-on counter reads as a warning about a limit almost nobody meets.
const COUNT_FROM = MAX_MESSAGE_LENGTH - 500;

export function ChatInput({
  onSendMessage,
  isLoading = false,
  isDisabled = false,
  enableAutoFocus = false,
  focusTrigger,
  placeholder = 'Ask me anything...',
  disabledMessage,
  selectedRunId,
  skills = [],
}: ChatInputProps) {
  const textareaRef = useRef<HTMLTextAreaElement>(null);
  const slash = useSlashCommand(skills, textareaRef);
  const { input, skill, content } = slash;

  const [detachedRunId, setDetachedRunId] = useState<string | null>(null);
  const attachedRunId =
    selectedRunId && selectedRunId !== detachedRunId ? selectedRunId : null;

  useEffect(() => {
    setDetachedRunId(null);
  }, [selectedRunId]);

  const tooLong = content.length > MAX_MESSAGE_LENGTH;
  const showCount = content.length >= COUNT_FROM;
  const canSend = !!content && !isLoading && !isDisabled && !tooLong;

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
    if (!canSend) return;

    const options: MessageOptions = {};
    // The run rides along so what we promise to attach and what the backend
    // looks up cannot drift: LiveView push_patch strips the URL param.
    if (attachedRunId) {
      options.attach_logs = true;
      options.attach_io_data = true;
      options.follow_run_id = attachedRunId;
    }

    onSendMessage?.(content, options);
    slash.reset();
  };

  const handleKeyDown = (e: React.KeyboardEvent<HTMLTextAreaElement>) => {
    if (slash.handleKeyDown(e)) return;

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
              <SkillMenu {...slash.menuProps} />
              <div
                className={cn(
                  'rounded-xl border-2 transition-all duration-200',
                  'bg-white',
                  content
                    ? 'border-primary-300'
                    : 'border-gray-200 hover:border-gray-300'
                )}
              >
                {attachedRunId && (
                  <div
                    className="flex flex-wrap items-center gap-3 px-3 pt-3"
                    data-testid="attached-context"
                  >
                    <span
                      className={cn(
                        'inline-flex items-center gap-1 rounded-md',
                        'bg-gray-100 px-1.5 py-0.5',
                        'text-[11px] font-medium text-gray-600'
                      )}
                    >
                      <Tooltip content={ATTACHED_RUN_DESCRIPTION} side="top">
                        <span className="inline-flex items-center gap-1">
                          <span className="hero-paper-clip h-3 w-3" />
                          Run {truncateUid(attachedRunId)} attached
                        </span>
                      </Tooltip>
                      <button
                        type="button"
                        onClick={() => setDetachedRunId(attachedRunId)}
                        className="-mr-0.5 flex items-center justify-center rounded-sm hover:bg-gray-200"
                        aria-label="Detach run"
                        title="Detach run"
                      >
                        <span className="hero-x-mark h-3 w-3" />
                      </button>
                    </span>
                  </div>
                )}

                <div className="relative overflow-hidden">
                  {skill && (
                    <span
                      ref={slash.commandRef}
                      className="pointer-events-none absolute left-4 top-3 text-[15px]"
                    >
                      <SkillCommand skill={skill} withTooltip={false} />
                    </span>
                  )}
                  <textarea
                    ref={textareaRef}
                    data-testid="chat-input"
                    value={input}
                    onChange={e => slash.handleChange(e.target.value)}
                    onKeyDown={handleKeyDown}
                    onScroll={slash.onScroll}
                    placeholder={skill ? 'Add details (optional)' : placeholder}
                    disabled={isLoading || isDisabled}
                    rows={1}
                    {...slash.comboboxProps}
                    className={cn(
                      'block w-full px-4 py-3 bg-transparent resize-none',
                      'text-[15px] text-gray-900 placeholder:text-gray-400',
                      'border-0 outline-none focus:outline-none focus:ring-0',
                      'disabled:text-gray-400 disabled:cursor-not-allowed'
                    )}
                    style={{
                      textIndent: slash.textIndent,
                      height: `${MIN_TEXTAREA_HEIGHT}px`,
                      minHeight: `${MIN_TEXTAREA_HEIGHT}px`,
                      maxHeight: `${MAX_TEXTAREA_HEIGHT}px`,
                      overflow: 'hidden',
                      overflowY: 'auto',
                    }}
                  />
                </div>

                <div className="flex items-center justify-between gap-3 px-3 pb-2">
                  <div className="min-w-0">
                    <div className="flex items-center gap-3 min-w-0">
                      <AIDisclaimerFooter />
                      {showCount && (
                        <span
                          data-testid="chat-input-length"
                          className={cn(
                            'text-xs whitespace-nowrap',
                            tooLong ? 'text-red-600' : 'text-gray-400'
                          )}
                        >
                          {content.length.toLocaleString()} /{' '}
                          {MAX_MESSAGE_LENGTH.toLocaleString()}
                          {tooLong ? ' — too long to send' : null}
                        </span>
                      )}
                    </div>
                  </div>

                  <button
                    type="submit"
                    data-testid="send-message-button"
                    disabled={!canSend}
                    className={cn(
                      'inline-flex items-center justify-center',
                      'h-7 w-7 rounded-lg',
                      'transition-all duration-200',
                      'focus:outline-none focus:ring-2 focus:ring-offset-2',
                      canSend
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
