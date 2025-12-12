import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useRef,
  useState,
} from 'react';

import { useKeyboardShortcut } from '../keyboard';

import { useLiveViewActions } from './LiveViewActionsContext';

/**
 * Timing constants for modal animations and LiveView coordination.
 *
 * MODAL_REOPEN_DELAY: Time to wait before reopening the configure modal after
 * credential modal closes. This allows the close animation to complete smoothly.
 * Phoenix.JS dispatches close events at ~250ms, so 200ms feels instant.
 *
 * LIVEVIEW_CLEANUP_DELAY: Time to wait before notifying LiveView to clean up
 * server-side modal state. This accounts for: Phoenix.JS animation (250ms) +
 * LiveView update time + buffer. Prevents race conditions if user quickly reopens.
 */
const MODAL_REOPEN_DELAY = 200;
const LIVEVIEW_CLEANUP_DELAY = 500;

type ModalSource = 'ide' | 'inspector' | null;

interface CredentialModalState {
  isOpen: boolean;
  schema: string | null;
  credentialId: string | null;
  source: ModalSource;
}

interface CredentialModalContextValue {
  /** Open the credential modal for creating or editing a credential */
  openCredentialModal: (
    schema: string,
    credentialId?: string,
    source?: ModalSource
  ) => void;
  /** Whether the credential modal is currently open */
  isCredentialModalOpen: boolean;
  /** Register a callback to be notified when the modal closes (only if source matches) */
  onModalClose: (source: ModalSource, callback: () => void) => () => void;
  /** Register a callback to be notified when a credential is saved (only if source matches) */
  onCredentialSaved: (
    source: ModalSource,
    callback: (payload: CredentialSavedPayload) => void
  ) => () => void;
}

export interface CredentialSavedPayload {
  credential: {
    id: string;
    project_credential_id?: string;
  };
  is_project_credential: boolean;
}

const CredentialModalContext =
  createContext<CredentialModalContextValue | null>(null);

interface CredentialModalProviderProps {
  children: React.ReactNode;
}

/**
 * CredentialModalProvider - Centralized controller for the credential modal.
 *
 * This provider owns the credential modal lifecycle and coordinates between
 * React components (JobForm, FullScreenIDE) and the LiveView credential modal.
 *
 * Usage:
 * - Call `openCredentialModal(schema, credentialId?)` to open the modal
 * - Register callbacks with `onModalClose` and `onCredentialSaved` to react to events
 * - The provider handles all LiveView communication and timing
 */
