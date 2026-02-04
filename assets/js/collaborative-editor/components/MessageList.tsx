import { useEffect, useRef, useState } from 'react';
import Markdown from 'react-markdown';
import remarkGfm from 'remark-gfm';

import { useCopyToClipboard } from '#/collaborative-editor/hooks/useCopyToClipboard';
import { cn } from '#/utils/cn';

import type { Message } from '../types/ai-assistant';

import { Tooltip } from './Tooltip';

/**
 * Custom code block component for react-markdown
 * Renders code with COPY/ADD action buttons
 */
const CodeBlock = ({
  children,
  showAddButtons,
  isWriteDisabled = false,
}: {
  children: string;
  showAddButtons?: boolean;
  /** Whether Add button is disabled due to readonly mode */
  isWriteDisabled?: boolean;
}) => {
  const { copyText, copyToClipboard, isCopied } = useCopyToClipboard();
  const [added, setAdded] = useState(false);

  const handleCopy = (e: React.MouseEvent) => {
    e.stopPropagation();
    void copyToClipboard(children);
  };

  const handleAdd = (e: React.MouseEvent) => {
    e.stopPropagation();
    if (isWriteDisabled) return;
    doInsert(children);
    setAdded(true);
    setTimeout(() => setAdded(false), 2000);
  };

  const isAddDisabled = added || isWriteDisabled;

  const addButton = (
    <button
      type="button"
      onClick={handleAdd}
      disabled={isAddDisabled}
      className={cn(
        'rounded-md px-2 py-1 text-xs font-medium transition-all duration-300 ease-in-out',
        added
          ? 'bg-green-100 text-green-700 scale-105'
          : isAddDisabled
            ? 'bg-gray-200 text-gray-400 cursor-not-allowed'
            : 'bg-slate-300 text-white hover:bg-primary-600 hover:scale-105'
      )}
    >
      {added ? 'Added' : 'Add'}
    </button>
  );

  return (
    <pre className="relative group">
      <code>{children}</code>
      <div className="code-actions absolute top-2 right-2 flex items-center gap-1 opacity-0 group-hover:opacity-100 transition-opacity">
        <button
          type="button"
          onClick={handleCopy}
          className={cn(
            'rounded-md px-2 py-1 text-xs font-medium transition-all duration-300 ease-in-out',
            isCopied
              ? 'bg-green-100 text-green-700 scale-105'
              : 'bg-slate-300 text-white hover:bg-primary-600 hover:scale-105'
          )}
        >
          {copyText || 'Copy'}
        </button>
        {showAddButtons && (
          <Tooltip
            content={
              isWriteDisabled
                ? 'Cannot add code snippet in readonly mode'
                : null
            }
            side="top"
          >
            {addButton}
          </Tooltip>
        )}
      </div>
    </pre>
  );
};

/**
 * Markdown renderer component using react-markdown
 */
const MarkdownContent = ({
  content,
  className,
  showAddButtons,
  isWriteDisabled = false,
}: {
  content: string;
  className?: string;
  showAddButtons?: boolean;
  /** Whether Add button is disabled due to readonly mode */
  isWriteDisabled?: boolean;
}) => {
  return (
    <div className={className}>
      <Markdown
        remarkPlugins={[remarkGfm]}
        components={{
          // Custom renderer for code blocks (fenced code)
          // Note: This only applies to assistant messages - user messages are plain text
          pre: ({ children }) => <>{children}</>,
          code: ({ className: codeClassName, children }) => {
            // Check if this is a code block (has language class) or inline code
            const isCodeBlock = codeClassName?.startsWith('language-');
            const codeContent = String(children).replace(/\n$/, '');

            if (isCodeBlock || (children && String(children).includes('\n'))) {
              return (
                <CodeBlock
                  showAddButtons={showAddButtons ?? false}
                  isWriteDisabled={isWriteDisabled}
                >
                  {codeContent}
                </CodeBlock>
              );
            }

            // Inline code
            return <code className={codeClassName}>{children}</code>;
          },
        }}
      >
        {content}
      </Markdown>
    </div>
  );
};

/**
 * Copy text to clipboard using modern Clipboard API
 */
const doCopy = async (text: string) => {
  const type = 'text/plain';
  const data = [new ClipboardItem({ [type]: new Blob([text], { type }) })];

  try {
    await navigator.clipboard.write(data);
    return true;
  } catch (e) {
    console.error('Copy failed:', e);
    return false;
  }
};

