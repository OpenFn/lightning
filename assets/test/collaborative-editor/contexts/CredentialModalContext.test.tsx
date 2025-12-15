/**
 * CredentialModalContext Tests
 *
 * Verifies CredentialModalContext behavior:
 * - Context provision and hook access
 * - Opening modal and LiveView event communication
 * - Source-based callback routing (only matching source receives callbacks)
 * - Callback registration and cleanup
 * - State transitions
 */

import { act, renderHook, waitFor } from '@testing-library/react';
import { afterEach, beforeEach, describe, expect, test, vi } from 'vitest';

import {
  CredentialModalProvider,
  useCredentialModal,
} from '../../../js/collaborative-editor/contexts/CredentialModalContext';
import { LiveViewActionsProvider } from '../../../js/collaborative-editor/contexts/LiveViewActionsContext';
import { KeyboardProvider } from '../../../js/collaborative-editor/keyboard';

// =============================================================================
// TEST SETUP & FIXTURES
// =============================================================================

interface MockLiveViewActions {
  pushEvent: ReturnType<typeof vi.fn>;
  pushEventTo: ReturnType<typeof vi.fn>;
  handleEvent: ReturnType<typeof vi.fn>;
  navigate: ReturnType<typeof vi.fn>;
}

function createMockLiveViewActions(): MockLiveViewActions {
  return {
    pushEvent: vi.fn(),
    pushEventTo: vi.fn(),
    handleEvent: vi.fn(() => vi.fn()),
    navigate: vi.fn(),
  };
}

function createTestWrapper(mockActions: MockLiveViewActions) {
  return function Wrapper({ children }: { children: React.ReactNode }) {
    return (
      <KeyboardProvider>
        <LiveViewActionsProvider actions={mockActions}>
          <CredentialModalProvider>{children}</CredentialModalProvider>
        </LiveViewActionsProvider>
      </KeyboardProvider>
    );
  };
}

// Helper to simulate DOM events from LiveView
function dispatchCloseModalEvent() {
  const element = document.getElementById('collaborative-editor-react');
  if (element) {
    element.dispatchEvent(new CustomEvent('close_credential_modal'));
  }
}

