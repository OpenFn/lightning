/**
 * EditorPreferences Store Tests
 *
 * Tests the EditorPreferences store behavior including:
 * - State initialization from storage
 * - Preference updates with storage persistence
 * - Referential stability
 * - Type safety
 * - Error handling
 *
 * Test Philosophy:
 * - Focus on user-facing behavior (state changes, persistence)
 * - Test store interface, not implementation details
 * - Verify referential stability guarantees
 */

import { afterEach, beforeEach, describe, expect, test, vi } from 'vitest';
import { createEditorPreferencesStore } from '../../../js/collaborative-editor/stores/createEditorPreferencesStore';
import type { EditorPreferencesStore } from '../../../js/collaborative-editor/types/editorPreferences';
import * as storage from 'lib0/storage';

describe('createEditorPreferencesStore', () => {
  let store: EditorPreferencesStore;

  beforeEach(() => {
    // Clear storage before each test
    storage.varStorage.clear?.() ||
      Object.keys(storage.varStorage).forEach(key =>
        storage.varStorage.removeItem(key)
      );
  });

  afterEach(() => {
    // Clean up storage after each test
    storage.varStorage.clear?.() ||
      Object.keys(storage.varStorage).forEach(key =>
        storage.varStorage.removeItem(key)
      );
  });

  // ========================================================================
  // INITIALIZATION
  // ========================================================================

  describe('initialization', () => {
    test('uses default values when no stored preferences exist', () => {
      store = createEditorPreferencesStore();
      const state = store.getSnapshot();

      expect(state.historyPanelCollapsed).toBe(true);
    });

    test('loads existing preferences from storage', () => {
      // Pre-populate storage
      storage.varStorage.setItem(
        'lightning.editor.historyPanelCollapsed',
        'false'
      );

      store = createEditorPreferencesStore();
      const state = store.getSnapshot();

      expect(state.historyPanelCollapsed).toBe(false);
    });

    test('handles corrupted storage gracefully', () => {
      // Set invalid value
      storage.varStorage.setItem(
        'lightning.editor.historyPanelCollapsed',
        'invalid'
      );

      store = createEditorPreferencesStore();
      const state = store.getSnapshot();

      // Should fall back to default (invalid values treated as falsy)
      expect(state.historyPanelCollapsed).toBe(false);
    });
  });

  // ========================================================================
  // STATE UPDATES
  // ========================================================================

  describe('setHistoryPanelCollapsed', () => {
    beforeEach(() => {
      store = createEditorPreferencesStore();
    });

    test('updates state and persists to storage', () => {
      store.setHistoryPanelCollapsed(false);

      const state = store.getSnapshot();
      expect(state.historyPanelCollapsed).toBe(false);

      // Verify storage was updated
      const stored = storage.varStorage.getItem(
        'lightning.editor.historyPanelCollapsed'
      );
      expect(stored).toBe('false');
    });

    test('notifies subscribers when state changes', () => {
      const listener = vi.fn();
      store.subscribe(listener);

      store.setHistoryPanelCollapsed(false);

      expect(listener).toHaveBeenCalledTimes(1);
    });

    test('notifies on every call even if value is same', () => {
      store.setHistoryPanelCollapsed(true); // Already default

      const listener = vi.fn();
      store.subscribe(listener);

      store.setHistoryPanelCollapsed(true); // Set to same value

      // Even though we set the same value, Immer creates new reference
      // This is expected behavior - notifies on every call
      expect(listener).toHaveBeenCalledTimes(1);

      // Storage should still be updated
      const stored = storage.varStorage.getItem(
        'lightning.editor.historyPanelCollapsed'
      );
      expect(stored).toBe('true');
    });
  });

  describe('resetToDefaults', () => {
    beforeEach(() => {
      store = createEditorPreferencesStore();
    });

    test('resets all preferences to defaults', () => {
      // Set non-default value
      store.setHistoryPanelCollapsed(false);
      expect(store.getSnapshot().historyPanelCollapsed).toBe(false);

      // Reset
      store.resetToDefaults();
      const state = store.getSnapshot();

      expect(state.historyPanelCollapsed).toBe(true);

      // Verify storage was updated
      const stored = storage.varStorage.getItem(
        'lightning.editor.historyPanelCollapsed'
      );
      expect(stored).toBe('true');
    });

    test('notifies subscribers', () => {
      const listener = vi.fn();
      store.subscribe(listener);

      store.resetToDefaults();

      expect(listener).toHaveBeenCalledTimes(1);
    });
  });

  // ========================================================================
  // REFERENTIAL STABILITY
  // ========================================================================

  describe('referential stability', () => {
    beforeEach(() => {
      store = createEditorPreferencesStore();
    });

    test('returns same state reference when no changes occur', () => {
      const state1 = store.getSnapshot();
      const state2 = store.getSnapshot();

      expect(state1).toBe(state2); // Same reference
    });

    test('returns new state reference after change', () => {
      const state1 = store.getSnapshot();

      store.setHistoryPanelCollapsed(false);

      const state2 = store.getSnapshot();
      expect(state1).not.toBe(state2); // Different references
    });

    test('withSelector returns stable result when state unchanged', () => {
      const selector = store.withSelector(s => s.historyPanelCollapsed);

      const result1 = selector();
      const result2 = selector();

      expect(result1).toBe(result2);
    });

    test('withSelector returns new result when state changes', () => {
      const selector = store.withSelector(s => s.historyPanelCollapsed);

      const result1 = selector();
      store.setHistoryPanelCollapsed(false);
      const result2 = selector();

      expect(result1).not.toBe(result2);
      expect(result1).toBe(true);
      expect(result2).toBe(false);
    });
  });

  // ========================================================================
  // SUBSCRIPTION MANAGEMENT
  // ========================================================================

  describe('subscription management', () => {
    beforeEach(() => {
      store = createEditorPreferencesStore();
    });

    test('allows multiple subscribers', () => {
      const listener1 = vi.fn();
      const listener2 = vi.fn();

      store.subscribe(listener1);
      store.subscribe(listener2);

      store.setHistoryPanelCollapsed(false);

      expect(listener1).toHaveBeenCalledTimes(1);
      expect(listener2).toHaveBeenCalledTimes(1);
    });

    test('unsubscribe removes listener', () => {
      const listener = vi.fn();
      const unsubscribe = store.subscribe(listener);

      store.setHistoryPanelCollapsed(false);
      expect(listener).toHaveBeenCalledTimes(1);

      unsubscribe();
      listener.mockClear();

      store.setHistoryPanelCollapsed(true);
      expect(listener).not.toHaveBeenCalled();
    });

    test('handles multiple unsubscribes safely', () => {
      const listener = vi.fn();
      const unsubscribe = store.subscribe(listener);

      unsubscribe();
      unsubscribe(); // Call again - should not throw

      store.setHistoryPanelCollapsed(false);
      expect(listener).not.toHaveBeenCalled();
    });
  });

  // ========================================================================
  // ERROR HANDLING
  // ========================================================================

  describe('error handling', () => {
    test('handles storage errors during save', () => {
      store = createEditorPreferencesStore();

      // Mock storage.setItem to throw
      const originalSetItem = storage.varStorage.setItem;
      storage.varStorage.setItem = vi.fn(() => {
        throw new Error('Storage quota exceeded');
      });

      // Should not throw
      expect(() => {
        store.setHistoryPanelCollapsed(false);
      }).not.toThrow();

      // State should still update (storage is best-effort)
      expect(store.getSnapshot().historyPanelCollapsed).toBe(false);

      // Restore original setItem
      storage.varStorage.setItem = originalSetItem;
    });

    test('handles storage errors during load', () => {
      // Mock storage.getItem to throw
      const originalGetItem = storage.varStorage.getItem;
      storage.varStorage.getItem = vi.fn(() => {
        throw new Error('Storage access denied');
      });

      // Should not throw, should use defaults
      expect(() => {
        store = createEditorPreferencesStore();
      }).not.toThrow();

      expect(store.getSnapshot().historyPanelCollapsed).toBe(true);

      // Restore original getItem
      storage.varStorage.getItem = originalGetItem;
    });
  });
});