/**
 * Insert code snippet into the editor using custom event
 */
const doInsert = (text: string) => {
  const e = new Event('insert-snippet');
  // @ts-expect-error - custom event property
  e.snippet = text;

  document.dispatchEvent(e);
};

/**
 * CodeActionButtons Component - Shows COPY and optional ADD/APPLY buttons with feedback
 */
const CodeActionButtons = ({
  code,
  showAdd = false,
  showApply = false,
  showPreview = false,
  onApply,
  onPreview,
  isApplying = false,
  isPreviewActive = false,
  isWriteDisabled = false,
}: {
  code: string;
  showAdd?: boolean;
  showApply?: boolean;
  showPreview?: boolean;
  onApply?: () => void;
  onPreview?: () => void;
  isApplying?: boolean;
  isPreviewActive?: boolean;
  /** Whether Apply/Add buttons are disabled due to readonly mode */
  isWriteDisabled?: boolean;
}) => {
  const { copyText, copyToClipboard, isCopied } = useCopyToClipboard();
  const [applied, setApplied] = useState(false);
  const [added, setAdded] = useState(false);

  const handleCopy = (e: React.MouseEvent) => {
    e.stopPropagation();
    void copyToClipboard(code);
  };

  const handleAdd = (e: React.MouseEvent) => {
    e.stopPropagation();
    if (isWriteDisabled) return;
    doInsert(code);
    setAdded(true);
    setTimeout(() => setAdded(false), 2000);
  };

  const handleApply = (e: React.MouseEvent) => {
    e.stopPropagation();
    if (isWriteDisabled) return;
    if (onApply) {
      onApply();
      setApplied(true);
      setTimeout(() => setApplied(false), 2000);
    }
  };

  const handlePreview = (e: React.MouseEvent) => {
    e.stopPropagation();
    if (onPreview) {
      onPreview();
    }
  };

  const isApplyDisabled = isApplying || applied || isWriteDisabled;
  const isAddDisabled = added || isWriteDisabled;
  const isPreviewDisabled = isPreviewActive;

  const applyButton = (
    <button
      type="button"
      data-testid="apply-workflow-button"
      onClick={handleApply}
      disabled={isApplyDisabled}
      className={cn(
        'rounded-md px-2 py-1 text-xs font-medium transition-all duration-300 ease-in-out',
        applied
          ? 'bg-green-100 text-green-700 scale-105'
          : isApplyDisabled
            ? 'bg-gray-200 text-gray-400 cursor-not-allowed'
            : 'bg-slate-300 text-white hover:bg-primary-600 hover:scale-105'
      )}
    >
      {applied ? 'Applied' : isApplying ? 'Applying...' : 'Apply'}
    </button>
  );

  const addButton = (
    <button
      type="button"
      onClick={handleAdd}
      disabled={isAddDisabled}
      className={cn(
        'rounded-md px-2 py-1 text-xs font-medium transition-all duration-300 ease-in-out',
        added
          ? 'bg-green-100 text-green-700 scale-105'
          : isAddDisabled
            ? 'bg-gray-200 text-gray-400 cursor-not-allowed'
            : 'bg-slate-300 text-white hover:bg-primary-600 hover:scale-105'
      )}
    >
      {added ? 'Added' : 'Add'}
    </button>
  );

  const previewButton = (
    <button
      type="button"
      onClick={handlePreview}
      disabled={isPreviewDisabled}
      className={cn(
        'rounded-md px-2 py-1 text-xs font-medium transition-all duration-300 ease-in-out',
        isPreviewActive
          ? 'bg-green-100 text-green-700'
          : isPreviewDisabled
            ? 'bg-gray-200 text-gray-400 cursor-not-allowed'
            : 'bg-slate-300 text-white hover:bg-primary-600 text-white'
      )}
    >
      {isPreviewActive ? 'Previewing' : 'Preview'}
    </button>
  );

  return (
    <div className="flex flex-wrap items-center justify-end gap-1">
      {showPreview && previewButton}
      {showApply && (
        <Tooltip
          content={
            isWriteDisabled ? 'Cannot apply workflow in readonly mode' : null
          }
          side="top"
        >
          {applyButton}
        </Tooltip>
      )}
      <button
        type="button"
        onClick={handleCopy}
        className={cn(
          'rounded-md px-2 py-1 text-xs font-medium transition-all duration-300 ease-in-out',
          isCopied
            ? 'bg-green-100 text-green-700 scale-105'
            : 'bg-slate-300 text-white hover:bg-primary-600 hover:scale-105'
        )}
      >
        {copyText || 'Copy'}
      </button>
      {showAdd && (
        <Tooltip
          content={
            isWriteDisabled ? 'Cannot add code snippet in readonly mode' : null
          }
          side="top"
        >
          {addButton}
        </Tooltip>
      )}
    </div>
  );
};

