import { Fragment, useEffect, useMemo, useRef, useState } from 'react';
import Markdown from 'react-markdown';
import remarkGfm from 'remark-gfm';

import { useCopyToClipboard } from '#/collaborative-editor/hooks/useCopyToClipboard';
import { cn } from '#/utils/cn';

import type {
  Message,
  ResponseSegment,
  WorkflowSnapshot,
} from '../types/ai-assistant';
import { STREAMING_MESSAGE_ID } from '../types/ai-assistant';

import { Tooltip } from '../../components/Tooltip';

import type { WorkflowChangeSet } from '../utils/workflowDiff';
import {
  assignStepDiffsToStatuses,
  deriveSnapshotChanges,
  deriveWorkflowChanges,
} from '../utils/workflowDiff';

import {
  StepDiffBlock,
  StructureBlock,
  WorkflowChangeBlocks,
  WorkflowDiffBlocks,
} from './WorkflowDiffBlocks';

const PROSE_CLASSES =
  'text-sm text-gray-700 leading-relaxed prose prose-sm max-w-none prose-headings:font-medium prose-h1:text-lg prose-h1:text-gray-900 prose-h1:mb-3 prose-h2:text-base prose-h2:text-gray-900 prose-h2:mb-2 prose-h2:mt-5 prose-h3:text-sm prose-h3:text-gray-900 prose-h3:mb-2 prose-h3:font-semibold prose-p:mb-3 prose-p:last:mb-0 prose-p:text-gray-700 prose-ul:list-disc prose-ul:pl-5 prose-ul:mb-3 prose-ul:space-y-1 prose-ol:list-decimal prose-ol:pl-5 prose-ol:mb-3 prose-ol:space-y-1 prose-li:text-gray-700 prose-strong:font-medium prose-strong:text-gray-900 prose-em:italic prose-a:text-primary-600 prose-a:hover:text-primary-700 prose-a:underline prose-a:font-normal prose-code:px-1.5 prose-code:py-0.5 prose-code:bg-gray-100 prose-code:text-gray-800 prose-code:rounded prose-code:text-xs prose-code:font-mono prose-code:font-normal prose-code:before:content-none prose-code:after:content-none prose-pre:rounded-md prose-pre:bg-slate-100 prose-pre:border-2 prose-pre:border-slate-200 prose-pre:text-slate-800 prose-pre:p-4 prose-pre:overflow-x-auto prose-pre:text-xs prose-pre:font-mono prose-pre:mb-4';

/**
 * Three-dot bouncing "typing" indicator, shared by the pre-text loading
 * indicator and the post-text streaming status.
 */
const BouncingDots = () => (
  <>
    <span className="inline-block w-1.5 h-1.5 bg-gray-400 rounded-full animate-bounce" />
    <span className="inline-block w-1.5 h-1.5 bg-gray-400 rounded-full animate-bounce [animation-delay:0.15s]" />
    <span className="inline-block w-1.5 h-1.5 bg-gray-400 rounded-full animate-bounce [animation-delay:0.3s]" />
  </>
);

/** A settled status row in the woven timeline ("Edited workflow structure" + tick) */
const StatusSegmentRow = ({ content }: { content: string }) => (
  <div className="flex items-center gap-2" data-testid="settled-status">
    <span
      className="hero-check-micro h-3.5 w-3.5 shrink-0 text-gray-400"
      aria-hidden="true"
    />
    <span className="text-xs text-gray-400 italic">{content}</span>
  </div>
);

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
 * Woven timeline of text and status segments (global assistant replies).
 * Text segments render as markdown blocks; status segments as italic rows.
 * Status segments are completed actions and always render settled (tick).
 * The transient thinking indicator (dots) renders separately, from the
 * scalar streamingStatus, below the timeline.
 */
