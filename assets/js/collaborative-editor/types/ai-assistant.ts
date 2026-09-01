/**
 * # AI Assistant Types
 *
 * Type definitions for the AI Assistant feature in the collaborative editor.
 * Supports two session types: job_code and workflow_template.
 */

/**
 * Session type determines the AI assistant mode
 * - job_code: AI assistance for individual job implementation
 * - workflow_template: AI-powered workflow generation
 */
export type SessionType = 'job_code' | 'workflow_template';

/**
 * Message role identifies who sent the message
 */
export type MessageRole = 'user' | 'assistant';

/**
 * Message status tracks the lifecycle of a message
 * - pending: User message waiting to be processed
 * - processing: AI is generating a response
 * - success: AI response completed successfully
 * - error: AI request failed
 * - cancelled: Message was cancelled by user
 */
export type MessageStatus =
  | 'pending'
  | 'processing'
  | 'success'
  | 'error'
  | 'cancelled';

/**
 * User info attached to a message for attribution in collaborative sessions
 */
export interface MessageUser {
  id: string;
  first_name: string | null;
  last_name: string | null;
}

/**
 * Message id of the in-flight streaming placeholder. Applies triggered
 * mid-stream carry this id instead of a persisted message id.
 */
export const STREAMING_MESSAGE_ID = '__streaming__' as const;

/**
 * A single entry in an assistant message's display timeline: either a chunk
 * of answer text or a status update ("Adding step...") woven between texts.
 * Mirrors the backend `response_segments` contract
 * (`{"type": "text" | "status", "content": string}`).
 */
export interface ResponseSegment {
  type: 'text' | 'status';
  content: string;
  /**
   * Shorter line to show when this segment's steps are rendered as detail
   * below it, so the step names are not printed twice. Falls back to
   * `content` when absent.
   */
  summary?: string;
  /**
   * Workflow steps this action touched, as data rather than names buried
   * in `content`. Present only on status segments, and only from an Apollo
   * that reports them — absent means "not reported", not "touched none".
   */
  steps?: SegmentStep[];
}

/** A workflow step a status segment acted on */
export interface SegmentStep {
  /** The workflow YAML key for the step: the stable identifier */
  key: string;
  /** Display name at the time the action ran */
  name?: string;
}

/**
 * Message represents a single chat message in the AI assistant
 */
export interface Message {
  id: string;
  content: string;
  code?: string;
  role: MessageRole;
  status: MessageStatus;
  inserted_at: string;
  user_id?: string;
  user?: MessageUser | null;
  job_id?: string;
  /**
   * True when this message came from the global AI assistant. Global
   * messages carry a full workflow YAML in `code` and never a `job_id`.
   */
  from_global?: boolean;
  /**
   * Interleaved text/status timeline for global assistant replies.
   * `null`/absent for legacy and non-global messages (render flat `content`).
   */
  response_segments?: ResponseSegment[] | null;
}

/**
 * Session context for job_code mode
 */
export interface JobCodeContext {
  job_id: string;
  attach_code?: boolean;
  attach_logs?: boolean;
  attach_io_data?: boolean;
  step_id?: string;
  follow_run_id?: string;
  content?: string;

  job_name?: string;
  job_body?: string;
  job_adaptor?: string;
  workflow_id?: string;

  // Full serialized workflow YAML attached by global chat (sent as the message
  // `code`). Present even with a step open, so it lives on the job context too.
  code?: string;
}

/**
 * Session context for workflow_template mode
 */
export type WorkflowTemplateContext =
  | {
      project_id: string;
      workflow_id?: string;

      code?: string;
      errors?: string;
      content?: string;
    }
  | {
      job_id: string;
      attach_code?: boolean;
      attach_logs?: boolean;
      attach_io_data?: boolean;
      step_id?: string;
      follow_run_id?: string;
      content?: string;

      job_name?: string;
      job_body?: string;
      job_adaptor?: string;

      workflow_id?: string;
      project_id: string;

      // Full serialized workflow YAML attached by global chat (sent as the
      // message `code`), present even when a step is open.
      code?: string;
    };

/**
 * Session metadata returned from the backend
 */
export interface Session {
  id: string;
  session_type: SessionType;
  messages: Message[];
}

/**
 * Connection state for the Phoenix Channel
 */
export type ConnectionState =
  | 'disconnected'
  | 'connecting'
  | 'connected'
  | 'error';

/**
 * Tracks a workflow YAML that was applied to the canvas early, during
 * streaming, so the auto-apply of the final new_message can be skipped
 * when it carries the same YAML (re-importing identical content dirties
 * the Y.Doc and shows a false "unsaved changes" indicator).
 *
 * Only set after a successful import, so failed applies never need to
 * reset it. `saveFailed` records that the post-import auto-save of a new
 * workflow is still owed.
 */
/**
 * A workflow YAML snapshot captured mid-stream, pinned to the position it
 * occupied in the segment timeline. See `streamingSnapshots`.
 */
export interface WorkflowSnapshot {
  yaml: string;
  /** Number of timeline segments that had drained when this snapshot landed */
  segmentIndex: number;
}

export interface StreamingApplyState {
  yaml: string;
  saveFailed: boolean;
}

/**
 * AI Assistant state managed by the store
 */
export interface AIAssistantState {
  connectionState: ConnectionState;
  connectionError: string | undefined;

  sessionId: string | null;
  sessionType: SessionType | null;

  messages: Message[];

