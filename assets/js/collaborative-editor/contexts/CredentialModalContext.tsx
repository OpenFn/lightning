import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useState,
} from 'react';

import { useLiveViewActions } from './LiveViewActionsContext';

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

  // Callback registries - keyed by source
  const [closeCallbacks, setCloseCallbacks] = useState<
    Map<ModalSource, Set<() => void>>
  >(() => new Map());
  const [savedCallbacks, setSavedCallbacks] = useState<
    Map<ModalSource, Set<(payload: CredentialSavedPayload) => void>>
  >(() => new Map());

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
      setCloseCallbacks(prev => {
        const next = new Map(prev);
        const sourceCallbacks = next.get(source) ?? new Set();
        sourceCallbacks.add(callback);
        next.set(source, sourceCallbacks);
        return next;
      });
      return () => {
        setCloseCallbacks(prev => {
          const next = new Map(prev);
          const sourceCallbacks = next.get(source);
          if (sourceCallbacks) {
            sourceCallbacks.delete(callback);
            if (sourceCallbacks.size === 0) {
              next.delete(source);
            }
          }
          return next;
        });
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
      setSavedCallbacks(prev => {
        const next = new Map(prev);
        const sourceCallbacks = next.get(source) ?? new Set();
        sourceCallbacks.add(callback);
        next.set(source, sourceCallbacks);
        return next;
      });
      return () => {
        setSavedCallbacks(prev => {
          const next = new Map(prev);
          const sourceCallbacks = next.get(source);
          if (sourceCallbacks) {
            sourceCallbacks.delete(callback);
            if (sourceCallbacks.size === 0) {
              next.delete(source);
            }
          }
          return next;
        });
      };
    },
    []
  );

  // Listen for close_credential_modal DOM event from LiveView
  useEffect(() => {
    const handleModalClose = () => {
      if (!modalState.isOpen) return;

      const currentSource = modalState.source;

      setModalState({
        isOpen: false,
        schema: null,
        credentialId: null,
        source: null,
      });

      // Notify only callbacks registered for the source that opened the modal
      setTimeout(() => {
        const sourceCallbacks = closeCallbacks.get(currentSource);
        sourceCallbacks?.forEach(callback => callback());
      }, 200);

      // Tell LiveView to close after animation completes
      setTimeout(() => {
        pushEvent('close_credential_modal', {});
      }, 500);
    };

    const element = document.getElementById('collaborative-editor-react');
    element?.addEventListener('close_credential_modal', handleModalClose);

    return () => {
      element?.removeEventListener('close_credential_modal', handleModalClose);
    };
  }, [modalState.isOpen, modalState.source, closeCallbacks, pushEvent]);

  // Listen for credential_saved event from LiveView
  useEffect(() => {
    const cleanup = handleEvent('credential_saved', (rawPayload: unknown) => {
      const payload = rawPayload as CredentialSavedPayload;
      const currentSource = modalState.source;

      setModalState({
        isOpen: false,
        schema: null,
        credentialId: null,
        source: null,
      });

      // Notify only callbacks registered for the source that opened the modal
      setTimeout(() => {
        const sourceSavedCallbacks = savedCallbacks.get(currentSource);
        sourceSavedCallbacks?.forEach(callback => callback(payload));

        const sourceCloseCallbacks = closeCallbacks.get(currentSource);
        sourceCloseCallbacks?.forEach(callback => callback());
      }, 200);
    });

    return cleanup;
  }, [handleEvent, modalState.source, savedCallbacks, closeCallbacks]);

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
