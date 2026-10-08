import { useEffect, useRef, useState } from 'react';

import { cn } from '#/utils/cn';

import { Tooltip } from '../../components/Tooltip';
import type { AISkill } from '../types/sessionContext';
import { parseSlashCommand } from '../utils/slashCommand';

import { AIDisclaimerFooter } from './AIDisclaimerFooter';
import { SkillCommand } from './SkillCommand';

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
  /** Skills a leading slash command can invoke */
  skills?: AISkill[] | undefined;
}

interface MessageOptions {
  attach_logs?: boolean;
  attach_io_data?: boolean;
  follow_run_id?: string;
}

/** What can be attached beyond the workflow, which the assistant always reads. */
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

// Mirrors ChatMessage.max_content_length/0.
const MAX_MESSAGE_LENGTH = 10_000;

// An always-on counter reads as a warning about a limit almost nobody meets.
const COUNT_FROM = MAX_MESSAGE_LENGTH - 500;

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
  skills = [],
}: ChatInputProps) {
  const [input, setInput] = useState('');
  const [skill, setSkill] = useState<AISkill | null>(null);
  const [highlighted, setHighlighted] = useState(0);
  const [dismissedMenuFor, setDismissedMenuFor] = useState<string | null>(null);

  const content = skill
    ? `/${skill.name} ${input.trim()}`.trim()
    : input.trim();
  const tooLong = content.length > MAX_MESSAGE_LENGTH;
  const showCount = content.length >= COUNT_FROM;
  const canSend = !!content && !isLoading && !isDisabled && !tooLong;

  // A command is only one while it is the first token, so the menu closes
  // at the first whitespace.
  const menuMatches =
    !skill && /^\/\S*$/.test(input) && dismissedMenuFor !== input
      ? skills.filter(s => s.name.startsWith(input.slice(1)))
      : [];
  const activeIndex = Math.min(highlighted, menuMatches.length - 1);
  const activeSkill: AISkill | undefined = menuMatches[activeIndex];
  const menuOpen = activeSkill !== undefined;

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

  const chooseSkill = (chosen: AISkill, rest = '') => {
    setSkill(chosen);
    setInput(rest);
    setHighlighted(0);
    textareaRef.current?.focus();
  };

  const handleChange = (value: string) => {
    // Typing the space after a known name, or pasting a whole command, turns
    // it into a pill; a bare `/qa` stays text until then, like `/qafoo`.
    const parsed = skill ? null : parseSlashCommand(value, skills);
    if (parsed && /^\/\S+\s/.test(value)) {
      chooseSkill(parsed.skill, parsed.rest);
      return;
    }
    setInput(value);
    setHighlighted(0);
  };

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    if (!canSend) return;

    const options: MessageOptions = {};
    // The run rides along so what we promise to attach and what the backend
    // looks up cannot drift: LiveView push_patch strips the URL param.
    if (selectedRunId) {
      options.attach_logs = attachLogs;
      options.attach_io_data = attachIoData;
      options.follow_run_id = selectedRunId;
    }

    onSendMessage?.(content, options);
    setInput('');
    setSkill(null);
  };

  const handleKeyDown = (e: React.KeyboardEvent<HTMLTextAreaElement>) => {
    if (activeSkill) {
      const move = { ArrowDown: 1, ArrowUp: -1 }[e.key];
      if (move) {
        e.preventDefault();
        setHighlighted(
          (activeIndex + move + menuMatches.length) % menuMatches.length
        );
        return;
      }
      if ((e.key === 'Enter' && !e.shiftKey) || e.key === 'Tab') {
        e.preventDefault();
        chooseSkill(activeSkill);
        return;
      }
      if (e.key === 'Escape') {
        e.preventDefault();
        setDismissedMenuFor(input);
        return;
      }
    }

    const { selectionStart, selectionEnd } = e.currentTarget;
    if (
      skill &&
      e.key === 'Backspace' &&
      selectionStart === 0 &&
      selectionEnd === 0
    ) {
      e.preventDefault();
      setSkill(null);
      return;
    }

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
              {menuOpen && (
                <div
                  id="skill-menu"
                  role="listbox"
                  aria-label="Skills"
                  data-testid="skill-menu"
                  className={cn(
                    'absolute bottom-full left-0 right-0 mb-2 z-10 py-1',
                    'rounded-lg border border-gray-200 bg-white shadow-lg'
                  )}
                >
                  {menuMatches.map((s, i) => (
                    <div
                      key={s.name}
                      id={`skill-option-${s.name}`}
                      role="option"
                      aria-selected={i === activeIndex}
                      tabIndex={-1}
                      onMouseDown={e => {
                        e.preventDefault();
                        chooseSkill(s);
                      }}
                      onMouseEnter={() => setHighlighted(i)}
                      className={cn(
                        'flex items-baseline gap-2 px-3 py-2 cursor-pointer',
                        i === activeIndex && 'bg-gray-100'
                      )}
                    >
                      <span className="text-sm font-medium text-gray-900">
                        /{s.name}
                      </span>
                      <span className="text-xs text-gray-500 truncate">
                        {s.description}
                      </span>
                    </div>
                  ))}
                </div>
              )}
              <div
                className={cn(
                  'rounded-xl border-2 transition-all duration-200',
                  'bg-white',
                  content
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

                <div className="flex items-start">
                  {skill && (
                    <SkillCommand
                      skill={skill}
                      className="shrink-0 pl-4 py-3 text-[15px]"
                    />
                  )}
                  <textarea
                    ref={textareaRef}
                    data-testid="chat-input"
                    value={input}
                    onChange={e => handleChange(e.target.value)}
                    onKeyDown={handleKeyDown}
                    placeholder={skill ? 'Add details (optional)' : placeholder}
                    disabled={isLoading || isDisabled}
                    rows={1}
                    role="combobox"
                    aria-expanded={menuOpen}
                    aria-controls={menuOpen ? 'skill-menu' : undefined}
                    aria-activedescendant={
                      activeSkill && `skill-option-${activeSkill.name}`
                    }
                    className={cn(
                      'block w-full min-w-0 flex-1 px-4 py-3 bg-transparent resize-none',
                      skill && 'pl-1',
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