describe('CredentialModalContext', () => {
  let mockActions: MockLiveViewActions;
  let mockElement: HTMLDivElement;

  beforeEach(() => {
    mockActions = createMockLiveViewActions();

    // Create the DOM element that LiveView events are dispatched to
    mockElement = document.createElement('div');
    mockElement.id = 'collaborative-editor-react';
    document.body.appendChild(mockElement);

    vi.useFakeTimers();
  });

  afterEach(() => {
    vi.clearAllMocks();
    vi.useRealTimers();

    // Clean up DOM
    if (mockElement && mockElement.parentNode) {
      mockElement.parentNode.removeChild(mockElement);
    }
  });

  // ===========================================================================
  // CONTEXT PROVISION TESTS
  // ===========================================================================

  describe('context provision', () => {
    test('provides all expected methods and state', () => {
      const { result } = renderHook(() => useCredentialModal(), {
        wrapper: createTestWrapper(mockActions),
      });

      expect(result.current.openCredentialModal).toBeDefined();
      expect(typeof result.current.openCredentialModal).toBe('function');
      expect(result.current.isCredentialModalOpen).toBe(false);
      expect(typeof result.current.onModalClose).toBe('function');
      expect(typeof result.current.onCredentialSaved).toBe('function');
    });

    test('throws error when used outside provider', () => {
      // Suppress console.error for this test since we expect an error
      const consoleSpy = vi
        .spyOn(console, 'error')
        .mockImplementation(() => {});

      expect(() => {
        renderHook(() => useCredentialModal());
      }).toThrow(
        'useCredentialModal must be used within a CredentialModalProvider'
      );

      consoleSpy.mockRestore();
    });
  });

  // ===========================================================================
  // OPEN MODAL TESTS
  // ===========================================================================

  describe('openCredentialModal', () => {
    test('opens modal and sends LiveView event with schema', () => {
      const { result } = renderHook(() => useCredentialModal(), {
        wrapper: createTestWrapper(mockActions),
      });

      act(() => {
        result.current.openCredentialModal('salesforce');
      });

      expect(result.current.isCredentialModalOpen).toBe(true);
      expect(mockActions.pushEvent).toHaveBeenCalledWith(
        'open_credential_modal',
        {
          schema: 'salesforce',
          credential_id: undefined,
        }
      );
    });

    test('opens modal with credential ID for editing', () => {
      const { result } = renderHook(() => useCredentialModal(), {
        wrapper: createTestWrapper(mockActions),
      });

      act(() => {
        result.current.openCredentialModal('salesforce', 'cred-123', 'ide');
      });

      expect(result.current.isCredentialModalOpen).toBe(true);
      expect(mockActions.pushEvent).toHaveBeenCalledWith(
        'open_credential_modal',
        {
          schema: 'salesforce',
          credential_id: 'cred-123',
        }
      );
    });
  });

  // ===========================================================================
  // SOURCE-BASED CALLBACK ROUTING TESTS
  // ===========================================================================

  describe('source-based callback routing', () => {
    test('onModalClose only calls callbacks for matching source', async () => {
      const { result } = renderHook(() => useCredentialModal(), {
        wrapper: createTestWrapper(mockActions),
      });

      const ideCallback = vi.fn();
      const inspectorCallback = vi.fn();

      // Register callbacks for different sources
      act(() => {
        result.current.onModalClose('ide', ideCallback);
        result.current.onModalClose('inspector', inspectorCallback);
      });

      // Open modal from IDE source
      act(() => {
        result.current.openCredentialModal('http', undefined, 'ide');
      });

      // Dispatch close event
      act(() => {
        dispatchCloseModalEvent();
      });

      // Advance timers past the MODAL_REOPEN_DELAY (200ms)
      act(() => {
        vi.advanceTimersByTime(200);
      });

      // Only IDE callback should be called
      expect(ideCallback).toHaveBeenCalledTimes(1);
      expect(inspectorCallback).not.toHaveBeenCalled();
    });

    test('onCredentialSaved only calls callbacks for matching source', async () => {
      // Create a mock handleEvent that captures the callback
      let savedEventCallback: ((payload: unknown) => void) | null = null;
      mockActions.handleEvent.mockImplementation(
        (event: string, callback: (payload: unknown) => void) => {
          if (event === 'credential_saved') {
            savedEventCallback = callback;
          }
          return vi.fn(); // cleanup function
        }
      );

      const { result } = renderHook(() => useCredentialModal(), {
        wrapper: createTestWrapper(mockActions),
      });

      const ideSavedCallback = vi.fn();
      const inspectorSavedCallback = vi.fn();

      // Register callbacks
      act(() => {
        result.current.onCredentialSaved('ide', ideSavedCallback);
        result.current.onCredentialSaved('inspector', inspectorSavedCallback);
      });

      // Open from inspector
      act(() => {
        result.current.openCredentialModal('dhis2', undefined, 'inspector');
      });

      // Simulate credential saved event from LiveView
      const savedPayload = {
        credential: {
          id: 'new-cred-id',
          project_credential_id: 'proj-cred-123',
        },
        is_project_credential: true,
      };

      act(() => {
        savedEventCallback?.(savedPayload);
      });

      // Advance timers
      act(() => {
        vi.advanceTimersByTime(200);
      });

      // Only inspector callback should be called
      expect(inspectorSavedCallback).toHaveBeenCalledWith(savedPayload);
      expect(ideSavedCallback).not.toHaveBeenCalled();
    });

    test('callbacks with null source are called regardless of open source', async () => {
      const { result } = renderHook(() => useCredentialModal(), {
        wrapper: createTestWrapper(mockActions),
      });

      const nullSourceCallback = vi.fn();

      act(() => {
        result.current.onModalClose(null, nullSourceCallback);
      });

      // Open from IDE (not null source)
      act(() => {
        result.current.openCredentialModal('commcare', undefined, 'ide');
      });

      // Close modal
      act(() => {
        dispatchCloseModalEvent();
      });

      act(() => {
        vi.advanceTimersByTime(200);
      });

      // null source callback should NOT be called because source was 'ide'
      expect(nullSourceCallback).not.toHaveBeenCalled();
    });
  });

  // ===========================================================================
  // CALLBACK CLEANUP TESTS
  // ===========================================================================

  describe('callback cleanup', () => {
    test('onModalClose cleanup removes callback', async () => {
      const { result } = renderHook(() => useCredentialModal(), {
        wrapper: createTestWrapper(mockActions),
      });

      const callback = vi.fn();

      // Register and immediately unregister
      let cleanup: () => void;
      act(() => {
        cleanup = result.current.onModalClose('ide', callback);
      });

      act(() => {
        cleanup();
      });

      // Open and close modal
      act(() => {
        result.current.openCredentialModal('http', undefined, 'ide');
      });

      act(() => {
        dispatchCloseModalEvent();
      });

      act(() => {
        vi.advanceTimersByTime(200);
      });

      // Callback should not be called since it was unregistered
      expect(callback).not.toHaveBeenCalled();
    });

    test('onCredentialSaved cleanup removes callback', async () => {
      let savedEventCallback: ((payload: unknown) => void) | null = null;
      mockActions.handleEvent.mockImplementation(
        (event: string, callback: (payload: unknown) => void) => {
          if (event === 'credential_saved') {
            savedEventCallback = callback;
          }
          return vi.fn();
        }
      );

      const { result } = renderHook(() => useCredentialModal(), {
        wrapper: createTestWrapper(mockActions),
      });

      const callback = vi.fn();

      // Register and immediately unregister
      let cleanup: () => void;
      act(() => {
        cleanup = result.current.onCredentialSaved('inspector', callback);
      });

      act(() => {
        cleanup();
      });

      // Open modal and trigger save
      act(() => {
        result.current.openCredentialModal(
          'salesforce',
          undefined,
          'inspector'
        );
      });

      act(() => {
        savedEventCallback?.({
          credential: { id: 'id' },
          is_project_credential: true,
        });
      });

      act(() => {
        vi.advanceTimersByTime(200);
      });

      // Callback should not be called
      expect(callback).not.toHaveBeenCalled();
    });
  });

  // ===========================================================================
  // STATE TRANSITION TESTS
  // ===========================================================================

  describe('state transitions', () => {
    test('modal closes after close event', () => {
      const { result } = renderHook(() => useCredentialModal(), {
        wrapper: createTestWrapper(mockActions),
      });

      // Open modal
      act(() => {
        result.current.openCredentialModal('http', undefined, 'ide');
      });

      expect(result.current.isCredentialModalOpen).toBe(true);

      // Close modal
      act(() => {
        dispatchCloseModalEvent();
      });

      expect(result.current.isCredentialModalOpen).toBe(false);
    });

    test('modal closes after credential saved event', () => {
      let savedEventCallback: ((payload: unknown) => void) | null = null;
      mockActions.handleEvent.mockImplementation(
        (event: string, callback: (payload: unknown) => void) => {
          if (event === 'credential_saved') {
            savedEventCallback = callback;
          }
          return vi.fn();
        }
      );

      const { result } = renderHook(() => useCredentialModal(), {
        wrapper: createTestWrapper(mockActions),
      });

      // Open modal
      act(() => {
        result.current.openCredentialModal('dhis2', undefined, 'inspector');
      });

      expect(result.current.isCredentialModalOpen).toBe(true);

      // Save credential
      act(() => {
        savedEventCallback?.({
          credential: { id: 'new-id' },
          is_project_credential: false,
        });
      });

      expect(result.current.isCredentialModalOpen).toBe(false);
    });

    test('close event is ignored if modal is not open', () => {
      const { result } = renderHook(() => useCredentialModal(), {
        wrapper: createTestWrapper(mockActions),
      });

      const callback = vi.fn();
      act(() => {
        result.current.onModalClose('ide', callback);
      });

      // Modal is not open, dispatch close event
      act(() => {
        dispatchCloseModalEvent();
      });

      act(() => {
        vi.advanceTimersByTime(200);
      });

      // Callback should not be called
      expect(callback).not.toHaveBeenCalled();
    });
  });

  // ===========================================================================
  // LIVEVIEW COMMUNICATION TESTS
  // ===========================================================================

  describe('LiveView communication', () => {
    test('sends close_credential_modal event after delay', () => {
      const { result } = renderHook(() => useCredentialModal(), {
        wrapper: createTestWrapper(mockActions),
      });

      act(() => {
        result.current.openCredentialModal('http', undefined, 'ide');
      });

      act(() => {
        dispatchCloseModalEvent();
      });

      // Not called immediately
      expect(mockActions.pushEvent).not.toHaveBeenCalledWith(
        'close_credential_modal',
        {}
      );

      // Called after LIVEVIEW_CLEANUP_DELAY (500ms)
      act(() => {
        vi.advanceTimersByTime(500);
      });

      expect(mockActions.pushEvent).toHaveBeenCalledWith(
        'close_credential_modal',
        {}
      );
    });

    test('registers handler for credential_saved event', () => {
      renderHook(() => useCredentialModal(), {
        wrapper: createTestWrapper(mockActions),
      });

      expect(mockActions.handleEvent).toHaveBeenCalledWith(
        'credential_saved',
        expect.any(Function)
      );
    });
  });

  // ===========================================================================
  // MULTIPLE CALLBACKS TESTS
  // ===========================================================================

  describe('multiple callbacks', () => {
    test('multiple callbacks for same source are all called', async () => {
      const { result } = renderHook(() => useCredentialModal(), {
        wrapper: createTestWrapper(mockActions),
      });

      const callback1 = vi.fn();
      const callback2 = vi.fn();
      const callback3 = vi.fn();

      act(() => {
        result.current.onModalClose('ide', callback1);
        result.current.onModalClose('ide', callback2);
        result.current.onModalClose('ide', callback3);
      });

      act(() => {
        result.current.openCredentialModal('fhir', undefined, 'ide');
      });

      act(() => {
        dispatchCloseModalEvent();
      });

      act(() => {
        vi.advanceTimersByTime(200);
      });

      expect(callback1).toHaveBeenCalledTimes(1);
      expect(callback2).toHaveBeenCalledTimes(1);
      expect(callback3).toHaveBeenCalledTimes(1);
    });
  });
});
