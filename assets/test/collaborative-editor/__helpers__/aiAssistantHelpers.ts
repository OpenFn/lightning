/**
 * AI Assistant Test Helpers
 *
 * Provides utilities for testing AI Assistant store, components, and hooks.
 * These helpers focus on creating mock AI data and setting up test scenarios
 * for the AI Assistant feature.
 *
 * @example
 * import {
 *   setupAIAssistantStoreTest,
 *   createMockAIMessage,
 *   populateAIStoreWithMessages
 * } from "./__helpers__";
 */

import { vi } from 'vitest';

import { createAIAssistantStore } from '../../../js/collaborative-editor/stores/createAIAssistantStore';
import type {
  Message,
  SessionSummary,
  JobCodeContext,
  WorkflowTemplateContext,
  SessionType,
  AIAssistantStore,
} from '../../../js/collaborative-editor/types/ai-assistant';
import type { MockPhoenixChannel } from '../mocks/phoenixChannel';

import { createMockPhoenixChannel } from './channelMocks';

/**
 * Setup result for AI Assistant store tests
 */
export interface AIAssistantStoreTestSetup {
  /** The created store instance */
  store: AIAssistantStore;
  /** Mock Phoenix channel for testing */
  mockChannel: MockPhoenixChannel;
  /** Cleanup function to call in afterEach */
  cleanup: () => void;
}

/**
 * Sets up an AI Assistant store for testing with a mocked channel
 *
 * @param initialSessionType - Optional initial session type to set
 * @returns Setup object with store, mock channel, and cleanup function
 *
 * @example
 * let setup: AIAssistantStoreTestSetup;
 *
 * beforeEach(() => {
 *   setup = setupAIAssistantStoreTest('job_code');
 * });
 *
 * afterEach(() => {
 *   setup.cleanup();
 * });
 */
export function setupAIAssistantStoreTest(
  initialSessionType?: SessionType
): AIAssistantStoreTestSetup {
  const store = createAIAssistantStore();
  const mockChannel = createMockPhoenixChannel('ai_assistant:test');

  if (initialSessionType) {
    const context =
      initialSessionType === 'job_code'
        ? createMockJobCodeContext()
        : createMockWorkflowTemplateContext();

    store.connect(initialSessionType, context);
  }

  const cleanup = () => {
    store.disconnect();
    vi.clearAllMocks();
  };

  return { store, mockChannel, cleanup };
}

/**
 * Creates a mock AI message with default values
 *
 * @param overrides - Partial message to override defaults
 * @returns Complete AI message object
 *
 * @example
 * const userMessage = createMockAIMessage({
 *   role: 'user',
 *   content: 'Help me create a workflow'
 * });
 *
 * const assistantMessage = createMockAIMessage({
 *   role: 'assistant',
 *   content: 'Here is a workflow template...'
 * });
 */
export function createMockAIMessage(overrides?: Partial<Message>): Message {
  return {
    id: `msg-${Date.now()}-${Math.random()}`,
    role: 'user',
    content: 'Test message content',
    status: 'success',
    inserted_at: new Date().toISOString(),
    ...overrides,
  };
}

/**
 * Creates a mock AI session with default values
 *
 * @param overrides - Partial session to override defaults
 * @returns Complete AI session object
 *
 * @example
 * const workflowSession = createMockAISession({
 *   session_type: 'workflow_template',
 *   workflow_name: 'My Workflow'
 * });
 */
export function createMockAISession(
  overrides?: Partial<SessionSummary>
): SessionSummary {
  return {
    id: `session-${Date.now()}-${Math.random()}`,
    title: 'Test Session',
    session_type: 'job_code',
    updated_at: new Date().toISOString(),
    message_count: 0,
    ...overrides,
  };
}

/**
 * Creates a mock job code context for testing
 *
 * @param overrides - Partial context to override defaults
 * @returns Complete job code context
 *
 * @example
 * const context = createMockJobCodeContext({
 *   job_id: 'job-123',
 *   job_adaptor: '@openfn/language-http@latest'
 * });
 */
export function createMockJobCodeContext(
  overrides?: Partial<JobCodeContext>
): JobCodeContext {
  return {
    job_id: 'job-123',
    job_body: 'fn(state => state);',
    job_adaptor: '@openfn/language-common@latest',
    job_name: 'Test Job',
    workflow_id: 'workflow-123',
    ...overrides,
  };
}

/**
 * Creates a mock workflow template context for testing
 *
 * @param overrides - Partial context to override defaults
 * @returns Complete workflow template context
 *
 * @example
 * const context = createMockWorkflowTemplateContext({
 *   workflow_id: 'workflow-123',
 *   code: 'name: My Workflow\njobs: ...'
 * });
 */
export function createMockWorkflowTemplateContext(
  overrides?: Partial<WorkflowTemplateContext>
): WorkflowTemplateContext {
  return {
    project_id: 'project-123',
    workflow_id: undefined,
    code: undefined,
    ...overrides,
  };
}

/**
 * Populates an AI store with a list of messages
 *
 * @param store - AI Assistant store instance
 * @param messages - Array of messages to add
 *
 * @example
 * populateAIStoreWithMessages(store, [
 *   createMockAIMessage({ role: 'user', content: 'Hello' }),
 *   createMockAIMessage({ role: 'assistant', content: 'Hi there!' })
 * ]);
 */
export function populateAIStoreWithMessages(
  store: AIAssistantStore,
  messages: Message[]
): void {
  // Directly set messages via store's internal state
  // This simulates messages received from the server
  messages.forEach(message => {
    store._addMessage(message);
  });
}

