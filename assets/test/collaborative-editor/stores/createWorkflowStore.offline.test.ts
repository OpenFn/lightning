/**
 * WorkflowStore Offline Editing Tests
 *
 * Tests for offline editing behavior, verifying that Y.Doc changes
 * propagate to Immer state even when the provider is disconnected.
 *
 * Critical Behavior:
 * - Y.Doc observers must remain active during disconnection
 * - Mutations should update Y.Doc and trigger observers
 * - Immer state should update from observers
 * - React components should re-render
 * - Changes should sync when reconnected
 *
 * Bug Context:
 * Previously, disconnect() was cleaning up ALL observers including
 * Y.Doc observers. This caused offline edits to update Y.Doc but
 * not propagate to Immer state, resulting in a "ghost workflow"
 * where changes were stored but not visible.
 *
 * Fix:
 * Separated observer cleanup into ydocCleanups (persist) and
 * channelCleanups (cleaned on disconnect). Y.Doc observers now
 * remain active during disconnection.
 */

import { describe, test, expect, beforeEach, vi } from 'vitest';
import * as Y from 'yjs';
import type { Channel } from 'phoenix';

import { createWorkflowStore } from '../../../js/collaborative-editor/stores/createWorkflowStore';
import type { WorkflowStoreInstance } from '../../../js/collaborative-editor/stores/createWorkflowStore';
import type { PhoenixChannelProvider } from 'y-phoenix-channel';
import type { Session } from '../../../js/collaborative-editor/types/session';