const formatTimestamp = (isoTimestamp: string): string => {
  const date = new Date(isoTimestamp);
  const now = new Date();
  const diffMs = now.getTime() - date.getTime();
  const diffMins = Math.floor(diffMs / 60000);
  const diffHours = Math.floor(diffMs / 3600000);
  const diffDays = Math.floor(diffMs / 86400000);

  if (diffMins < 1) return 'Just now';
  if (diffMins < 60) return `${diffMins}m ago`;
  if (diffHours < 24) return `${diffHours}h ago`;
  if (diffDays < 7) return `${diffDays}d ago`;

  return date.toLocaleDateString(undefined, {
    month: 'short',
    day: 'numeric',
    year: date.getFullYear() !== now.getFullYear() ? 'numeric' : undefined,
  });
};

/**
 * Formats user name for attribution display
 * Returns first name, or "first last" if both available, or null if no user
 */
const formatUserName = (user: Message['user']): string | null => {
  if (!user) return null;
  const { first_name, last_name } = user;
  if (first_name && last_name) return `${first_name} ${last_name}`;
  if (first_name) return first_name;
  return null;
};

/**
 * MessageList Component
 *
 * Displays the list of messages in the AI Assistant chat.
 * Shows user and assistant messages with appropriate styling.
 *
 * Features:
 * - Empty state with welcome message
 * - User messages in bubble style (right-aligned)
 * - Assistant messages full-width with code blocks
 * - Loading and error states
 * - Copy functionality for code blocks
 * - User attribution for collaborative sessions
 */

interface MessageListProps {
  messages?: Message[];
  isLoading?: boolean;
  sessionType?: 'job_code' | 'workflow_template';
  onApplyWorkflow?: ((yaml: string, messageId: string) => void) | undefined;
  onApplyJobCode?: ((code: string, messageId: string) => void) | undefined;
  onPreviewJobCode?: ((code: string, messageId: string) => void) | undefined;
  applyingMessageId?: string | null | undefined;
  previewingMessageId?: string | null | undefined;
  showAddButtons?: boolean;
  showApplyButton?: boolean;
  onRetryMessage?: (messageId: string) => void;
  /** Whether write actions (Apply/Add) are disabled due to readonly mode */
  isWriteDisabled?: boolean;
}

