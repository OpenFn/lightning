import hljs from 'highlight.js/lib/core';
import elixir from 'highlight.js/lib/languages/elixir';
import javascript from 'highlight.js/lib/languages/javascript';
import json from 'highlight.js/lib/languages/json';
import yaml from 'highlight.js/lib/languages/yaml';
import 'highlight.js/styles/github.css';
import { marked } from 'marked';
import { useEffect, useMemo, useRef, useState } from 'react';

import { cn } from '#/utils/cn';

// Register languages we want to support
hljs.registerLanguage('javascript', javascript);
hljs.registerLanguage('json', json);
hljs.registerLanguage('yaml', yaml);
hljs.registerLanguage('elixir', elixir);

// Configure marked
marked.setOptions({
  gfm: true,
  breaks: true,
  highlight: (code, lang) => {
    if (lang && hljs.getLanguage(lang)) {
      try {
        return hljs.highlight(code, { language: lang }).value;
      } catch (err) {
        console.error('Highlight error:', err);
      }
    }
    return code;
  },
});

/**
 * Markdown renderer component using marked
 */
const MarkdownContent = ({
  content,
  className,
  showAddButtons,
}: {
  content: string;
  className?: string;
  showAddButtons?: boolean;
}) => {
  const containerRef = useRef<HTMLDivElement>(null);

  const html = useMemo(() => {
    try {
      const result = marked.parse(content, { async: false });
      return typeof result === 'string' ? result : content;
    } catch (err) {
      console.error('Markdown parse error:', err);
      return content;
    }
  }, [content]);

  // Add copy/add buttons to code blocks after render
  useEffect(() => {
    if (!containerRef.current) return;

    const codeBlocks = containerRef.current.querySelectorAll('pre > code');

    codeBlocks.forEach(codeElement => {
      const preElement = codeElement.parentElement;
      if (!preElement || preElement.querySelector('.code-actions')) return; // Already has buttons

      const code = codeElement.textContent || '';

      // Create button container
      const buttonContainer = document.createElement('div');
      buttonContainer.className =
        'code-actions absolute top-2 right-2 flex items-center gap-1 opacity-0 group-hover:opacity-100 transition-opacity';

      // Create copy button
      const copyButton = document.createElement('button');
      copyButton.type = 'button';
      copyButton.className =
        'rounded-md px-2 py-1 text-xs font-medium bg-slate-300 text-white hover:bg-primary-600 hover:scale-105 transition-all duration-300 ease-in-out';
      copyButton.textContent = 'COPY';
      copyButton.title = 'Copy to clipboard';

      copyButton.onclick = async e => {
        e.stopPropagation();
        const success = await doCopy(code);
        if (success) {
          copyButton.textContent = 'COPIED';
          copyButton.className =
            'rounded-md px-2 py-1 text-xs font-medium bg-green-100 text-green-700 scale-105 transition-all duration-300 ease-in-out';
          setTimeout(() => {
            copyButton.textContent = 'COPY';
            copyButton.className =
              'rounded-md px-2 py-1 text-xs font-medium bg-slate-300 text-white hover:bg-primary-600 hover:scale-105 transition-all duration-300 ease-in-out';
          }, 2000);
        }
      };

      buttonContainer.appendChild(copyButton);

      // Create add button if in job mode
      if (showAddButtons) {
        const addButton = document.createElement('button');
        addButton.type = 'button';
        addButton.className =
          'rounded-md px-2 py-1 text-xs font-medium bg-slate-300 text-white hover:bg-primary-600 hover:scale-105 transition-all duration-300 ease-in-out';
        addButton.textContent = 'ADD';
        addButton.title = 'Add this snippet to the end of the code';

        addButton.onclick = e => {
          e.stopPropagation();
          doInsert(code);
          addButton.textContent = 'ADDED';
          addButton.className =
            'rounded-md px-2 py-1 text-xs font-medium bg-green-100 text-green-700 scale-105 transition-all duration-300 ease-in-out';
          addButton.disabled = true;
          setTimeout(() => {
            addButton.textContent = 'ADD';
            addButton.className =
              'rounded-md px-2 py-1 text-xs font-medium bg-slate-300 text-white hover:bg-primary-600 hover:scale-105 transition-all duration-300 ease-in-out';
            addButton.disabled = false;
          }, 2000);
        };

        buttonContainer.appendChild(addButton);
      }

      // Make pre element relative for absolute positioning
      preElement.style.position = 'relative';
      preElement.classList.add('group');
      preElement.appendChild(buttonContainer);
    });
  }, [html, showAddButtons]);

  return (
    <div
      ref={containerRef}
      className={className}
      dangerouslySetInnerHTML={{ __html: html }}
    />
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
  onApply,
  isApplying = false,
}: {
  code: string;
  showAdd?: boolean;
  showApply?: boolean;
  onApply?: () => void;
  isApplying?: boolean;
}) => {
  const [copied, setCopied] = useState(false);
  const [applied, setApplied] = useState(false);
  const [added, setAdded] = useState(false);

  const handleCopy = (e: React.MouseEvent) => {
    e.stopPropagation();
    void (async () => {
      const success = await doCopy(code);
      if (success) {
        setCopied(true);
        setTimeout(() => setCopied(false), 2000);
      }
    })();
  };

  const handleAdd = (e: React.MouseEvent) => {
    e.stopPropagation();
    doInsert(code);
    setAdded(true);
    setTimeout(() => setAdded(false), 2000);
  };

  const handleApply = (e: React.MouseEvent) => {
    e.stopPropagation();
    if (onApply) {
      onApply();
      setApplied(true);
      setTimeout(() => setApplied(false), 2000);
    }
  };

  return (
    <div className="flex items-center gap-1">
      {showApply && (
        <button
          type="button"
          onClick={handleApply}
          disabled={isApplying || applied}
          className={cn(
            'rounded-md px-2 py-1 text-xs font-medium transition-all duration-300 ease-in-out',
            applied
              ? 'bg-green-100 text-green-700 scale-105'
              : isApplying
                ? 'bg-gray-200 text-gray-400 cursor-not-allowed'
                : 'bg-slate-300 text-white hover:bg-primary-600 hover:scale-105'
          )}
          title={applied ? 'Applied!' : 'Apply workflow to canvas'}
        >
          {applied ? 'APPLIED' : isApplying ? 'APPLYING...' : 'APPLY'}
        </button>
      )}
      <button
        type="button"
        onClick={handleCopy}
        className={cn(
          'rounded-md px-2 py-1 text-xs font-medium transition-all duration-300 ease-in-out',
          copied
            ? 'bg-green-100 text-green-700 scale-105'
            : 'bg-slate-300 text-white hover:bg-primary-600 hover:scale-105'
        )}
        title={copied ? 'Copied!' : 'Copy to clipboard'}
      >
        {copied ? 'COPIED' : 'COPY'}
      </button>
      {showAdd && (
        <button
          type="button"
          onClick={handleAdd}
          disabled={added}
          className={cn(
            'rounded-md px-2 py-1 text-xs font-medium transition-all duration-300 ease-in-out',
            added
              ? 'bg-green-100 text-green-700 scale-105'
              : 'bg-slate-300 text-white hover:bg-primary-600 hover:scale-105'
          )}
          title={added ? 'Added!' : 'Add this snippet to the end of the code'}
        >
          {added ? 'ADDED' : 'ADD'}
        </button>
      )}
    </div>
  );
};