  isLoading: boolean;
  isSending: boolean;

  streamingContent: string | null;
  streamingStatus: string | null;
  streamingChanges: Record<string, unknown> | null;
  /**
   * Woven text/status timeline built up while a reply streams in.
   * Append-only during a stream; fed exclusively by the char drain so wire
   * order is preserved. Reset alongside the other streaming fields.
   */
  streamingSegments: ResponseSegment[];
  /**
   * Workflow YAML snapshots streamed during a reply, in wire order.
   *
   * Apollo sends a `changes` event at every point it actually mutates the
   * workflow, immediately followed by the settled status that describes
   * that mutation. `segmentIndex` records how many segments the timeline
   * held when the snapshot drained, which is exactly the index of the
   * status segment that follows it — so snapshot N is the "after" state
   * for status N, and snapshot N-1 is its "before".
   *
   * Fed through the same char drain as status segments so a snapshot can
   * never overtake the text that preceded it on the wire. Reset alongside
   * the other streaming fields.
   */
  streamingSnapshots: WorkflowSnapshot[];
  /**
   * Snapshots handed over from `streamingSnapshots` when a reply finalizes,
   * keyed by the assistant message id the server assigned it.
   *
   * The id is only known at `new_message`, so the live stream cannot record
   * them under it directly. Keeping them here means a message renders the
   * same per-status diffs the moment it settles as it did while streaming,
   * instead of collapsing to a single whole-message diff. Session-scoped:
   * a reload has no snapshots and falls back to the whole-message diff
   * until they are persisted server-side.
   */
  snapshotsByMessageId: Record<string, WorkflowSnapshot[]>;
  streamingApply: StreamingApplyState | null;
  /**
   * The canvas as it stood after the assistant's last import, serialized by
   * `serializeCanvasForComparison`. Undo compares against it to tell whether
   * the workflow has been edited since, and skip the confirmation when it has
   * not. Session-scoped: a reload has none, and undo then always confirms.
   */
  appliedCanvasYaml: string | null;

  sessionList: SessionSummary[];
  sessionListLoading: boolean;
  sessionListPagination: {
    total_count: number;
    has_next_page: boolean;
    has_prev_page: boolean;
  } | null;

  jobCodeContext: JobCodeContext | null;
  workflowTemplateContext: WorkflowTemplateContext | null;
}

/**
 * AI Assistant store interface following CQS pattern
 */
export interface AIAssistantStore {
  subscribe: (listener: () => void) => () => void;
  getSnapshot: () => AIAssistantState;
  withSelector: <T>(selector: (state: AIAssistantState) => T) => () => T;

  connect: (
    sessionType: SessionType,
    context: JobCodeContext | WorkflowTemplateContext,
    sessionId?: string
  ) => void;
  disconnect: () => void;

  setMessageSending: () => void;
  retryMessage: (messageId: string) => void;

  clearSession: () => void;
  loadSession: (sessionId: string) => void;
  updateContext: (context: Partial<JobCodeContext>) => void;

  loadSessionList: (options?: {
    offset?: number;
    limit?: number;
    append?: boolean;
  }) => Promise<void>;

  _setConnectionState: (state: ConnectionState, error?: string) => void;
  _setSession: (session: Session) => void;
  _clearSession: () => void;
  _clearSessionList: () => void;
  _prependSession: (session: SessionSummary) => void;
  _addMessage: (message: Message) => void;
  _updateMessageStatus: (messageId: string, status: MessageStatus) => void;
  _setSessionList: (response: SessionListResponse) => void;
  _appendSessionList: (response: SessionListResponse) => void;
  _initializeContext: (
    sessionType: SessionType,
    context: JobCodeContext | WorkflowTemplateContext
  ) => void;
  _setProcessingState: (isProcessing: boolean) => void;
  _appendStreamingChunk: (content: string) => void;
  _appendStreamingSegment: (segment: ResponseSegment) => void;
  setStreamingStatus: (text: string | null) => void;
  _appendStreamingSnapshot: (yaml: string) => void;
  _setStreamingChanges: (changes: Record<string, unknown>) => void;
  _clearStreaming: () => void;
  _setStreamingApply: (yaml: string) => void;
  _setStreamingApplySaveFailed: (saveFailed: boolean) => void;
  _clearStreamingApply: () => void;
  _setAppliedCanvasYaml: (yaml: string | null) => void;
  _connectChannel: (channelProvider: unknown) => () => void;
}

/**
 * Options for sending a message
 */
export interface MessageOptions {
  attach_code?: boolean;
  attach_logs?: boolean;
  attach_io_data?: boolean;
  step_id?: string;

  code?: string;
  errors?: string;

  use_global_assistant?: boolean;
  page?: string;
}

/**
 * Session summary for session list/history
 */
export interface SessionSummary {
  id: string;
  title: string;
  session_type: SessionType;
  message_count: number;
  updated_at: string; // ISO 8601 timestamp
  job_name?: string;
  workflow_name?: string;
  project_name?: string;
}

/**
 * Paginated session list response
 */
export interface SessionListResponse {
  sessions: SessionSummary[];
  pagination: {
    total_count: number;
    has_next_page: boolean;
    has_prev_page: boolean;
  };
}

/**
 * Channel events sent from backend to frontend
 */
export type ChannelEvent =
  | {
      event: 'new_message';
      payload: { message: Message };
    }
  | {
      event: 'message_status_changed';
      payload: { message_id: string; status: MessageStatus };
    };
