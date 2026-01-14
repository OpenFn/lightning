/**
 * CredentialModalContext Tests
 *
 * Verifies CredentialModalContext behavior:
 * - Context provision and hook access
 * - Opening modal and LiveView event communication
 * - Source-based callback routing (only matching source receives callbacks)
 * - Callback registration and cleanup
 * - State transitions
 *
 * Note: Both `credential_saved` and `credential_modal_closed` events come through
 * the WebSocket channel via handleEvent (not DOM events).
 */

import { act, renderHook } from '@testing-library/react';
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

// Store event callbacks so tests can trigger them
type EventCallbacks = {
  credential_saved?: (payload: unknown) => void;
  credential_modal_closed?: () => void;
};

function createMockLiveViewActions(eventCallbacks: EventCallbacks = {}) {
  return {
    pushEvent: vi.fn(),
    pushEventTo: vi.fn(),
    handleEvent: vi.fn(
      (event: string, callback: (payload?: unknown) => void) => {
        if (event === 'credential_saved') {
          eventCallbacks.credential_saved = callback;
        } else if (event === 'credential_modal_closed') {
          eventCallbacks.credential_modal_closed = callback as () => void;
        }
        return vi.fn(); // cleanup function
      }
    ),
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

describe('CredentialModalContext', () => {
  let mockActions: MockLiveViewActions;
  let eventCallbacks: EventCallbacks;

  beforeEach(() => {
    eventCallbacks = {};
    mockActions = createMockLiveViewActions(eventCallbacks);
    vi.useFakeTimers();
  });

  afterEach(() => {
    vi.clearAllMocks();
    vi.useRealTimers();
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

      // Simulate credential_modal_closed event from LiveView
      act(() => {
        eventCallbacks.credential_modal_closed?.();
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
        eventCallbacks.credential_saved?.(savedPayload);
      });

      // Advance timers
      act(() => {
        vi.advanceTimersByTime(200);
      });

      // Only inspector callback should be called
      expect(inspectorSavedCallback).toHaveBeenCalledWith(savedPayload);
      expect(ideSavedCallback).not.toHaveBeenCalled();
    });

    test('callbacks with null source are called when opened with null source', async () => {
      const { result } = renderHook(() => useCredentialModal(), {
        wrapper: createTestWrapper(mockActions),
      });

      const nullSourceCallback = vi.fn();

      act(() => {
        result.current.onModalClose(null, nullSourceCallback);
      });

      // Open with null source (default)
      act(() => {
        result.current.openCredentialModal('commcare');
      });

      // Close modal
      act(() => {
        eventCallbacks.credential_modal_closed?.();
      });

      act(() => {
        vi.advanceTimersByTime(200);
      });

      // null source callback should be called
      expect(nullSourceCallback).toHaveBeenCalledTimes(1);
    });

    test('null source callbacks are NOT called when opened with specific source', async () => {
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
        eventCallbacks.credential_modal_closed?.();
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
        eventCallbacks.credential_modal_closed?.();
      });

      act(() => {
        vi.advanceTimersByTime(200);
      });

      // Callback should not be called since it was unregistered
      expect(callback).not.toHaveBeenCalled();
    });

    test('onCredentialSaved cleanup removes callback', async () => {
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
        eventCallbacks.credential_saved?.({
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
    test('modal closes after credential_modal_closed event', () => {
      const { result } = renderHook(() => useCredentialModal(), {
        wrapper: createTestWrapper(mockActions),
      });

      // Open modal
      act(() => {
        result.current.openCredentialModal('http', undefined, 'ide');
      });

      expect(result.current.isCredentialModalOpen).toBe(true);

      // Close modal via event
      act(() => {
        eventCallbacks.credential_modal_closed?.();
      });

      expect(result.current.isCredentialModalOpen).toBe(false);
    });

    test('modal stays open after credential_saved event (closed by credential_modal_closed)', () => {
      const { result } = renderHook(() => useCredentialModal(), {
        wrapper: createTestWrapper(mockActions),
      });

      // Open modal
      act(() => {
        result.current.openCredentialModal('dhis2', undefined, 'inspector');
      });

      expect(result.current.isCredentialModalOpen).toBe(true);

      // Credential saved event doesn't close modal directly
      act(() => {
        eventCallbacks.credential_saved?.({
          credential: { id: 'new-id' },
          is_project_credential: false,
        });
      });

      // Modal is still open - waiting for credential_modal_closed
      expect(result.current.isCredentialModalOpen).toBe(true);

      // Now close event arrives
      act(() => {
        eventCallbacks.credential_modal_closed?.();
      });

      expect(result.current.isCredentialModalOpen).toBe(false);
    });
  });

  // ===========================================================================
  // LIVEVIEW COMMUNICATION TESTS
  // ===========================================================================

  describe('LiveView communication', () => {
    test('registers handlers for both credential events', () => {
      renderHook(() => useCredentialModal(), {
        wrapper: createTestWrapper(mockActions),
      });

      expect(mockActions.handleEvent).toHaveBeenCalledWith(
        'credential_saved',
        expect.any(Function)
      );
      expect(mockActions.handleEvent).toHaveBeenCalledWith(
        'credential_modal_closed',
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
        eventCallbacks.credential_modal_closed?.();
      });

      act(() => {
        vi.advanceTimersByTime(200);
      });

      expect(callback1).toHaveBeenCalledTimes(1);
      expect(callback2).toHaveBeenCalledTimes(1);
      expect(callback3).toHaveBeenCalledTimes(1);
    });
  });

  // ===========================================================================
  // EVENT ORDER TESTS (A+ solution specific)
  // ===========================================================================

  describe('event ordering', () => {
    test('credential_saved arrives before credential_modal_closed for save flow', async () => {
      const { result } = renderHook(() => useCredentialModal(), {
        wrapper: createTestWrapper(mockActions),
      });

      const savedCallback = vi.fn();
      const closeCallback = vi.fn();
      const callOrder: string[] = [];

      act(() => {
        result.current.onCredentialSaved('inspector', () => {
          callOrder.push('saved');
          savedCallback();
        });
        result.current.onModalClose('inspector', () => {
          callOrder.push('close');
          closeCallback();
        });
      });

      act(() => {
        result.current.openCredentialModal('http', undefined, 'inspector');
      });

      // Simulate save flow: credential_saved arrives first, then credential_modal_closed
      act(() => {
        eventCallbacks.credential_saved?.({
          credential: { id: 'new-id', project_credential_id: 'proj-id' },
          is_project_credential: true,
        });
      });

      act(() => {
        eventCallbacks.credential_modal_closed?.();
      });

      // Advance past all delays
      act(() => {
        vi.advanceTimersByTime(200);
      });

      // Both callbacks should be called
      expect(savedCallback).toHaveBeenCalledTimes(1);
      expect(closeCallback).toHaveBeenCalledTimes(1);

      // Saved should be called before close (both have same delay, but saved event arrived first)
      expect(callOrder).toEqual(['saved', 'close']);
    });
  });
});