describe('WorkflowStore - Offline Editing', () => {
  let store: WorkflowStoreInstance;
  let ydoc: Session.WorkflowDoc;
  let mockChannel: Channel;
  let mockProvider: PhoenixChannelProvider & { channel: Channel };

  beforeEach(() => {
    // Create fresh store and Y.Doc instances
    store = createWorkflowStore();
    ydoc = new Y.Doc() as Session.WorkflowDoc;

    // Mock Phoenix Channel
    mockChannel = {
      push: vi.fn(),
      on: vi.fn(),
      off: vi.fn(),
    } as unknown as Channel;

    // Create mock provider with channel
    mockProvider = {
      channel: mockChannel,
      synced: true,
      awareness: null,
      doc: ydoc,
    } as unknown as PhoenixChannelProvider & { channel: Channel };

    // Initialize workflow in Y.Doc
    const workflowMap = ydoc.getMap('workflow');
    workflowMap.set('id', 'workflow-123');
    workflowMap.set('name', 'Test Workflow');
    workflowMap.set('lock_version', null);

    // Initialize empty arrays and maps
    ydoc.getArray('jobs');
    ydoc.getArray('triggers');
    ydoc.getArray('edges');
    ydoc.getMap('positions');
    ydoc.getMap('errors');

    // Connect store to Y.Doc and provider
    store.connect(ydoc, mockProvider);
  });

  test('job name changes propagate to state while offline', () => {
    // Add a job while online
    store.addJob({
      id: 'job-1',
      name: 'Initial Job Name',
      adaptor: '@openfn/language-common@latest',
    });

    // Verify job was added
    const initialState = store.getSnapshot();
    expect(initialState.jobs).toHaveLength(1);
    expect(initialState.jobs[0]?.name).toBe('Initial Job Name');

    // Disconnect (simulate offline)
    store.disconnect();

    // Verify store shows disconnected
    expect(store.isConnected).toBe(true); // ydoc still exists
    expect(store.ydoc).toBe(ydoc); // ydoc reference preserved

    // Update job name while offline
    store.updateJobName('job-1', 'Updated Offline Name');

    // CRITICAL: Verify state updated despite being offline
    const offlineState = store.getSnapshot();
    expect(offlineState.jobs).toHaveLength(1);
    expect(offlineState.jobs[0]?.name).toBe('Updated Offline Name');

    // Verify Y.Doc also has the change
    const jobsArray = ydoc.getArray('jobs');
    const jobs = jobsArray.toArray() as Y.Map<unknown>[];
    expect(jobs[0]?.get('name')).toBe('Updated Offline Name');
  });

  test('job updates propagate to state while offline', () => {
    // Add a job while online
    store.addJob({
      id: 'job-1',
      name: 'Test Job',
      adaptor: '@openfn/language-common@latest',
    });

    // Disconnect
    store.disconnect();

    // Update multiple fields while offline
    store.updateJob('job-1', {
      name: 'New Name',
      adaptor: '@openfn/language-http@latest',
    });

    // Verify state updated
    const state = store.getSnapshot();
    expect(state.jobs[0]?.name).toBe('New Name');
    expect(state.jobs[0]?.adaptor).toBe('@openfn/language-http@latest');
  });

  test('workflow metadata changes propagate while offline', () => {
    // Disconnect
    store.disconnect();

    // Update workflow while offline
    store.updateWorkflow({
      name: 'Updated Workflow Name',
      concurrency: 5,
    });

    // Verify state updated
    const state = store.getSnapshot();
    expect(state.workflow?.name).toBe('Updated Workflow Name');
    expect(state.workflow?.concurrency).toBe(5);
  });

  test('multiple offline changes accumulate correctly', () => {
    // Add initial jobs
    store.addJob({
      id: 'job-1',
      name: 'Job 1',
      adaptor: '@openfn/language-common@latest',
    });
    store.addJob({
      id: 'job-2',
      name: 'Job 2',
      adaptor: '@openfn/language-common@latest',
    });

    // Add edge
    store.addEdge({
      id: 'edge-1',
      source_job_id: 'job-1',
      target_job_id: 'job-2',
      condition_type: 'on_job_success',
    });

    // Disconnect
    store.disconnect();

    // Make multiple offline changes
    store.updateJobName('job-1', 'Updated Job 1');
    store.updateJobName('job-2', 'Updated Job 2');
    store.updateEdge('edge-1', {
      condition_type: 'always',
    });

    // Verify all changes in state
    const state = store.getSnapshot();
    expect(state.jobs[0]?.name).toBe('Updated Job 1');
    expect(state.jobs[1]?.name).toBe('Updated Job 2');
    expect(state.edges[0]?.condition_type).toBe('always');
  });

  test('reconnection preserves Y.Doc observers', () => {
    // Add a job
    store.addJob({
      id: 'job-1',
      name: 'Initial Name',
      adaptor: '@openfn/language-common@latest',
    });

    // Disconnect
    store.disconnect();

    // Make offline change
    store.updateJobName('job-1', 'Offline Name');

    // Verify change applied
    expect(store.getSnapshot().jobs[0]?.name).toBe('Offline Name');

    // Reconnect with SAME ydoc (simulates reconnection scenario)
    const newMockChannel = {
      push: vi.fn(),
      on: vi.fn(),
      off: vi.fn(),
    } as unknown as Channel;

    const newMockProvider = {
      channel: newMockChannel,
      synced: true,
      awareness: null,
      doc: ydoc, // SAME ydoc
    } as unknown as PhoenixChannelProvider & { channel: Channel };

    store.connect(ydoc, newMockProvider);

    // Verify offline change still visible after reconnect
    expect(store.getSnapshot().jobs[0]?.name).toBe('Offline Name');

    // Make another change after reconnect
    store.updateJobName('job-1', 'Post-Reconnect Name');

    // Verify new change applied
    expect(store.getSnapshot().jobs[0]?.name).toBe('Post-Reconnect Name');
  });

  test('observers fire correctly after disconnect/reconnect cycle', () => {
    // Add a job
    store.addJob({
      id: 'job-1',
      name: 'Job 1',
      adaptor: '@openfn/language-common@latest',
    });

    // Track state changes via subscription
    const stateChanges: string[] = [];
    const unsubscribe = store.subscribe(() => {
      const state = store.getSnapshot();
      stateChanges.push(state.jobs[0]?.name || 'unknown');
    });

    // Disconnect
    store.disconnect();

    // Make offline change
    store.updateJobName('job-1', 'Offline Change');

    // Verify observer fired (subscription was called)
    expect(stateChanges).toContain('Offline Change');

    // Reconnect
    const newMockChannel = {
      push: vi.fn(),
      on: vi.fn(),
      off: vi.fn(),
    } as unknown as Channel;

    const newMockProvider = {
      channel: newMockChannel,
      synced: true,
      awareness: null,
      doc: ydoc,
    } as unknown as PhoenixChannelProvider & { channel: Channel };

    store.connect(ydoc, newMockProvider);

    // Make post-reconnect change
    store.updateJobName('job-1', 'Post-Reconnect Change');

    // Verify observer still firing
    expect(stateChanges).toContain('Post-Reconnect Change');

    unsubscribe();
  });

  test('undo/redo works during offline mode', async () => {
    // Add a job
    store.addJob({
      id: 'job-1',
      name: 'Job 1',
      adaptor: '@openfn/language-common@latest',
    });

    // Verify undoManager exists and job was added
    const state = store.getSnapshot();
    expect(state.undoManager).toBeDefined();
    expect(store.getSnapshot().jobs).toHaveLength(1);

    // Wait for captureTimeout to pass (UndoManager groups edits within 500ms)
    // This ensures addJob and updateJobName are separate undo items
    await new Promise(resolve => setTimeout(resolve, 600));

    // Disconnect
    store.disconnect();

    // Verify canUndo (should be able to undo job creation)
    expect(store.canUndo()).toBe(true);

    // Make change offline
    store.updateJobName('job-1', 'Changed Name');
    expect(store.getSnapshot().jobs[0]?.name).toBe('Changed Name');

    // Undo while offline (should revert name change only, not remove job)
    expect(store.canUndo()).toBe(true);
    store.undo();

    // After undo, job should still exist with original name
    expect(store.getSnapshot().jobs).toHaveLength(1);
    expect(store.getSnapshot().jobs[0]?.name).toBe('Job 1');

    // Redo while offline
    expect(store.canRedo()).toBe(true);
    store.redo();

    // Verify redo worked
    expect(store.getSnapshot().jobs[0]?.name).toBe('Changed Name');
  });

  test('channel observers are cleaned up on disconnect', () => {
    // Verify channel.on was called during connect
    expect(mockChannel.on).toHaveBeenCalledWith(
      'trigger_auth_methods_updated',
      expect.any(Function)
    );

    // Disconnect
    store.disconnect();

    // Verify channel.off was called to clean up channel observer
    expect(mockChannel.off).toHaveBeenCalledWith(
      'trigger_auth_methods_updated',
      expect.any(Function)
    );
  });

  test('Y.Doc observers NOT cleaned up on disconnect', () => {
    // Add a job to establish observer
    store.addJob({
      id: 'job-1',
      name: 'Job 1',
      adaptor: '@openfn/language-common@latest',
    });

    // Disconnect
    store.disconnect();

    // Track state changes via subscription
    let updateCount = 0;
    const unsubscribe = store.subscribe(() => {
      updateCount++;
    });

    // Make change using store method (which uses Y.Doc transactions)
    // If observers were cleaned up, this wouldn't trigger the subscription
    store.updateJobName('job-1', 'Changed While Offline');

    // Verify subscription was called (proving observers are still active)
    expect(updateCount).toBeGreaterThan(0);

    // Verify state updated via internal observers
    expect(store.getSnapshot().jobs[0]?.name).toBe('Changed While Offline');

    // Cleanup
    unsubscribe();
  });
});