export function CredentialModalProvider({
  children,
}: CredentialModalProviderProps) {
  const { pushEvent, handleEvent } = useLiveViewActions();

  const [modalState, setModalState] = useState<CredentialModalState>({
    isOpen: false,
    schema: null,
    credentialId: null,
    source: null,
  });

  // Use ref to access current state in event handlers without stale closures
  const modalStateRef = useRef(modalState);
  modalStateRef.current = modalState;

  // Callback registries - keyed by source
  // Using refs instead of state to:
  // 1. Avoid unnecessary re-renders when callbacks register/unregister
  // 2. Always access current callbacks in setTimeout handlers (no stale closures)
  const closeCallbacksRef = useRef<Map<ModalSource, Set<() => void>>>(
    new Map()
  );
  const savedCallbacksRef = useRef<
    Map<ModalSource, Set<(payload: CredentialSavedPayload) => void>>
  >(new Map());

  // High-priority Escape handler to prevent closing parent IDE/inspector
  // when the LiveView credential modal is open.
  // Priority 100 (MODAL) ensures this runs before IDE handler (priority 50).
  // This handler does nothing - it just blocks the event from reaching lower-priority handlers.
  // LiveView handles the actual modal close via its own keyboard handling.
  useKeyboardShortcut(
    'Escape',
    () => {
      // Do nothing - just block the event from reaching IDE/inspector handlers
      // LiveView will handle its own modal closing
    },
    100,
    { enabled: modalState.isOpen }
  );

  // Open the credential modal
  const openCredentialModal = useCallback(
    (schema: string, credentialId?: string, source: ModalSource = null) => {
      setModalState({
        isOpen: true,
        schema,
        credentialId: credentialId ?? null,
        source,
      });

      pushEvent('open_credential_modal', {
        schema,
        credential_id: credentialId,
      });
    },
    [pushEvent]
  );

  // Register a callback for modal close (only called if source matches)
  const onModalClose = useCallback(
    (source: ModalSource, callback: () => void) => {
      const callbacks = closeCallbacksRef.current;
      const sourceCallbacks = callbacks.get(source) ?? new Set();
      sourceCallbacks.add(callback);
      callbacks.set(source, sourceCallbacks);

      // Return cleanup function
      return () => {
        const currentCallbacks = closeCallbacksRef.current.get(source);
        if (currentCallbacks) {
          currentCallbacks.delete(callback);
          if (currentCallbacks.size === 0) {
            closeCallbacksRef.current.delete(source);
          }
        }
      };
    },
    []
  );

  // Register a callback for credential saved (only called if source matches)
  const onCredentialSaved = useCallback(
    (
      source: ModalSource,
      callback: (payload: CredentialSavedPayload) => void
    ) => {
      const callbacks = savedCallbacksRef.current;
      const sourceCallbacks = callbacks.get(source) ?? new Set();
      sourceCallbacks.add(callback);
      callbacks.set(source, sourceCallbacks);

      // Return cleanup function
      return () => {
        const currentCallbacks = savedCallbacksRef.current.get(source);
        if (currentCallbacks) {
          currentCallbacks.delete(callback);
          if (currentCallbacks.size === 0) {
            savedCallbacksRef.current.delete(source);
          }
        }
      };
    },
    []
  );

  // Listen for close_credential_modal DOM event from LiveView
  useEffect(() => {
    const handleModalClose = () => {
      // Use ref to get current state - avoids stale closure issues
      if (!modalStateRef.current.isOpen) return;

      const currentSource = modalStateRef.current.source;

      setModalState({
        isOpen: false,
        schema: null,
        credentialId: null,
        source: null,
      });

      // Notify only callbacks registered for the source that opened the modal
      // Using ref ensures we call the current callbacks, not stale ones
      setTimeout(() => {
        const sourceCallbacks = closeCallbacksRef.current.get(currentSource);
        sourceCallbacks?.forEach(callback => callback());
      }, MODAL_REOPEN_DELAY);

      // Tell LiveView to close after animation completes
      setTimeout(() => {
        pushEvent('close_credential_modal', {});
      }, LIVEVIEW_CLEANUP_DELAY);
    };

    const element = document.getElementById('collaborative-editor-react');
    element?.addEventListener('close_credential_modal', handleModalClose);

    return () => {
      element?.removeEventListener('close_credential_modal', handleModalClose);
    };
  }, [pushEvent]);

  // Listen for credential_saved event from LiveView
  useEffect(() => {
    const cleanup = handleEvent('credential_saved', (rawPayload: unknown) => {
      const payload = rawPayload as CredentialSavedPayload;
      // Use ref to get current state - avoids stale closure issues
      const currentSource = modalStateRef.current.source;

      setModalState({
        isOpen: false,
        schema: null,
        credentialId: null,
        source: null,
      });

      // Notify only callbacks registered for the source that opened the modal
      // Using refs ensures we call the current callbacks, not stale ones
      setTimeout(() => {
        const sourceSavedCallbacks =
          savedCallbacksRef.current.get(currentSource);
        sourceSavedCallbacks?.forEach(callback => callback(payload));

        const sourceCloseCallbacks =
          closeCallbacksRef.current.get(currentSource);
        sourceCloseCallbacks?.forEach(callback => callback());
      }, MODAL_REOPEN_DELAY);
    });

    return cleanup;
  }, [handleEvent]);

  const value: CredentialModalContextValue = {
    openCredentialModal,
    isCredentialModalOpen: modalState.isOpen,
    onModalClose,
    onCredentialSaved,
  };

  return (
    <CredentialModalContext.Provider value={value}>
      {children}
    </CredentialModalContext.Provider>
  );
}

export function useCredentialModal(): CredentialModalContextValue {
  const context = useContext(CredentialModalContext);
  if (!context) {
    throw new Error(
      'useCredentialModal must be used within a CredentialModalProvider'
    );
  }
  return context;
}
