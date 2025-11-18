/**
 * WorkflowDiagram Undo/Redo Integration Tests
 *
 * Tests for undo/redo functionality integration in WorkflowDiagram:
 * - State tracking (canUndo/canRedo)
 * - UndoManager event subscriptions
 * - Store command integration
 *
 * Note: Full component rendering tests are covered by E2E tests.
 * These unit tests focus on the undo/redo state management logic.
 */

import { renderHook, waitFor, act } from '@testing-library/react';
import { describe, expect, test, beforeEach, vi } from 'vitest';
import * as Y from 'yjs';
import type { Channel } from 'phoenix';
import type { PhoenixChannelProvider } from 'y-phoenix-channel';

import { createWorkflowStore } from '../../../../js/collaborative-editor/stores/createWorkflowStore';
import type { WorkflowStoreInstance } from '../../../../js/collaborative-editor/stores/createWorkflowStore';
import type { Session } from '../../../../js/collaborative-editor/types/session';
import {
  createMockChannelPushOk,
  createMockPhoenixChannel,
} from '../../__helpers__/channelMocks';
import { useState, useEffect } from 'react';

describe('WorkflowDiagram - Undo/Redo State Management', () => {
  let workflowStore: WorkflowStoreInstance;
  let ydoc: Session.WorkflowDoc;
  let mockProvider: PhoenixChannelProvider & { channel: Channel };

  beforeEach(() => {
    // Create store and Y.Doc
    workflowStore = createWorkflowStore();
    ydoc = new Y.Doc() as Session.WorkflowDoc;

    // Initialize Y.Doc structure
    const workflowMap = ydoc.getMap('workflow');
    workflowMap.set('id', 'workflow-123');
    workflowMap.set('name', 'Test Workflow');

    ydoc.getArray('jobs');
    ydoc.getArray('triggers');
    ydoc.getArray('edges');
    ydoc.getMap('positions');

    // Create mock provider
    const mockChannel = createMockPhoenixChannel();
    mockChannel.push = createMockChannelPushOk({});

    mockProvider = {
      channel: mockChannel,
      synced: true,
      awareness: null,
      doc: ydoc,
    } as unknown as PhoenixChannelProvider & { channel: Channel };

    // Connect store
    workflowStore.connect(ydoc, mockProvider);
  });

  test('canUndo state is initially false', () => {
    expect(workflowStore.canUndo()).toBe(false);
  });

  test('canRedo state is initially false', () => {
    expect(workflowStore.canRedo()).toBe(false);
  });

  test('canUndo becomes true after an operation', () => {
    workflowStore.addJob({ id: 'job1', name: 'Test Job', body: '' });
    expect(workflowStore.canUndo()).toBe(true);
  });

  test('canRedo becomes true after undo', () => {
    workflowStore.addJob({ id: 'job1', name: 'Test Job', body: '' });
    workflowStore.undo();
    expect(workflowStore.canRedo()).toBe(true);
  });

  test('UndoManager events trigger state updates', async () => {
    // Hook to listen to UndoManager events
    function useUndoRedoState(store: WorkflowStoreInstance) {
      const [canUndo, setCanUndo] = useState(false);
      const [canRedo, setCanRedo] = useState(false);

      useEffect(() => {
        const undoManager = store.getSnapshot().undoManager;
        if (!undoManager) return;

        const updateState = () => {
          setCanUndo(store.canUndo());
          setCanRedo(store.canRedo());
        };

        updateState();

        undoManager.on('stack-item-added', updateState);
        undoManager.on('stack-item-popped', updateState);
        undoManager.on('stack-cleared', updateState);

        return () => {
          undoManager.off('stack-item-added', updateState);
          undoManager.off('stack-item-popped', updateState);
          undoManager.off('stack-cleared', updateState);
        };
      }, [store]);

      return { canUndo, canRedo };
    }

    const { result } = renderHook(() => useUndoRedoState(workflowStore));

    // Initially false
    expect(result.current.canUndo).toBe(false);
    expect(result.current.canRedo).toBe(false);

    // Add job
    act(() => {
      workflowStore.addJob({ id: 'job1', name: 'Test Job', body: '' });
    });

    // Wait for state update
    await waitFor(() => {
      expect(result.current.canUndo).toBe(true);
      expect(result.current.canRedo).toBe(false);
    });

    // Undo
    act(() => {
      workflowStore.undo();
    });

    // Wait for state update
    await waitFor(() => {
      expect(result.current.canUndo).toBe(false);
      expect(result.current.canRedo).toBe(true);
    });
  });

  test('undo command integration', () => {
    // Add operation
    workflowStore.addJob({ id: 'job1', name: 'Test Job', body: '' });
    expect(workflowStore.getSnapshot().jobs.length).toBe(1);

    // Undo
    workflowStore.undo();
    expect(workflowStore.getSnapshot().jobs.length).toBe(0);
  });

  test('redo command integration', () => {
    // Add, undo, redo
    workflowStore.addJob({ id: 'job1', name: 'Test Job', body: '' });
    workflowStore.undo();
    workflowStore.redo();

    expect(workflowStore.getSnapshot().jobs.length).toBe(1);
    expect(workflowStore.getSnapshot().jobs[0].name).toBe('Test Job');
  });

  test('multiple operations update state correctly', async () => {
    function useUndoRedoState(store: WorkflowStoreInstance) {
      const [canUndo, setCanUndo] = useState(false);
      const [canRedo, setCanRedo] = useState(false);

      useEffect(() => {
        const undoManager = store.getSnapshot().undoManager;
        if (!undoManager) return;

        const updateState = () => {
          setCanUndo(store.canUndo());
          setCanRedo(store.canRedo());
        };

        updateState();

        undoManager.on('stack-item-added', updateState);
        undoManager.on('stack-item-popped', updateState);

        return () => {
          undoManager.off('stack-item-added', updateState);
          undoManager.off('stack-item-popped', updateState);
        };
      }, [store]);

      return { canUndo, canRedo };
    }

    const { result } = renderHook(() => useUndoRedoState(workflowStore));

    // Add job 1
    act(() => {
      workflowStore.addJob({ id: 'job1', name: 'Job 1', body: '' });
    });

    await waitFor(() => {
      expect(result.current.canUndo).toBe(true);
      expect(result.current.canRedo).toBe(false);
    });

    // Wait for captureTimeout to expire (500ms) to prevent grouping
    await new Promise(resolve => setTimeout(resolve, 600));

    // Add job 2
    act(() => {
      workflowStore.addJob({ id: 'job2', name: 'Job 2', body: '' });
    });

    await waitFor(() => {
      expect(result.current.canUndo).toBe(true);
    });

    // Undo once
    act(() => {
      workflowStore.undo();
    });

    await waitFor(() => {
      expect(result.current.canUndo).toBe(true); // Still have job1 to undo
      expect(result.current.canRedo).toBe(true); // Can redo job2
    });

    // Undo again
    act(() => {
      workflowStore.undo();
    });

    await waitFor(() => {
      expect(result.current.canUndo).toBe(false); // Nothing left to undo
      expect(result.current.canRedo).toBe(true); // Can redo both
    });
  });

  test('keyboard shortcut simulation', () => {
    // Simulate what happens when Ctrl+Z is pressed
    workflowStore.addJob({ id: 'job1', name: 'Test Job', body: '' });

    const undoSpy = vi.spyOn(workflowStore, 'undo');

    // Simulate keyboard handler calling undo
    workflowStore.undo();

    expect(undoSpy).toHaveBeenCalled();
    expect(workflowStore.getSnapshot().jobs.length).toBe(0);
  });

  test('keyboard shortcut simulation for redo', () => {
    // Simulate what happens when Ctrl+Y is pressed
    workflowStore.addJob({ id: 'job1', name: 'Test Job', body: '' });
    workflowStore.undo();

    const redoSpy = vi.spyOn(workflowStore, 'redo');

    // Simulate keyboard handler calling redo
    workflowStore.redo();

    expect(redoSpy).toHaveBeenCalled();
    expect(workflowStore.getSnapshot().jobs.length).toBe(1);
  });

  test('clearHistory integration', async () => {
    function useUndoRedoState(store: WorkflowStoreInstance) {
      const [canUndo, setCanUndo] = useState(false);
      const [canRedo, setCanRedo] = useState(false);

      useEffect(() => {
        const undoManager = store.getSnapshot().undoManager;
        if (!undoManager) return;

        const updateState = () => {
          setCanUndo(store.canUndo());
          setCanRedo(store.canRedo());
        };

        updateState();

        undoManager.on('stack-cleared', updateState);

        return () => {
          undoManager.off('stack-cleared', updateState);
        };
      }, [store]);

      return { canUndo, canRedo };
    }

    const { result } = renderHook(() => useUndoRedoState(workflowStore));

    // Add and undo to create history
    act(() => {
      workflowStore.addJob({ id: 'job1', name: 'Test Job', body: '' });
      workflowStore.undo();
    });

    // Clear history
    act(() => {
      workflowStore.clearHistory();
    });

    await waitFor(() => {
      expect(result.current.canUndo).toBe(false);
      expect(result.current.canRedo).toBe(false);
    });
  });
});
