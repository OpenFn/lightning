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
}

/**
 * Session context for workflow_template mode
 */
export interface WorkflowTemplateContext {
  project_id: string;
  workflow_id?: string;
  code?: string;
  errors?: string;
  content?: string;
}

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

  sessionList: SessionSummary[];
  sessionListLoading: boolean;
  sessionListPagination: {
    total_count: number;
    has_next_page: boolean;
    has_prev_page: boolean;
  } | null;

  jobCodeContext: JobCodeContext | null;
  workflowTemplateContext: WorkflowTemplateContext | null;

  hasReadDisclaimer: boolean;
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

  markDisclaimerRead: () => void;

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
