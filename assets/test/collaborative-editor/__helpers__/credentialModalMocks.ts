import { vi } from 'vitest';

type ModalSource = 'ide' | 'inspector' | null;

/**
 * Creates mock values for the CredentialModalContext
 */
export function createCredentialModalMock() {
  return {
    openCredentialModal: vi.fn(),
    isCredentialModalOpen: false,
    onModalClose: vi.fn((_source: ModalSource, _callback: () => void) =>
      vi.fn()
    ),
    onCredentialSaved: vi.fn(
      (_source: ModalSource, _callback: (payload: unknown) => void) => vi.fn()
    ),
  };
}

/**
 * Default mock implementation for CredentialModalContext
 * Use this in vi.mock() calls
 */
export const defaultCredentialModalMock = {
  CredentialModalProvider: ({ children }: { children: React.ReactNode }) =>
    children,
  useCredentialModal: () => createCredentialModalMock(),
};