/**
 * Format timestamp for display
 * Shows relative time (e.g., "2 minutes ago") or date if older than 24h
 */
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

  // Format as date if older than a week
  return date.toLocaleDateString(undefined, {
    month: 'short',
    day: 'numeric',
    year: date.getFullYear() !== now.getFullYear() ? 'numeric' : undefined,
  });
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
 */

interface Message {
  id: string;
  content: string;
  role: 'user' | 'assistant';
  status: 'pending' | 'processing' | 'success' | 'error' | 'cancelled';
  code?: string;
  inserted_at: string;
}

interface MessageListProps {
  messages?: Message[];
  isLoading?: boolean;
  onApplyWorkflow?: ((yaml: string, messageId: string) => void) | undefined;
  applyingMessageId?: string | null | undefined;
  showAddButtons?: boolean; // Show ADD buttons for code snippets (job_code mode)
  onRetryMessage?: (messageId: string) => void; // Retry failed messages
}

export function MessageList({
  messages = [],
  isLoading = false,
  onApplyWorkflow,
  applyingMessageId,
  showAddButtons = false,
  onRetryMessage,
}: MessageListProps) {
  const loadingRef = useRef<HTMLDivElement>(null);
  const messagesEndRef = useRef<HTMLDivElement>(null);
  const [expandedYaml, setExpandedYaml] = useState<Set<string>>(new Set());

  // Auto-scroll to bottom when new messages arrive
  useEffect(() => {
    if (messagesEndRef.current) {
      messagesEndRef.current.scrollIntoView({
        behavior: 'smooth',
        block: 'end',
      });
    }
  }, [messages.length]);

  // Auto-scroll to loading indicator when it appears
  useEffect(() => {
    if (isLoading && loadingRef.current) {
      loadingRef.current.scrollIntoView({ behavior: 'smooth', block: 'end' });
    }
  }, [isLoading]);

  if (messages.length === 0 && !isLoading) {
    return (
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
    );
  }

  return (
    <div className="h-full overflow-y-auto">
      {messages.map(message => (
        <div
          key={message.id}
          className={cn(
            'group px-6 py-4',
            message.role === 'assistant' ? 'bg-gray-50/50' : 'bg-white'
          )}
        >
          <div className="max-w-3xl mx-auto">
            {message.role === 'assistant' ? (
              // Assistant Message - Full Width
              <div>
                {/* Message Content */}
                <div className="space-y-3">
                  {/* Message Text */}
                  <MarkdownContent
                    content={message.content}
                    showAddButtons={showAddButtons}
                    className="text-sm text-gray-700 leading-relaxed prose prose-sm max-w-none prose-headings:font-medium prose-h1:text-lg prose-h1:text-gray-900 prose-h1:mb-3 prose-h2:text-base prose-h2:text-gray-900 prose-h2:mb-2 prose-h2:mt-5 prose-h3:text-sm prose-h3:text-gray-900 prose-h3:mb-2 prose-h3:font-semibold prose-p:mb-3 prose-p:last:mb-0 prose-p:text-gray-700 prose-ul:list-disc prose-ul:pl-5 prose-ul:mb-3 prose-ul:space-y-1 prose-ol:list-decimal prose-ol:pl-5 prose-ol:mb-3 prose-ol:space-y-1 prose-li:text-gray-700 prose-strong:font-medium prose-strong:text-gray-900 prose-em:italic prose-a:text-primary-600 prose-a:hover:text-primary-700 prose-a:underline prose-a:font-normal prose-code:px-1.5 prose-code:py-0.5 prose-code:bg-gray-100 prose-code:text-gray-800 prose-code:rounded prose-code:text-xs prose-code:font-mono prose-code:font-normal prose-pre:rounded-md prose-pre:bg-slate-100 prose-pre:border-2 prose-pre:border-slate-200 prose-pre:text-slate-800 prose-pre:p-4 prose-pre:overflow-x-auto prose-pre:text-xs prose-pre:font-mono prose-pre:mb-4"
                  />

                  {/* Code Block - Only show for assistant messages */}
                  {message.code && (
                    <div className="rounded-lg overflow-hidden border border-gray-200 bg-white">
                      <div
                        className={cn(
                          'w-full px-4 py-2 bg-gray-50 flex items-center justify-between',
                          expandedYaml.has(message.id) &&
                            'border-b border-gray-200'
                        )}
                      >
                        <button
                          type="button"
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
                          <span className="text-xs font-medium text-gray-700">
                            Generated Workflow
                          </span>
                        </button>
                        <CodeActionButtons
                          code={message.code}
                          showAdd={showAddButtons}
                          showApply={!!onApplyWorkflow}
                          onApply={() =>
                            onApplyWorkflow?.(message.code!, message.id)
                          }
                          isApplying={applyingMessageId === message.id}
                        />
                      </div>
                      {expandedYaml.has(message.id) && (
                        <pre className="bg-slate-100 text-slate-800 p-3 overflow-x-auto text-xs font-mono">
                          <code>{message.code}</code>
                        </pre>
                      )}
                    </div>
                  )}

                  {/* Error State */}
                  {message.status === 'error' && (
                    <div className="flex items-center gap-2 px-3 py-2 rounded-lg bg-red-50 border border-red-200">
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

                  {/* Processing State */}
                  {message.status === 'processing' && (
                    <div className="flex items-center gap-2 text-gray-600">
                      <div className="flex items-center gap-1">
                        <span className="inline-block w-1.5 h-1.5 bg-gray-400 rounded-full animate-bounce" />
                        <span className="inline-block w-1.5 h-1.5 bg-gray-400 rounded-full animate-bounce [animation-delay:0.15s]" />
                        <span className="inline-block w-1.5 h-1.5 bg-gray-400 rounded-full animate-bounce [animation-delay:0.3s]" />
                      </div>
                    </div>
                  )}

                  {/* Timestamp */}
                  <div className="mt-2">
                    <span className="text-xs text-gray-400">
                      {formatTimestamp(message.inserted_at)}
                    </span>
                  </div>
                </div>
              </div>
            ) : (
              // User Message - Bubble Style
              <div className="flex justify-end">
                <div className="flex flex-col items-end max-w-[85%]">
                  <div className="rounded-2xl bg-gray-100 border border-gray-200 px-4 py-3">
                    <MarkdownContent
                      content={message.content}
                      showAddButtons={false}
                      className="text-sm text-gray-800 leading-relaxed prose prose-sm max-w-none prose-p:mb-2 prose-p:last:mb-0 prose-p:text-gray-800 prose-strong:font-medium prose-strong:text-gray-900 prose-code:px-1 prose-code:py-0.5 prose-code:bg-white prose-code:text-gray-800 prose-code:rounded prose-code:text-xs prose-code:font-mono prose-code:font-normal prose-pre:rounded-md prose-pre:bg-slate-100 prose-pre:border-2 prose-pre:border-slate-200 prose-pre:text-slate-800 prose-pre:p-3 prose-pre:overflow-x-auto prose-pre:text-xs prose-pre:font-mono prose-pre:mt-2"
                    />
                  </div>

                  {/* Error State for User Messages */}
                  {message.status === 'error' && (
                    <div className="flex items-center gap-2 mt-2 px-3 py-1.5 rounded-lg bg-red-50 border border-red-200">
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

                  {/* Timestamp */}
                  <span className="text-xs text-gray-400 mt-1">
                    {formatTimestamp(message.inserted_at)}
                  </span>
                </div>
              </div>
            )}
          </div>
        </div>
      ))}

      {/* Loading Indicator - Shows while waiting for assistant response */}
      {isLoading && (
        <div ref={loadingRef} className="group px-6 py-4 bg-gray-50/50">
          <div className="max-w-3xl mx-auto">
            <div className="flex items-center gap-1.5">
              <span className="inline-block w-1.5 h-1.5 bg-gray-400 rounded-full animate-bounce" />
              <span className="inline-block w-1.5 h-1.5 bg-gray-400 rounded-full animate-bounce [animation-delay:0.15s]" />
              <span className="inline-block w-1.5 h-1.5 bg-gray-400 rounded-full animate-bounce [animation-delay:0.3s]" />
            </div>
          </div>
        </div>
      )}

      {/* Scroll anchor - invisible element at the bottom */}
      <div ref={messagesEndRef} />
    </div>
  );
}