export function MessageList({
  messages = [],
  isLoading = false,
  onApplyWorkflow,
  onApplyJobCode,
  onPreviewJobCode,
  applyingMessageId,
  previewingMessageId,
  showAddButtons = false,
  showApplyButton = false,
  onRetryMessage,
  isWriteDisabled = false,
}: MessageListProps) {
  const loadingRef = useRef<HTMLDivElement>(null);
  const messagesEndRef = useRef<HTMLDivElement>(null);
  const [expandedYaml, setExpandedYaml] = useState<Set<string>>(new Set());
  const [copiedMessageId, setCopiedMessageId] = useState<string | null>(null);

  useEffect(() => {
    if (messagesEndRef.current) {
      messagesEndRef.current.scrollIntoView({
        behavior: 'smooth',
        block: 'end',
      });
    }
  }, [messages.length]);

  useEffect(() => {
    if (isLoading && loadingRef.current) {
      loadingRef.current.scrollIntoView({ behavior: 'smooth', block: 'end' });
    }
  }, [isLoading]);

  if (messages.length === 0) {
    return (
      <div
        className="flex items-center justify-center h-full"
        data-testid="empty-state"
      >
        <div className="flex items-center gap-2 text-gray-600">
          <span className="hero-arrow-path h-5 w-5 animate-spin" />
          <span className="text-sm">Loading session...</span>
        </div>
      </div>
    );
  }

  return (
    <div className="h-full overflow-y-auto" data-testid="message-list">
      {messages.map(message => (
        <div
          key={message.id}
          data-role={`${message.role}-message`}
          className={cn('group px-6 py-4')}
        >
          <div className="max-w-3xl mx-auto">
            {message.role === 'assistant' ? (
              <div data-testid="assistant-message">
                <div className="space-y-3">
                  <MarkdownContent
                    content={message.content}
                    showAddButtons={showAddButtons && !message.code}
                    isWriteDisabled={isWriteDisabled}
                    className="text-sm text-gray-700 leading-relaxed prose prose-sm max-w-none prose-headings:font-medium prose-h1:text-lg prose-h1:text-gray-900 prose-h1:mb-3 prose-h2:text-base prose-h2:text-gray-900 prose-h2:mb-2 prose-h2:mt-5 prose-h3:text-sm prose-h3:text-gray-900 prose-h3:mb-2 prose-h3:font-semibold prose-p:mb-3 prose-p:last:mb-0 prose-p:text-gray-700 prose-ul:list-disc prose-ul:pl-5 prose-ul:mb-3 prose-ul:space-y-1 prose-ol:list-decimal prose-ol:pl-5 prose-ol:mb-3 prose-ol:space-y-1 prose-li:text-gray-700 prose-strong:font-medium prose-strong:text-gray-900 prose-em:italic prose-a:text-primary-600 prose-a:hover:text-primary-700 prose-a:underline prose-a:font-normal prose-code:px-1.5 prose-code:py-0.5 prose-code:bg-gray-100 prose-code:text-gray-800 prose-code:rounded prose-code:text-xs prose-code:font-mono prose-code:font-normal prose-pre:rounded-md prose-pre:bg-slate-100 prose-pre:border-2 prose-pre:border-slate-200 prose-pre:text-slate-800 prose-pre:p-4 prose-pre:overflow-x-auto prose-pre:text-xs prose-pre:font-mono prose-pre:mb-4"
                  />

                  {message.code && (
                    <div className="rounded-lg overflow-hidden border border-gray-200 bg-white">
                      <div
                        className={cn(
                          'w-full px-4 py-2 bg-gray-50 flex items-center justify-between gap-2',
                          expandedYaml.has(message.id) &&
                            'border-b border-gray-200'
                        )}
                      >
                        <button
                          type="button"
                          data-testid="expand-code-button"
                          onClick={() => {
                            setExpandedYaml(prev => {
                              const next = new Set(prev);
                              if (next.has(message.id)) {
                                next.delete(message.id);
                              } else {
                                next.add(message.id);
                              }
                              return next;
                            });
                          }}
                          className="flex items-center gap-2 hover:opacity-75 transition-opacity"
                        >
                          <span
                            className={cn(
                              'transition-transform duration-200',
                              expandedYaml.has(message.id) ? 'rotate-90' : ''
                            )}
                          >
                            <span className="hero-chevron-right h-4 w-4 text-gray-500" />
                          </span>
                          <span className="text-xs text-left font-medium text-gray-700">
                            {message.job_id
                              ? 'Generated Job Code'
                              : 'Generated Workflow'}
                          </span>
                        </button>
                        <CodeActionButtons
                          code={message.code}
                          showAdd={showAddButtons}
                          showApply={showApplyButton}
                          showPreview={!!message.job_id}
                          onApply={() => {
                            if (message.job_id) {
                              onApplyJobCode?.(message.code!, message.id);
                            } else {
                              onApplyWorkflow?.(message.code!, message.id);
                            }
                          }}
                          onPreview={() => {
                            onPreviewJobCode?.(message.code!, message.id);
                          }}
                          isApplying={!!applyingMessageId}
                          isPreviewActive={previewingMessageId === message.id}
                          isWriteDisabled={isWriteDisabled}
                        />
                      </div>
                      {expandedYaml.has(message.id) && (
                        <pre
                          className="bg-slate-100 text-slate-800 p-3 overflow-x-auto text-xs font-mono"
                          data-testid="generated-code"
                        >
                          <code>{message.code}</code>
                        </pre>
                      )}
                    </div>
                  )}

                  {message.status === 'error' && (
                    <div
                      className="flex items-center gap-2 px-3 py-2 rounded-lg bg-red-50 border border-red-200"
                      data-testid="ai-error-message"
                    >
                      <span className="hero-exclamation-circle h-4 w-4 text-red-600 flex-shrink-0" />
                      <span className="text-sm text-red-700 flex-1">
                        Failed to send message. Please try again.
                      </span>
                      {onRetryMessage && (
                        <button
                          type="button"
                          onClick={() => onRetryMessage(message.id)}
                          className={cn(
                            'inline-flex items-center gap-1.5 px-3 py-1.5',
                            'text-xs font-medium rounded-md',
                            'bg-red-100 text-red-700 hover:bg-red-200',
                            'transition-colors duration-150',
                            'focus:outline-none focus:ring-2 focus:ring-red-500 focus:ring-offset-1'
                          )}
                        >
                          <span className="hero-arrow-path h-3.5 w-3.5" />
                          Retry
                        </button>
                      )}
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

                  <div className="mt-2 flex items-center gap-2 text-xs text-gray-400">
                    <span>{formatTimestamp(message.inserted_at)}</span>
                    <span>•</span>
                    <button
                      type="button"
                      onClick={() => {
                        void (async () => {
                          const success = await doCopy(message.content);
                          if (success) {
                            setCopiedMessageId(message.id);
                            setTimeout(() => setCopiedMessageId(null), 2000);
                          }
                        })();
                      }}
                      className={cn(
                        'flex items-center gap-1 transition-colors duration-200',
                        copiedMessageId === message.id
                          ? 'text-green-600'
                          : 'text-gray-400 hover:text-gray-600'
                      )}
                      title={
                        copiedMessageId === message.id
                          ? 'Copied!'
                          : 'Copy message'
                      }
                    >
                      <span
                        className={cn(
                          'h-3 w-3',
                          copiedMessageId === message.id
                            ? 'hero-check'
                            : 'hero-clipboard-document'
                        )}
                      />
                      <span>
                        {copiedMessageId === message.id ? 'Copied' : 'Copy'}
                      </span>
                    </button>
                  </div>
                </div>
              </div>
            ) : (
              <div className="flex justify-end" data-testid="user-message">
                <div className="flex flex-col items-end max-w-[85%] min-w-0">
                  <div className="rounded-2xl bg-gray-100 px-4 py-2 max-w-full">
                    <div
                      style={{ overflowWrap: 'break-word' }}
                      className="text-sm text-gray-800 leading-relaxed whitespace-pre-wrap max-w-full"
                    >
                      {message.content}
                    </div>
                  </div>

                  {message.status === 'error' && (
                    <div
                      className="flex items-center gap-2 mt-2 px-3 py-1.5 rounded-lg bg-red-50 border border-red-200"
                      data-testid="ai-error-message"
                    >
                      <span className="hero-exclamation-circle h-3.5 w-3.5 text-red-600" />
                      <span className="text-xs text-red-700 flex-1">
                        Failed to send
                      </span>
                      {onRetryMessage && (
                        <button
                          type="button"
                          onClick={() => onRetryMessage(message.id)}
                          className={cn(
                            'inline-flex items-center gap-1 px-2 py-1',
                            'text-xs font-medium rounded-md',
                            'bg-red-100 text-red-700 hover:bg-red-200',
                            'transition-colors duration-150',
                            'focus:outline-none focus:ring-2 focus:ring-red-500 focus:ring-offset-1'
                          )}
                        >
                          <span className="hero-arrow-path h-3 w-3" />
                          Retry
                        </button>
                      )}
                    </div>
                  )}

                  <span className="text-xs text-gray-400 mt-1">
                    {formatUserName(message.user) ? (
                      <>
                        Sent by {formatUserName(message.user)} •{' '}
                        {formatTimestamp(message.inserted_at)}
                      </>
                    ) : (
                      formatTimestamp(message.inserted_at)
                    )}
                  </span>
                </div>
              </div>
            )}
          </div>
        </div>
      ))}

      {isLoading && (
        <div
          ref={loadingRef}
          className="group px-6 py-4"
          data-testid="loading-indicator"
        >
          <div className="max-w-3xl mx-auto">
            <div className="flex items-center gap-1.5">
              <span className="inline-block w-1.5 h-1.5 bg-gray-400 rounded-full animate-bounce" />
              <span className="inline-block w-1.5 h-1.5 bg-gray-400 rounded-full animate-bounce [animation-delay:0.15s]" />
              <span className="inline-block w-1.5 h-1.5 bg-gray-400 rounded-full animate-bounce [animation-delay:0.3s]" />
            </div>
          </div>
        </div>
      )}

      <div ref={messagesEndRef} />
    </div>
  );
}
