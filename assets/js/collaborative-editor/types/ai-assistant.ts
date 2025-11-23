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
 * Message represents a single chat message in the AI assistant
 */
export interface Message {
  id: string;
  content: string;
  code?: string; // Optional workflow YAML for workflow_template mode
  role: MessageRole;
  status: MessageStatus;
  inserted_at: string; // ISO 8601 timestamp
  user_id?: string;
}

/**
 * Session context for job_code mode
 */
export interface JobCodeContext {
  job_id: string;
  attach_code?: boolean; // Include job code in AI context
  attach_logs?: boolean; // Include run logs in AI context
  follow_run_id?: string; // Optional run ID to follow for logs
}

/**
 * Session context for workflow_template mode
 */
export interface WorkflowTemplateContext {
  project_id: string;
  workflow_id?: string; // Optional for editing existing workflows
  code?: string; // Current workflow YAML
  errors?: string; // Validation errors to fix
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
  // Connection state
  connectionState: ConnectionState;
  connectionError?: string;

  // Session management
  sessionId: string | null;
  sessionType: SessionType | null;

  // Messages
  messages: Message[];

  // UI state
  isLoading: boolean; // True when sending a message
  isSending: boolean; // True when actively sending (for button state)

  // Session list / history
  sessionList: SessionSummary[];
  sessionListLoading: boolean;
  sessionListPagination: {
    total_count: number;
    has_next_page: boolean;
    has_prev_page: boolean;
  } | null;

  // Context for session creation
  jobCodeContext: JobCodeContext | null;
  workflowTemplateContext: WorkflowTemplateContext | null;

  // Disclaimer
  hasReadDisclaimer: boolean;
}

/**
 * AI Assistant store interface following CQS pattern
 */
export interface AIAssistantStore {
  // Core store interface (useSyncExternalStore)
  subscribe: (listener: () => void) => () => void;
  getSnapshot: () => AIAssistantState;
  withSelector: <T>(selector: (state: AIAssistantState) => T) => () => T;

  // Commands - State mutations

  // Connection management
  connect: (
    sessionType: SessionType,
    context: JobCodeContext | WorkflowTemplateContext,
    sessionId?: string
  ) => void;
  disconnect: () => void;

  // Message operations
  sendMessage: (content: string, options?: MessageOptions) => void;
  retryMessage: (messageId: string) => void;

  // Session management
  clearSession: () => void;
  loadSession: (sessionId: string) => void;

  // Session list
  loadSessionList: () => void;

  // Disclaimer
  markDisclaimerRead: () => void;

  // Session persistence
  loadStoredSessionForWorkflow: (workflowId: string) => string | null;

  // Internal state updates (called by channel hook)
  _setConnectionState: (state: ConnectionState, error?: string) => void;
  _setSession: (session: Session) => void;
  _clearSession: () => void;
  _addMessage: (message: Message) => void;
  _updateMessageStatus: (messageId: string, status: MessageStatus) => void;
  _setSessionList: (response: SessionListResponse) => void;
}

/**
 * Options for sending a message
 */
export interface MessageOptions {
  // For job_code mode
  attach_code?: boolean;
  attach_logs?: boolean;

  // For workflow_template mode
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