/**
 * Asserts that a message exists in the store
 *
 * @param store - AI Assistant store instance
 * @param messageId - ID of the message to find
 * @throws Error if message not found
 *
 * @example
 * expectAIMessageInStore(store, 'msg-123');
 */
export function expectAIMessageInStore(
  store: AIAssistantStore,
  messageId: string
): void {
  const state = store.getSnapshot();
  const message = state.messages.find(m => m.id === messageId);

  if (!message) {
    throw new Error(`Expected message "${messageId}" to be in store`);
  }
}

/**
 * Asserts that the store is in connected state
 *
 * @param store - AI Assistant store instance
 * @throws Error if store is not connected
 *
 * @example
 * expectAIStoreConnected(store);
 */
export function expectAIStoreConnected(store: AIAssistantStore): void {
  const state = store.getSnapshot();

  if (state.connectionState !== 'connected') {
    throw new Error(
      `Expected store to be connected, but state is "${state.connectionState}"`
    );
  }
}

/**
 * Asserts that the store has a specific session type
 *
 * @param store - AI Assistant store instance
 * @param expectedType - Expected session type
 * @throws Error if session type doesn't match
 *
 * @example
 * expectAIStoreSessionType(store, 'job_code');
 */
export function expectAIStoreSessionType(
  store: AIAssistantStore,
  expectedType: SessionType
): void {
  const state = store.getSnapshot();

  if (state.sessionType !== expectedType) {
    throw new Error(
      `Expected session type to be "${expectedType}", but got "${state.sessionType}"`
    );
  }
}

/**
 * Creates a conversation history with user and assistant messages
 *
 * @param exchanges - Array of [user message, assistant response] tuples
 * @returns Array of AI messages alternating user/assistant
 *
 * @example
 * const conversation = createMockConversation([
 *   ['Help me create a workflow', 'Here is a workflow template...'],
 *   ['Can you add error handling?', 'Sure, I've added error handling...']
 * ]);
 */
export function createMockConversation(
  exchanges: Array<[string, string]>
): Message[] {
  const messages: Message[] = [];

  exchanges.forEach(([userContent, assistantContent], index) => {
    messages.push(
      createMockAIMessage({
        id: `msg-user-${index}`,
        role: 'user',
        content: userContent,
        inserted_at: new Date(Date.now() + index * 1000).toISOString(),
      })
    );

    messages.push(
      createMockAIMessage({
        id: `msg-assistant-${index}`,
        role: 'assistant',
        content: assistantContent,
        inserted_at: new Date(Date.now() + index * 1000 + 500).toISOString(),
      })
    );
  });

  return messages;
}

/**
 * Creates a workflow YAML string for testing
 *
 * @param name - Workflow name
 * @param jobCount - Number of jobs to include
 * @returns YAML string
 *
 * @example
 * const yaml = createMockWorkflowYAML('Data Pipeline', 2);
 */
export function createMockWorkflowYAML(
  name: string = 'Test Workflow',
  jobCount: number = 1
): string {
  const jobs = Array.from({ length: jobCount }, (_, i) => ({
    id: `job-${i + 1}`,
    name: `Job ${i + 1}`,
    adaptor: '@openfn/language-common@latest',
    body: `fn(state => state);`,
  }));

  const jobsYAML = jobs
    .map(
      job => `  ${job.id}:
    name: ${job.name}
    adaptor: ${job.adaptor}
    body: |
      ${job.body}`
    )
    .join('\n');

  return `name: ${name}
jobs:
${jobsYAML}
triggers:
  - type: webhook
    enabled: true
edges:
  - source_trigger_id: trigger_1
    target_job_id: job-1
    condition_type: always`;
}

/**
 * Waits for the store to reach a specific connection state
 *
 * @param store - AI Assistant store instance
 * @param targetState - Target connection state
 * @param timeout - Max time to wait in ms (default: 1000)
 * @returns Promise that resolves when state is reached
 *
 * @example
 * await waitForConnectionState(store, 'connected');
 */
export async function waitForConnectionState(
  store: AIAssistantStore,
  targetState: 'connected' | 'disconnected' | 'connecting' | 'error',
  timeout: number = 1000
): Promise<void> {
  const startTime = Date.now();

  return new Promise((resolve, reject) => {
    const checkState = () => {
      const state = store.getSnapshot();

      if (state.connectionState === targetState) {
        resolve();
        return;
      }

      if (Date.now() - startTime > timeout) {
        reject(
          new Error(
            `Timeout waiting for connection state "${targetState}". Current: "${state.connectionState}"`
          )
        );
        return;
      }

      setTimeout(checkState, 10);
    };

    checkState();
  });
}

/**
 * Waits for messages to appear in the store
 *
 * @param store - AI Assistant store instance
 * @param expectedCount - Expected number of messages
 * @param timeout - Max time to wait in ms (default: 1000)
 * @returns Promise that resolves when message count is reached
 *
 * @example
 * await waitForMessages(store, 2);
 */
export async function waitForMessages(
  store: AIAssistantStore,
  expectedCount: number,
  timeout: number = 1000
): Promise<void> {
  const startTime = Date.now();

  return new Promise((resolve, reject) => {
    const checkMessages = () => {
      const state = store.getSnapshot();

      if (state.messages.length >= expectedCount) {
        resolve();
        return;
      }

      if (Date.now() - startTime > timeout) {
        reject(
          new Error(
            `Timeout waiting for ${expectedCount} messages. Current: ${state.messages.length}`
          )
        );
        return;
      }

      setTimeout(checkMessages, 10);
    };

    checkMessages();
  });
}
