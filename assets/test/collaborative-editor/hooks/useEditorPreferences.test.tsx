/**
 * EditorPreferences Hooks Tests
 *
 * Tests the EditorPreferences hooks behavior including:
 * - State selection and updates
 * - Command execution
 * - Context error handling
 * - Referential stability
 * - Re-render optimization
 */

import { renderHook, act } from '@testing-library/react';
import { describe, expect, test, beforeEach, afterEach } from 'vitest';
import type React from 'react';
import {
  useHistoryPanelCollapsed,
  useEditorPreferencesCommands,
} from '../../../js/collaborative-editor/hooks/useEditorPreferences';
import { StoreContext } from '../../../js/collaborative-editor/contexts/StoreProvider';
import type { StoreContextValue } from '../../../js/collaborative-editor/contexts/StoreProvider';
import { createEditorPreferencesStore } from '../../../js/collaborative-editor/stores/createEditorPreferencesStore';
import type { EditorPreferencesStore } from '../../../js/collaborative-editor/types/editorPreferences';
import * as storage from 'lib0/storage';

function createWrapper(
  editorPreferencesStore: EditorPreferencesStore
): React.ComponentType<{ children: React.ReactNode }> {
  const mockStoreValue: StoreContextValue = {
    editorPreferencesStore,
    adaptorStore: {} as any,
    credentialStore: {} as any,
    awarenessStore: {} as any,
    workflowStore: {} as any,
    sessionContextStore: {} as any,
    historyStore: {} as any,
    uiStore: {} as any,
  };

  return ({ children }: { children: React.ReactNode }) => (
    <StoreContext.Provider value={mockStoreValue}>
      {children}
    </StoreContext.Provider>
  );
}

describe('useEditorPreferences hooks', () => {
  let store: EditorPreferencesStore;

  beforeEach(() => {
    // Clear storage before each test
    storage.varStorage.clear?.() ||
      Object.keys(storage.varStorage).forEach(key =>
        storage.varStorage.removeItem(key)
      );
  });

  afterEach(() => {
    storage.varStorage.clear?.() ||
      Object.keys(storage.varStorage).forEach(key =>
        storage.varStorage.removeItem(key)
      );
  });

  // ==========================================================================
  // useHistoryPanelCollapsed
  // ==========================================================================

  describe('useHistoryPanelCollapsed', () => {
    test('returns default value on first render', () => {
      store = createEditorPreferencesStore();
      const { result } = renderHook(() => useHistoryPanelCollapsed(), {
        wrapper: createWrapper(store),
      });

      expect(result.current).toBe(true);
    });

    test('returns stored value if exists', () => {
      // Pre-populate storage
      storage.varStorage.setItem(
        'lightning.editor.historyPanelCollapsed',
        'false'
      );

      store = createEditorPreferencesStore();
      const { result } = renderHook(() => useHistoryPanelCollapsed(), {
        wrapper: createWrapper(store),
      });

      expect(result.current).toBe(false);
    });

    test('updates when preference changes', () => {
      store = createEditorPreferencesStore();
      const wrapper = createWrapper(store);
      const { result: collapsedResult } = renderHook(
        () => useHistoryPanelCollapsed(),
        { wrapper }
      );
      const { result: commandsResult } = renderHook(
        () => useEditorPreferencesCommands(),
        { wrapper }
      );

      expect(collapsedResult.current).toBe(true);

      act(() => {
        commandsResult.current.setHistoryPanelCollapsed(false);
      });

      expect(collapsedResult.current).toBe(false);
    });

    test('throws error when used outside StoreProvider', () => {
      // Suppress console.error for this test
      const consoleError = console.error;
      console.error = () => {};

      expect(() => {
        renderHook(() => useHistoryPanelCollapsed());
      }).toThrow(
        'useEditorPreferencesStore must be used within a StoreProvider'
      );

      console.error = consoleError;
    });

    test('maintains referential stability when value unchanged', () => {
      store = createEditorPreferencesStore();
      const { result, rerender } = renderHook(
        () => useHistoryPanelCollapsed(),
        { wrapper: createWrapper(store) }
      );

      const firstValue = result.current;
      rerender();
      const secondValue = result.current;

      expect(firstValue).toBe(secondValue);
    });
  });

  // ==========================================================================
  // useEditorPreferencesCommands
  // ==========================================================================

  describe('useEditorPreferencesCommands', () => {
    test('returns stable command functions', () => {
      store = createEditorPreferencesStore();
      const { result, rerender } = renderHook(
        () => useEditorPreferencesCommands(),
        { wrapper: createWrapper(store) }
      );

      const firstCommands = result.current;
      rerender();
      const secondCommands = result.current;

      expect(firstCommands.setHistoryPanelCollapsed).toBe(
        secondCommands.setHistoryPanelCollapsed
      );
      expect(firstCommands.resetToDefaults).toBe(
        secondCommands.resetToDefaults
      );
    });

    test('setHistoryPanelCollapsed updates state and storage', () => {
      store = createEditorPreferencesStore();
      const { result } = renderHook(() => useEditorPreferencesCommands(), {
        wrapper: createWrapper(store),
      });

      act(() => {
        result.current.setHistoryPanelCollapsed(false);
      });

      const stored = storage.varStorage.getItem(
        'lightning.editor.historyPanelCollapsed'
      );
      expect(stored).toBe('false');
    });

    test('resetToDefaults resets all preferences', () => {
      store = createEditorPreferencesStore();
      const wrapper = createWrapper(store);
      const { result: commandsResult } = renderHook(
        () => useEditorPreferencesCommands(),
        { wrapper }
      );
      const { result: collapsedResult } = renderHook(
        () => useHistoryPanelCollapsed(),
        { wrapper }
      );

      // Set non-default value
      act(() => {
        commandsResult.current.setHistoryPanelCollapsed(false);
      });
      expect(collapsedResult.current).toBe(false);

      // Reset
      act(() => {
        commandsResult.current.resetToDefaults();
      });

      expect(collapsedResult.current).toBe(true);
      expect(
        storage.varStorage.getItem('lightning.editor.historyPanelCollapsed')
      ).toBe('true');
    });
  });

  // ==========================================================================
  // INTEGRATION
  // ==========================================================================

  describe('integration', () => {
    test('multiple components can read same preference', () => {
      store = createEditorPreferencesStore();
      const wrapper = createWrapper(store);
      const { result: result1 } = renderHook(() => useHistoryPanelCollapsed(), {
        wrapper,
      });
      const { result: result2 } = renderHook(() => useHistoryPanelCollapsed(), {
        wrapper,
      });

      expect(result1.current).toBe(result2.current);
      expect(result1.current).toBe(true);
    });

    test('preference change propagates to all consumers', () => {
      store = createEditorPreferencesStore();
      const wrapper = createWrapper(store);
      const { result: result1 } = renderHook(() => useHistoryPanelCollapsed(), {
        wrapper,
      });
      const { result: result2 } = renderHook(() => useHistoryPanelCollapsed(), {
        wrapper,
      });
      const { result: commandsResult } = renderHook(
        () => useEditorPreferencesCommands(),
        { wrapper }
      );

      act(() => {
        commandsResult.current.setHistoryPanelCollapsed(false);
      });

      expect(result1.current).toBe(false);
      expect(result2.current).toBe(false);
    });
  });
});