const SegmentTimeline = ({
  segments,
  streaming = false,
  showAddButtons = false,
  isWriteDisabled = false,
  changesByStatusIndex,
  onOpenStep,
}: {
  segments: ResponseSegment[];
  streaming?: boolean;
  showAddButtons?: boolean;
  isWriteDisabled?: boolean;
  onOpenStep?: (jobId: string) => void;
  /**
   * Per-status change sets (segment index → what that action changed),
   * rendered right under the status row that announced it. Passed while
   * streaming and after settling alike, so no blocks appear or move when
   * the reply finalizes.
   */
  changesByStatusIndex?: Map<number, WorkflowChangeSet>;
}) => (
  <>
    {segments.map((segment, index) => {
      const isLast = index === segments.length - 1;

      if (segment.type === 'status') {
        const changes = changesByStatusIndex?.get(index);
        return (
          // Timeline is append-only, so index keys are stable
          <Fragment key={index}>
            <StatusSegmentRow
              content={
                // When the steps render as blocks right below, the shorter
                // summary avoids naming them twice. Apollo versions that
                // send no summary keep their full sentence.
                changes && segment.summary ? segment.summary : segment.content
              }
            />
            {changes &&
              (changes.steps.length > 0 || changes.structure.length > 0) && (
                <div className="space-y-2" data-testid="status-step-diffs">
                  {changes.steps.map((step, stepIndex) => (
                    <StepDiffBlock
                      key={`${step.type}-${step.name}-${stepIndex}`}
                      step={step}
                      onOpenStep={onOpenStep}
                    />
                  ))}
                  {changes.structure.length > 0 && (
                    <StructureBlock rows={changes.structure} />
                  )}
                </div>
              )}
          </Fragment>
        );
      }

      return (
        <MarkdownContent
          key={index}
          content={
            streaming && isLast
              ? segment.content.replace(/\n+$/, '')
              : segment.content
          }
          showAddButtons={showAddButtons}
          isWriteDisabled={isWriteDisabled}
          className={PROSE_CLASSES}
        />
      );
    })}
  </>
);

/**
 * Merge change sets that landed under the same status row (two `changes`
 * events with no status between them).
 */
const mergeChangeSets = (sets: WorkflowChangeSet[]): WorkflowChangeSet => ({
  steps: sets.flatMap(set => set.steps),
  structure: sets.flatMap(set => set.structure),
});

/**
 * Timeline of a global assistant reply with its workflow diff blocks woven
 * in, used unchanged while the reply streams and after it settles.
 *
 * Two ways to get there, in preference order:
 *
 * 1. Streamed snapshots. Apollo sends the workflow YAML each time it
 *    mutates it, followed by the status describing that mutation, so each
 *    consecutive pair of snapshots is exactly one action. Diffing them
 *    gives what that action did, and the snapshot's pinned segment index
 *    says which status it belongs under. This is the live path, and it
 *    survives into the settled message so nothing shifts on finalize.
 *
 * 2. Whole-message fallback, for a reply reloaded from history where the
 *    snapshots are gone. One diff of the message's final YAML against the
 *    workflow as it stood before, with blocks attributed to statuses by
 *    name. Less precise, and the reason persisting snapshots server-side
 *    is worth doing.
 */
