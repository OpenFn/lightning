/**
 * EditorPreferences Store
 *
 * Manages local user preferences for the collaborative editor using
 * useSyncExternalStore + Immer + Redux DevTools pattern.
 *
 * Preferences are persisted to localStorage via lib0/storage.
 */

import { produce } from 'immer';
import * as storage from 'lib0/storage';

import _logger from '#/utils/logger';

import type {
  EditorPreferencesState,
  EditorPreferencesStore,
} from '../types/editorPreferences';

import { createWithSelector } from './common';
import { wrapStoreWithDevTools } from './devtools';

const logger = _logger.ns('EditorPreferencesStore').seal();

/**
 * Storage key prefix for all editor preferences
 */
const STORAGE_PREFIX = 'lightning.editor';

/**
 * Default values for all preferences
 */
const DEFAULT_STATE: EditorPreferencesState = {
  historyPanelCollapsed: true,
};

/**
 * Load a single preference from storage
 */
function loadPreference<K extends keyof EditorPreferencesState>(
  key: K,
  defaultValue: EditorPreferencesState[K]
): EditorPreferencesState[K] {
  try {
    const storageKey = `${STORAGE_PREFIX}.${key}`;
    const stored = storage.varStorage.getItem(storageKey);

    if (stored === null) {
      return defaultValue;
    }

    // Handle boolean values (stored as strings)
    if (typeof defaultValue === 'boolean') {
      return (stored === 'true') as EditorPreferencesState[K];
    }

    // Add more type handlers here as needed
    return stored as EditorPreferencesState[K];
  } catch (error) {
    logger.error(`Failed to load preference: ${key}`, error);
    return defaultValue;
  }
}

/**
 * Save a single preference to storage
 */
function savePreference<K extends keyof EditorPreferencesState>(
  key: K,
  value: EditorPreferencesState[K]
): void {
  try {
    const storageKey = `${STORAGE_PREFIX}.${key}`;
    storage.varStorage.setItem(storageKey, String(value));
  } catch (error) {
    logger.error(`Failed to save preference: ${key}`, error);
  }
}

/**
 * Create EditorPreferences store instance
 */
export const createEditorPreferencesStore = (): EditorPreferencesStore => {
  // Initialize state from storage with defaults
  let state: EditorPreferencesState = produce(
    {
      historyPanelCollapsed: loadPreference(
        'historyPanelCollapsed',
        DEFAULT_STATE.historyPanelCollapsed
      ),
    } as EditorPreferencesState,
    draft => draft
  );

  // Create listener set for subscribers
  const listeners = new Set<() => void>();

  // Initialize Redux DevTools integration
  const devtools = wrapStoreWithDevTools({
    name: 'EditorPreferencesStore',
    excludeKeys: [], // All state is serializable
    maxAge: 50,
  });

  // Connect DevTools immediately
  devtools.connect();

  // Create notify function
  const notify = (actionName: string = 'stateChange') => {
    devtools.notifyWithAction(actionName, () => state);
    listeners.forEach(listener => {
      listener();
    });
  };

  // Implement useSyncExternalStore interface
  const subscribe = (listener: () => void) => {
    listeners.add(listener);
    return () => listeners.delete(listener);
  };

  const getSnapshot = (): EditorPreferencesState => state;

  // Create withSelector utility for memoized selectors
  const withSelector = createWithSelector(getSnapshot);

  // Commands
  const setHistoryPanelCollapsed = (collapsed: boolean) => {
    state = produce(state, draft => {
      draft.historyPanelCollapsed = collapsed;
    });
    savePreference('historyPanelCollapsed', collapsed);
    notify('setHistoryPanelCollapsed');
  };

  const resetToDefaults = () => {
    state = produce(state, draft => {
      Object.assign(draft, DEFAULT_STATE);
    });
    // Save all defaults
    Object.entries(DEFAULT_STATE).forEach(([key, value]) => {
      savePreference(key as keyof EditorPreferencesState, value);
    });
    notify('resetToDefaults');
  };

  return {
    subscribe,
    getSnapshot,
    withSelector,
    setHistoryPanelCollapsed,
    resetToDefaults,
  };
};

export type EditorPreferencesStoreInstance = ReturnType<
  typeof createEditorPreferencesStore
>;
