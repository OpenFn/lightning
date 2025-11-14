/**
 * Workflow Store Test Helpers
 *
 * Utility functions for testing workflow store functionality. These helpers
 * simplify the setup of WorkflowStore instances with Y.Doc and provider
 * connections for testing.
 *
 * Since WorkflowStore is complex and commonly used in tests, these helpers
 * consolidate the repetitive Y.Doc + provider initialization logic.
 *
 * Usage:
 *   const { store, ydoc, cleanup } = setupWorkflowStoreTest();
 *   // ... run test
 *   cleanup();
 */

import * as Y from 'yjs';
import { vi } from 'vitest';
import type { Channel } from 'phoenix';
import type { PhoenixChannelProvider } from 'y-phoenix-channel';

import { createWorkflowStore } from '../../../js/collaborative-editor/stores/createWorkflowStore';
import type { WorkflowStoreInstance } from '../../../js/collaborative-editor/stores/createWorkflowStore';
import type { Session } from '../../../js/collaborative-editor/types/session';

import {
  createMockPhoenixChannel,
  createMockPhoenixChannelProvider,
  type MockPhoenixChannel,
  type MockPhoenixChannelProvider,
} from './channelMocks';

/**
 * Result of setting up a workflow store test
 */
export interface WorkflowStoreTestSetup {
  /** The workflow store instance */
  store: WorkflowStoreInstance;
  /** The Y.Doc instance (typed as WorkflowDoc) */
  ydoc: Session.WorkflowDoc;
  /** Mock Phoenix channel */
  mockChannel: MockPhoenixChannel;
  /** Mock channel provider */
  mockProvider: MockPhoenixChannelProvider & { channel: Channel };
  /** Cleanup function to call after test */
  cleanup: () => void;
}

/**
 * Sets up a workflow store test with Y.Doc and provider connection
 *
 * This helper creates a WorkflowStore instance, initializes a Y.Doc with
 * workflow structure, sets up mock channel and provider, and connects them
 * together. It provides a consistent starting point for workflow store tests.
 *
 * The Y.Doc is initialized with the basic workflow structure (workflow map,
 * jobs array, triggers array, edges array, positions map, errors map) but
 * all are empty. Use the optional `ydoc` parameter to provide a pre-populated
 * Y.Doc created with `createWorkflowYDoc()` from workflowFactory.
 *
 * @param ydoc - Optional pre-configured Y.Doc (defaults to empty workflow)
 * @param topic - Optional channel topic (defaults to "test:workflow")
 * @returns Test setup with store, ydoc, mocks, and cleanup function
 *
 * @example
 * // Basic usage with empty workflow
 * test("workflow store functionality", () => {
 *   const { store, ydoc, cleanup } = setupWorkflowStoreTest();
 *
 *   // Y.Doc is already connected, ready to use
 *   expect(store.isConnected).toBe(true);
 *
 *   cleanup();
 * });
 *
 * @example
 * // Usage with pre-populated Y.Doc
 * import { createWorkflowYDoc } from "./__helpers__";
 *
 * test("workflow with jobs", () => {
 *   const ydoc = createWorkflowYDoc({
 *     jobs: {
 *       "job-a": { id: "job-a", name: "Job A", adaptor: "@openfn/language-common" }
 *     }
 *   });
 *
 *   const { store, cleanup } = setupWorkflowStoreTest(ydoc);
 *
 *   const state = store.getSnapshot();
 *   expect(state.jobs).toHaveLength(1);
 *
 *   cleanup();
 * });
 *
 * @example
 * // Configuring channel responses
 * test("workflow save", async () => {
 *   const { store, mockChannel, cleanup } = setupWorkflowStoreTest();
 *
 *   // Configure mock channel for save_workflow
 *   mockChannel.push = vi.fn().mockReturnValue({
 *     receive: (status: string, callback: (response?: any) => void) => {
 *       if (status === "ok") {
 *         callback({ saved_at: "2025-01-01", lock_version: 1 });
 *       }
 *       return { receive: () => {} };
 *     }
 *   });
 *
 *   await store.saveWorkflow();
 *
 *   cleanup();
 * });
 */
export function setupWorkflowStoreTest(
  ydoc?: Y.Doc,
  topic: string = 'test:workflow'
): WorkflowStoreTestSetup {
  const store = createWorkflowStore();

  // Create or use provided Y.Doc
  const workflowDoc = (ydoc ??
    createEmptyWorkflowYDoc()) as Session.WorkflowDoc;

  // Create mock channel and provider
  const mockChannel = createMockPhoenixChannel(topic);
  const mockProvider = createMockPhoenixChannelProvider(
    mockChannel
  ) as MockPhoenixChannelProvider & { channel: Channel };

  // Attach the Y.Doc to the provider (required by WorkflowStore)
  (mockProvider as any).doc = workflowDoc;

  // Connect store to Y.Doc and provider
  store.connect(workflowDoc, mockProvider as any);

  return {
    store,
    ydoc: workflowDoc,
    mockChannel,
    mockProvider,
    cleanup: () => {
      store.disconnect();
    },
  };
}

/**
 * Creates an empty Y.Doc with workflow structure
 *
 * Initializes a Y.Doc with the expected workflow structure:
 * - workflow map (empty)
 * - jobs array (empty)
 * - triggers array (empty)
 * - edges array (empty)
 * - positions map (empty)
 * - errors map (empty)
 *
 * This is used internally by setupWorkflowStoreTest when no custom Y.Doc
 * is provided. For tests that need pre-populated workflows, use
 * `createWorkflowYDoc()` from workflowFactory instead.
 *
 * @returns Y.Doc with empty workflow structure
 *
 * @example
 * const ydoc = createEmptyWorkflowYDoc();
 * expect(ydoc.getArray("jobs").length).toBe(0);
 */
export function createEmptyWorkflowYDoc(): Y.Doc {
  const ydoc = new Y.Doc();

  // Initialize workflow map (empty)
  ydoc.getMap('workflow');

  // Initialize arrays (empty)
  ydoc.getArray('jobs');
  ydoc.getArray('triggers');
  ydoc.getArray('edges');

  // Initialize positions map (empty)
  ydoc.getMap('positions');

  // Initialize errors map (empty)
  ydoc.getMap('errors');

  return ydoc;
}

/**
 * Creates a minimal workflow Y.Doc with basic workflow metadata
 *
 * Useful for tests that need a workflow with an ID and name but no jobs,
 * triggers, or edges yet.
 *
 * @param id - Workflow ID (defaults to "workflow-test")
 * @param name - Workflow name (defaults to "Test Workflow")
 * @param lockVersion - Lock version (defaults to null for new workflow)
 * @returns Y.Doc with workflow metadata
 *
 * @example
 * const ydoc = createMinimalWorkflowYDoc("wf-123", "My Workflow");
 * const workflowMap = ydoc.getMap("workflow");
 * expect(workflowMap.get("id")).toBe("wf-123");
 */
export function createMinimalWorkflowYDoc(
  id: string = 'workflow-test',
  name: string = 'Test Workflow',
  lockVersion: number | null = null
): Y.Doc {
  const ydoc = createEmptyWorkflowYDoc();

  const workflowMap = ydoc.getMap('workflow');
  workflowMap.set('id', id);
  workflowMap.set('name', name);
  workflowMap.set('lock_version', lockVersion);
  workflowMap.set('deleted_at', null);
  workflowMap.set('concurrency', null);
  workflowMap.set('enable_job_logs', false);

  return ydoc;
}