const WorkflowReplyTimeline = ({
  segments,
  snapshots,
  baselineYaml,
  finalYaml,
  streaming = false,
  showAddButtons = false,
  isWriteDisabled = false,
  onOpenStep,
}: {
  segments: ResponseSegment[];
  snapshots: WorkflowSnapshot[];
  baselineYaml: string | null;
  finalYaml: string | null;
  streaming?: boolean;
  showAddButtons?: boolean;
  isWriteDisabled?: boolean;
  onOpenStep?: (jobId: string) => void;
}) => {
  const { byStatusIndex, trailing } = useMemo(() => {
    if (snapshots.length > 0) {
      const grouped = new Map<number, WorkflowChangeSet[]>();
      const after: WorkflowChangeSet[] = [];

      for (const { segmentIndex, changes } of deriveSnapshotChanges(
        baselineYaml,
        snapshots
      )) {
        // A snapshot whose status has not drained yet (or never comes)
        // renders below the timeline rather than vanishing.
        if (segmentIndex >= segments.length) {
          after.push(changes);
          continue;
        }
        const existing = grouped.get(segmentIndex);
        if (existing) existing.push(changes);
        else grouped.set(segmentIndex, [changes]);
      }

      return {
        byStatusIndex: new Map(
          [...grouped].map(([index, sets]) => [index, mergeChangeSets(sets)])
        ),
        trailing: after.length > 0 ? mergeChangeSets(after) : null,
      };
    }

    const changes = finalYaml
      ? deriveWorkflowChanges(baselineYaml, finalYaml)
      : null;
    if (!changes) {
      return {
        byStatusIndex: new Map<number, WorkflowChangeSet>(),
        trailing: null,
      };
    }

    const assignment = assignStepDiffsToStatuses(changes.steps, segments);
    return {
      byStatusIndex: new Map(
        [...assignment.byStatusIndex].map(([index, steps]) => [
          index,
          { steps, structure: [] },
        ])
      ),
      trailing: {
        steps: assignment.unmatched,
        structure: changes.structure,
      },
    };
  }, [snapshots, baselineYaml, finalYaml, segments]);

  return (
    <>
      <SegmentTimeline
        segments={segments}
        streaming={streaming}
        showAddButtons={showAddButtons}
        isWriteDisabled={isWriteDisabled}
        changesByStatusIndex={byStatusIndex}
        onOpenStep={onOpenStep}
      />
      {trailing &&
        (trailing.steps.length > 0 || trailing.structure.length > 0) && (
          <WorkflowChangeBlocks
            steps={trailing.steps}
            structure={trailing.structure}
          />
        )}
    </>
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
  onApplyWorkflow?: ((yaml: string, messageId: string) => void) | undefined;
  onApplyJobCode?: ((code: string, messageId: string) => void) | undefined;
  onPreviewJobCode?: ((code: string, messageId: string) => void) | undefined;
  applyingMessageId?: string | null | undefined;
  previewingMessageId?: string | null | undefined;
  showAddButtons?: boolean;
  showApplyButton?: boolean;
  onRetryMessage?: (messageId: string) => void;
  isWriteDisabled?: boolean;
  streamingContent?: string | null;
  streamingStatus?: string | null;
  /** Woven text/status timeline built while a reply streams in */
  streamingSegments?: ResponseSegment[] | null;
  /** Workflow snapshots streamed so far for the in-flight reply */
  streamingSnapshots?: WorkflowSnapshot[];
  /** Snapshots retained per finalized assistant message id */
  snapshotsByMessageId?: Record<string, WorkflowSnapshot[]>;
  /** Opens a step in the IDE from a diff block */
  onOpenStep?: (jobId: string) => void;
  /**
   * Whether the global assistant is active. Gates the woven streaming
   * timeline — non-global streams keep the flat content + single scalar
   * status row behavior.
   */
  isGlobalAssistantActive?: boolean;
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
  streamingContent,
  streamingStatus,
  streamingSegments,
  streamingSnapshots = [],
  snapshotsByMessageId = {},
  onOpenStep,
  isGlobalAssistantActive = false,
}: MessageListProps) {
  const loadingRef = useRef<HTMLDivElement>(null);
  const messagesEndRef = useRef<HTMLDivElement>(null);
  const containerRef = useRef<HTMLDivElement>(null);
  const userScrolledAwayRef = useRef(false);
  const [expandedYaml, setExpandedYaml] = useState<Set<string>>(new Set());
  const [copiedMessageId, setCopiedMessageId] = useState<string | null>(null);

  useEffect(() => {
    if (messagesEndRef.current && !userScrolledAwayRef.current) {
      messagesEndRef.current.scrollIntoView({
        behavior: 'smooth',
        block: 'end',
      });
    }
  }, [messages.length]);

  useEffect(() => {
    if (isLoading && loadingRef.current && !userScrolledAwayRef.current) {
      loadingRef.current.scrollIntoView({
        behavior: 'smooth',
        block: 'end',
      });
    }
  }, [isLoading]);

  // A reply is live from its first status, well before any prose: a global
  // reply streams its statuses, workflow and diff blocks first. Scroll
  // tracking has to cover that whole window, not just the text part.
  const isStreamLive =
    !!streamingContent ||
    !!streamingStatus ||
    streamingSegments != null ||
    streamingSnapshots.length > 0;

  // Reset scroll tracking when a reply starts
  useEffect(() => {
    if (isStreamLive) {
      userScrolledAwayRef.current = false;
    }
  }, [isStreamLive]);

  // Auto-scroll during streaming, but stop if user scrolls away.
  // Uses requestAnimationFrame to coalesce multiple updates per frame
  // instead of setTimeout debounce (which defers scrolling until streaming pauses).
  const scrollRafRef = useRef<number>(0);

  useEffect(() => {
    if (streamingContent && !userScrolledAwayRef.current) {
      if (!scrollRafRef.current) {
        scrollRafRef.current = requestAnimationFrame(() => {
          scrollRafRef.current = 0;
          // Re-check on the frame it actually runs. Text arrives every 15ms
          // and a frame is ~16ms, so a scroll is almost always already
          // queued; without this a scroll scheduled before the user moved
          // still fires afterwards and drags them back down.
          if (userScrolledAwayRef.current) return;
          messagesEndRef.current?.scrollIntoView({
            behavior: 'instant',
            block: 'end',
          });
        });
      }
    }
    return () => {
      if (scrollRafRef.current) {
        cancelAnimationFrame(scrollRafRef.current);
        scrollRafRef.current = 0;
      }
    };
  }, [streamingContent]);

  // Build a unified message list: real messages + optional streaming placeholder.
  // The streaming message renders in the same loop as finalized messages,
  // so the transition from streaming → final is a seamless in-place update
  // instead of a DOM unmount/remount flash.
  // NOTE: This useMemo must be BEFORE the early return to maintain consistent
  // hook count across renders (React rules of hooks).
  const displayMessages = useMemo(() => {
    // A global reply can open with a status segment before any text has
    // streamed (Apollo edits the workflow first, then writes prose), so the
    // placeholder must exist as soon as either arrives.
    const hasStream =
      !!streamingContent ||
      (isGlobalAssistantActive && !!streamingSegments?.length);
    if (hasStream && messages.length > 0) {
      return [
        ...messages,
        {
          id: STREAMING_MESSAGE_ID,
          role: 'assistant' as const,
          content: streamingContent ?? '',
          status: 'streaming' as const,
        } as Message & { status: 'streaming' },
      ];
    }
    return messages;
  }, [messages, streamingContent, streamingSegments, isGlobalAssistantActive]);

  const isStreaming = (message: Message) => message.id === STREAMING_MESSAGE_ID;

  // Before-workflow YAML for each global assistant reply: the nearest
  // preceding user message's `code` (the client serialized the doc at send
  // time). Missing code → null → the diff treats before as an empty
  // workflow. Cheap index walk only; YAML parsing is memoized inside
  // WorkflowDiffBlocks.
  const beforeYamlByMessageId = useMemo(() => {
    const map = new Map<string, string | null>();
    messages.forEach((message, index) => {
      if (
        message.role !== 'assistant' ||
        !message.from_global ||
        !message.code
      ) {
        return;
      }
      let before: string | null = null;
      for (let i = index - 1; i >= 0; i--) {
        if (messages[i]!.role === 'user') {
          before = messages[i]!.code ?? null;
          break;
        }
      }
      map.set(message.id, before);
    });
    return map;
  }, [messages]);

  /**
   * Whether this message renders as a global reply with workflow diffs.
   * The streaming placeholder has no `from_global` flag of its own, so the
   * active-assistant prop stands in for it; a settled message needs either
   * its final YAML or retained snapshots to have anything to show.
   */
  const isGlobalReply = (message: Message): boolean =>
    isStreaming(message)
      ? isGlobalAssistantActive
      : Boolean(
          message.from_global &&
            (message.code || snapshotsByMessageId[message.id]?.length)
        );

  const snapshotsFor = (message: Message): WorkflowSnapshot[] =>
    isStreaming(message)
      ? streamingSnapshots
      : (snapshotsByMessageId[message.id] ?? []);

  /**
   * The workflow as it stood before this reply started: for a settled
   * message the indexed lookup below, for the in-flight one the last user
   * message's serialized doc, which is what the request was built from.
   */
  const baselineYamlFor = (message: Message): string | null => {
    if (!isStreaming(message)) {
      return beforeYamlByMessageId.get(message.id) ?? null;
    }
    for (let i = messages.length - 1; i >= 0; i--) {
      const candidate = messages[i];
      if (candidate?.role === 'user') return candidate.code ?? null;
    }
    return null;
  };

  // Woven text/status timeline to render instead of flat content, or null.
  // - Completed messages: persisted `response_segments` (global replies).
  // - Streaming placeholder: live `streamingSegments`. Gated on the global
  //   assistant being active as a deliberate blast-radius hold: job and
  //   workflow chat are live services, and keeping their streaming render
  //   on the flat `streamingContent` path means this PR cannot change what
  //   they display. Only Apollo's global endpoint emits status segments
  //   today; lift the gate when that changes.
  const timelineSegments = (message: Message): ResponseSegment[] | null => {
    if (isStreaming(message)) {
      return isGlobalAssistantActive && streamingSegments?.length
        ? streamingSegments
        : null;
    }
    return message.response_segments?.length ? message.response_segments : null;
  };

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
    <div
      ref={containerRef}
      className="h-full overflow-y-auto"
      data-testid="message-list"
      onScroll={() => {
        const el = containerRef.current;
        if (el && isStreamLive) {
          const isNearBottom =
            el.scrollHeight - el.scrollTop - el.clientHeight < 100;
          userScrolledAwayRef.current = !isNearBottom;
        }
      }}
    >
      {displayMessages.map(message => {
        const segments = timelineSegments(message);
        const showMessageAddButtons =
          !isStreaming(message) && showAddButtons && !message.code;

        return (
          <div
            key={message.id}
            data-role={`${message.role}-message`}
            className={cn('group px-6 py-4')}
          >
            <div className="max-w-3xl mx-auto">
              {message.role === 'assistant' ? (
                <div
                  data-testid={
                    isStreaming(message)
                      ? 'streaming-message'
                      : 'assistant-message'
                  }
                >
                  <div className="space-y-3">
                    {message.status === 'error' &&
                    !isStreaming(message) &&
                    message.content.trim() ? (
                      <div
                        className="rounded-lg border border-red-200 bg-red-50 px-3 py-2"
                        data-testid="ai-validation-error"
                      >
                        <div className="flex items-start gap-2">
                          <span className="hero-exclamation-circle h-4 w-4 text-red-600 flex-shrink-0 mt-0.5" />
                          <p className="text-sm text-red-700 leading-relaxed">
                            {message.content}
                          </p>
                        </div>
                      </div>
                    ) : segments ? (
                      isGlobalReply(message) ? (
                        <WorkflowReplyTimeline
                          segments={segments}
                          snapshots={snapshotsFor(message)}
                          baselineYaml={baselineYamlFor(message)}
                          finalYaml={message.code ?? null}
                          streaming={isStreaming(message)}
                          showAddButtons={showMessageAddButtons}
                          isWriteDisabled={isWriteDisabled}
                          onOpenStep={onOpenStep}
                        />
                      ) : (
                        <SegmentTimeline
                          segments={segments}
                          streaming={isStreaming(message)}
                          showAddButtons={showMessageAddButtons}
                          isWriteDisabled={isWriteDisabled}
                        />
                      )
                    ) : (
                      <MarkdownContent
                        content={
                          isStreaming(message)
                            ? message.content.replace(/\n+$/, '')
                            : message.content
                        }
                        showAddButtons={showMessageAddButtons}
                        isWriteDisabled={isWriteDisabled}
                        className={PROSE_CLASSES}
                      />
                    )}

                    {/* Transient thinking status — the registry clears it
                      when text or a persistent status segment arrives. */}
                    {isStreaming(message) && streamingStatus && (
                      <div
                        className="flex items-center gap-2"
                        data-testid="streaming-status"
                      >
                        <div className="flex items-center gap-1">
                          <BouncingDots />
                        </div>
                        <span className="text-xs text-gray-400 italic">
                          {streamingStatus}
                        </span>
                      </div>
                    )}

                    {/* Legacy/flat global replies (no timeline): all diff
                      blocks render together at the end of the message */}
                    {!isStreaming(message) &&
                      message.from_global &&
                      message.code &&
                      !segments && (
                        <WorkflowDiffBlocks
                          beforeYaml={
                            beforeYamlByMessageId.get(message.id) ?? null
                          }
                          afterYaml={message.code}
                          onOpenStep={onOpenStep}
                        />
                      )}

                    {/* Global replies render no "Generated Workflow" panel
                      and no action buttons: changes auto-apply (failures
                      surface their own retry paths), so the diff blocks
                      above are the entire representation of the change. */}
                    {!isStreaming(message) &&
                      message.code &&
                      !message.from_global && (
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
                                  expandedYaml.has(message.id)
                                    ? 'rotate-90'
                                    : ''
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
                              isPreviewActive={
                                previewingMessageId === message.id
                              }
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

                    {!isStreaming(message) &&
                      message.status === 'error' &&
                      !message.content.trim() && (
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

                    {!isStreaming(message) &&
                      message.status === 'processing' && (
                        <div className="flex items-center gap-2 text-gray-600">
                          <div className="flex items-center gap-1">
                            <BouncingDots />
                          </div>
                        </div>
                      )}

                    <div
                      className={cn(
                        'mt-2 flex items-center gap-2 text-xs text-gray-400',
                        isStreaming(message)
                          ? 'invisible'
                          : 'animate-[fade-in-keys_0.3s_ease-in]'
                      )}
                    >
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
        );
      })}

      {isLoading && !streamingContent && (
        <div
          ref={loadingRef}
          className="group px-6 py-4"
          data-testid="loading-indicator"
        >
          <div className="max-w-3xl mx-auto">
            <div className="flex items-center gap-2">
              <div className="flex items-center gap-1">
                <BouncingDots />
              </div>
              <span className="text-xs text-gray-400 italic">
                {streamingStatus}
              </span>
            </div>
          </div>
        </div>
      )}

      <div ref={messagesEndRef} />
    </div>
  );
}
