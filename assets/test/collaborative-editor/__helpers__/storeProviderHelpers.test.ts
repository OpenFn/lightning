/**
 * Enhanced StoreProvider Helper Tests
 *
 * Tests for the enhanced simulateStoreProviderWithConnection functionality:
 * - Custom Y.Doc support
 * - Session context emission
 * - Backward compatibility
 */

import { describe, expect, test } from 'vitest';

import { waitForAsync } from '../mocks/phoenixChannel';
import {
  simulateStoreProviderWithConnection,
  type StoreProviderConnectionOptions,
} from './storeProviderHelpers';
import { createWorkflowYDoc } from './workflowFactory';

describe('simulateStoreProviderWithConnection - Enhanced Options', () => {
  // =========================================================================
  // BACKWARD COMPATIBILITY TESTS
  // =========================================================================

  describe('backward compatibility', () => {
    test('works without options (existing tests unchanged)', async () => {
      const { stores, sessionStore, channelCleanup, cleanup } =
        await simulateStoreProviderWithConnection();

      expect(stores).toBeDefined();
      expect(sessionStore).toBeDefined();
      expect(stores.workflowStore).toBeDefined();
      expect(stores.sessionContextStore).toBeDefined();

      channelCleanup();
      cleanup();
    });

    test('works with legacy options format', async () => {
      const { stores, sessionStore, channelCleanup, cleanup } =
        await simulateStoreProviderWithConnection('test:room', undefined, {
          connect: true,
        });

      expect(stores).toBeDefined();
      expect(sessionStore).toBeDefined();

      channelCleanup();
      cleanup();
    });

    test('works with custom userData', async () => {
      const userData = {
        id: 'custom-user',
        name: 'Custom User',
        color: '#00ff00',
      };

      const { stores, sessionStore, channelCleanup, cleanup } =
        await simulateStoreProviderWithConnection('test:room', userData);

      expect(stores).toBeDefined();
      expect(sessionStore).toBeDefined();

      channelCleanup();
      cleanup();
    });
  });

  // =========================================================================
  // CUSTOM Y.DOC TESTS
  // =========================================================================

  describe('custom Y.Doc support', () => {
    test('uses provided Y.Doc with workflow data', async () => {
      const customYDoc = createWorkflowYDoc({
        jobs: {
          'job-a': {
            id: 'job-a',
            name: 'Job A',
            adaptor: '@openfn/language-common',
          },
          'job-b': {
            id: 'job-b',
            name: 'Job B',
            adaptor: '@openfn/language-common',
          },
        },
        edges: [
          {
            id: 'edge-1',
            source: 'job-a',
            target: 'job-b',
            condition_type: 'on_job_success',
          },
        ],
      });

      const { stores, ydoc, channelCleanup, cleanup } =
        await simulateStoreProviderWithConnection('test:room', undefined, {
          workflowYDoc: customYDoc,
        });

      // Verify Y.Doc is returned
      expect(ydoc).toBeDefined();
      expect(ydoc).toBe(customYDoc);

      // Verify workflow store is connected to the Y.Doc
      const state = stores.workflowStore.getSnapshot();
      expect(state.jobs).toHaveLength(2);
      expect(state.edges).toHaveLength(1);
      expect(state.jobs[0].name).toBe('Job A');
      expect(state.jobs[1].name).toBe('Job B');

      channelCleanup();
      cleanup();
    });

    test('creates empty Y.Doc when not provided', async () => {
      const { stores, ydoc, channelCleanup, cleanup } =
        await simulateStoreProviderWithConnection();

      // Verify Y.Doc is returned
      expect(ydoc).toBeDefined();

      // Verify workflow store is connected to an empty Y.Doc
      const state = stores.workflowStore.getSnapshot();
      expect(state.jobs).toHaveLength(0);
      expect(state.edges).toHaveLength(0);
      expect(state.triggers).toHaveLength(0);

      channelCleanup();
      cleanup();
    });

    test('workflow store can update provided Y.Doc', async () => {
      const customYDoc = createWorkflowYDoc({
        jobs: {
          'job-a': {
            id: 'job-a',
            name: 'Job A',
            adaptor: '@openfn/language-common',
          },
        },
      });

      const { stores, ydoc, channelCleanup, cleanup } =
        await simulateStoreProviderWithConnection('test:room', undefined, {
          workflowYDoc: customYDoc,
        });

      // Get initial state
      let state = stores.workflowStore.getSnapshot();
      expect(state.jobs).toHaveLength(1);

      // Add a job using workflow store
      const jobsArray = ydoc!.getArray('jobs');
      const newJobMap = new Map();
      newJobMap.set('id', 'job-b');
      newJobMap.set('name', 'Job B');
      newJobMap.set('adaptor', '@openfn/language-common');

      // Wait for Y.Doc update to propagate
      await waitForAsync(50);

      // Verify the update is reflected in store
      state = stores.workflowStore.getSnapshot();

      channelCleanup();
      cleanup();
    });
  });

  // =========================================================================
  // SESSION CONTEXT EMISSION TESTS
  // =========================================================================

  describe('session context emission', () => {
    test('emits session context when configured', async () => {
      const { stores, emitSessionContext, channelCleanup, cleanup } =
        await simulateStoreProviderWithConnection('test:room', undefined, {
          sessionContext: {
            permissions: { can_edit_workflow: true },
            user: { first_name: 'Test', last_name: 'User' },
          },
          emitSessionContext: true,
        });

      // Verify emit function is provided
      expect(emitSessionContext).toBeDefined();
      expect(typeof emitSessionContext).toBe('function');

      // Wait for session context to be processed
      await waitForAsync(100);

      // Verify session context store received the data
      const state = stores.sessionContextStore.getSnapshot();
      expect(state.user?.first_name).toBe('Test');
      expect(state.user?.last_name).toBe('User');
      expect(state.permissions?.can_edit_workflow).toBe(true);

      channelCleanup();
      cleanup();
    });

    test('does not provide emit function when not configured', async () => {
      const { emitSessionContext, channelCleanup, cleanup } =
        await simulateStoreProviderWithConnection();

      // Verify emit function is not provided
      expect(emitSessionContext).toBeUndefined();

      channelCleanup();
      cleanup();
    });

    test('does not provide emit function when emitSessionContext is false', async () => {
      const { emitSessionContext, channelCleanup, cleanup } =
        await simulateStoreProviderWithConnection('test:room', undefined, {
          sessionContext: {
            permissions: { can_edit_workflow: true },
          },
          emitSessionContext: false,
        });

      // Verify emit function is not provided
      expect(emitSessionContext).toBeUndefined();

      channelCleanup();
      cleanup();
    });

    test('re-emits session context with overrides', async () => {
      const { stores, emitSessionContext, channelCleanup, cleanup } =
        await simulateStoreProviderWithConnection('test:room', undefined, {
          sessionContext: {
            permissions: { can_edit_workflow: true },
            user: { first_name: 'Test', last_name: 'User' },
          },
          emitSessionContext: true,
        });

      // Wait for initial emission
      await waitForAsync(50);

      // Verify initial state
      let state = stores.sessionContextStore.getSnapshot();
      expect(state.permissions?.can_edit_workflow).toBe(true);

      // Re-emit with overrides
      emitSessionContext?.({
        permissions: { can_edit_workflow: false },
      });

      // Wait for update
      await waitForAsync(50);

      // Verify updated state
      state = stores.sessionContextStore.getSnapshot();
      expect(state.permissions?.can_edit_workflow).toBe(false);
      // User should be preserved from original context
      expect(state.user?.first_name).toBe('Test');

      channelCleanup();
      cleanup();
    });

    test('emits with GitHub repo connection', async () => {
      const { stores, emitSessionContext, channelCleanup, cleanup } =
        await simulateStoreProviderWithConnection('test:room', undefined, {
          sessionContext: {
            project_repo_connection: {
              repo: 'openfn/demo',
              branch: 'main',
            },
          },
          emitSessionContext: true,
        });

      // Wait for emission
      await waitForAsync(100);

      // Verify session context store received the data
      const state = stores.sessionContextStore.getSnapshot();

      // Note: Store transforms snake_case to camelCase
      expect(state.projectRepoConnection).toBeDefined();
      expect(state.projectRepoConnection?.repo).toBe('openfn/demo');
      expect(state.projectRepoConnection?.branch).toBe('main');

      channelCleanup();
      cleanup();
    });
  });

  // =========================================================================
  // COMBINED FEATURES TESTS
  // =========================================================================

  describe('combined features', () => {
    test('works with both custom Y.Doc and session context', async () => {
      const customYDoc = createWorkflowYDoc({
        jobs: {
          'job-a': {
            id: 'job-a',
            name: 'Job A',
            adaptor: '@openfn/language-common',
          },
        },
      });

      const { stores, ydoc, emitSessionContext, channelCleanup, cleanup } =
        await simulateStoreProviderWithConnection('test:room', undefined, {
          workflowYDoc: customYDoc,
          sessionContext: {
            permissions: { can_edit_workflow: true },
            user: { first_name: 'Test', last_name: 'User' },
          },
          emitSessionContext: true,
        });

      // Wait for session context
      await waitForAsync(50);

      // Verify Y.Doc
      expect(ydoc).toBe(customYDoc);
      const workflowState = stores.workflowStore.getSnapshot();
      expect(workflowState.jobs).toHaveLength(1);
      expect(workflowState.jobs[0].name).toBe('Job A');

      // Verify session context
      const sessionState = stores.sessionContextStore.getSnapshot();
      expect(sessionState.user?.first_name).toBe('Test');
      expect(sessionState.permissions?.can_edit_workflow).toBe(true);

      // Verify emit function is available
      expect(emitSessionContext).toBeDefined();

      channelCleanup();
      cleanup();
    });

    test('works with all options combined', async () => {
      const customYDoc = createWorkflowYDoc({
        jobs: {
          'job-a': {
            id: 'job-a',
            name: 'Job A',
            adaptor: '@openfn/language-common',
          },
        },
      });

      const userData = {
        id: 'custom-user',
        name: 'Custom User',
        color: '#00ff00',
      };

      const options: StoreProviderConnectionOptions = {
        connect: true,
        workflowYDoc: customYDoc,
        sessionContext: {
          permissions: { can_edit_workflow: true },
          user: { first_name: 'Test', last_name: 'User' },
          project_repo_connection: {
            repo: 'openfn/demo',
            branch: 'main',
          },
        },
        emitSessionContext: true,
      };

      const { stores, ydoc, emitSessionContext, channelCleanup, cleanup } =
        await simulateStoreProviderWithConnection(
          'test:custom-room',
          userData,
          options
        );

      // Wait for session context
      await waitForAsync(100);

      // Verify all features work together
      expect(ydoc).toBe(customYDoc);
      expect(stores.workflowStore.getSnapshot().jobs).toHaveLength(1);
      expect(stores.sessionContextStore.getSnapshot().user?.first_name).toBe(
        'Test'
      );
      const sessionState = stores.sessionContextStore.getSnapshot();
      // Note: Store transforms snake_case to camelCase
      expect(sessionState.projectRepoConnection).toBeDefined();
      expect(sessionState.projectRepoConnection?.repo).toBe('openfn/demo');
      expect(emitSessionContext).toBeDefined();

      channelCleanup();
      cleanup();
    });
  });

  // =========================================================================
  // CLEANUP TESTS
  // =========================================================================

  describe('cleanup', () => {
    test('disconnects workflow store on cleanup', async () => {
      const customYDoc = createWorkflowYDoc({
        jobs: {
          'job-a': {
            id: 'job-a',
            name: 'Job A',
            adaptor: '@openfn/language-common',
          },
        },
      });

      const { stores, channelCleanup, cleanup } =
        await simulateStoreProviderWithConnection('test:room', undefined, {
          workflowYDoc: customYDoc,
        });

      // Verify connected
      expect(stores.workflowStore.isConnected).toBe(true);

      // Call cleanup
      channelCleanup();

      // Verify disconnected
      expect(stores.workflowStore.isConnected).toBe(false);

      cleanup();
    });
  });
});
