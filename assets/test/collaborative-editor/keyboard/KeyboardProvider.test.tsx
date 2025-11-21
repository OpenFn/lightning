/**
 * Unit tests for KeyboardProvider and useKeyboardShortcut
 */

import { act, render, waitFor } from '@testing-library/react';
import React from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import {
  KeyboardProvider,
  useKeyboardShortcut,
} from '../../../js/collaborative-editor/keyboard/KeyboardProvider';
import type { KeyboardHandlerOptions } from '../../../js/collaborative-editor/keyboard/types';

describe('KeyboardProvider', () => {
  // Helper component for testing
  function TestComponent({
    combos,
    callback,
    priority = 0,
    options,
  }: {
    combos: string;
    callback: (e: KeyboardEvent) => boolean | void;
    priority?: number;
    options?: KeyboardHandlerOptions;
  }) {
    useKeyboardShortcut(combos, callback, priority, options);
    return <div>Test Component</div>;
  }

  beforeEach(() => {
    // Clear any existing keyboard listeners
    document.body.innerHTML = '';
  });

  afterEach(() => {
    vi.clearAllMocks();
  });

  describe('Basic functionality', () => {
    it('should call handler when key pressed', async () => {
      const handler = vi.fn();

      render(
        <KeyboardProvider>
          <TestComponent combos="Escape" callback={handler} />
        </KeyboardProvider>
      );

      // Simulate Escape key press
      const event = new KeyboardEvent('keydown', { key: 'Escape' });
      window.dispatchEvent(event);

      await waitFor(() => {
        expect(handler).toHaveBeenCalledTimes(1);
      });
    });

    it('should support multiple key combos', async () => {
      const handler = vi.fn();

      render(
        <KeyboardProvider>
          <TestComponent
            combos="$mod+Enter, Control+Enter"
            callback={handler}
          />
        </KeyboardProvider>
      );

      // Simulate Cmd+Enter
      const event1 = new KeyboardEvent('keydown', {
        key: 'Enter',
        metaKey: true,
      });
      window.dispatchEvent(event1);

      // Simulate Ctrl+Enter
      const event2 = new KeyboardEvent('keydown', {
        key: 'Enter',
        ctrlKey: true,
      });
      window.dispatchEvent(event2);

      await waitFor(() => {
        expect(handler).toHaveBeenCalledTimes(2);
      });
    });

    it('should cleanup handler on unmount', async () => {
      const handler = vi.fn();

      const { unmount } = render(
        <KeyboardProvider>
          <TestComponent combos="Escape" callback={handler} />
        </KeyboardProvider>
      );

      unmount();

      // Simulate key press after unmount
      const event = new KeyboardEvent('keydown', { key: 'Escape' });
      window.dispatchEvent(event);

      // Wait a bit to ensure no handler is called
      await new Promise(resolve => setTimeout(resolve, 50));

      expect(handler).not.toHaveBeenCalled();
    });
  });

  describe('Priority handling', () => {
    it('should call highest priority handler first', async () => {
      const lowPriorityHandler = vi.fn();
      const highPriorityHandler = vi.fn();

      render(
        <KeyboardProvider>
          <TestComponent
            combos="Escape"
            callback={lowPriorityHandler}
            priority={0}
          />
          <TestComponent
            combos="Escape"
            callback={highPriorityHandler}
            priority={100}
          />
        </KeyboardProvider>
      );

      const event = new KeyboardEvent('keydown', { key: 'Escape' });
      window.dispatchEvent(event);

      await waitFor(() => {
        expect(highPriorityHandler).toHaveBeenCalledTimes(1);
        expect(lowPriorityHandler).not.toHaveBeenCalled();
      });
    });

    it('should call most recent handler when priorities equal', async () => {
      const firstHandler = vi.fn();
      const secondHandler = vi.fn();

      // Component that mounts handlers sequentially
      function SequentialTestComponents() {
        const [showSecond, setShowSecond] = React.useState(false);

        React.useEffect(() => {
          // Mount second handler after a delay
          const timer = setTimeout(() => setShowSecond(true), 10);
          return () => clearTimeout(timer);
        }, []);

        return (
          <>
            <TestComponent
              combos="Escape"
              callback={firstHandler}
              priority={10}
            />
            {showSecond && (
              <TestComponent
                combos="Escape"
                callback={secondHandler}
                priority={10}
              />
            )}
          </>
        );
      }

      render(
        <KeyboardProvider>
          <SequentialTestComponents />
        </KeyboardProvider>
      );

      // Wait for second component to mount
      await act(async () => {
        await new Promise(resolve => setTimeout(resolve, 50));
      });

      // Now dispatch the event once
      const event = new KeyboardEvent('keydown', { key: 'Escape' });
      window.dispatchEvent(event);

      await waitFor(() => {
        expect(secondHandler).toHaveBeenCalled();
      });

      expect(secondHandler).toHaveBeenCalledTimes(1);
      expect(firstHandler).not.toHaveBeenCalled();
    });

    it('should try next handler when current returns false', async () => {
      const lowPriorityHandler = vi.fn();
      const highPriorityHandler = vi.fn(() => false); // Return false to pass

      render(
        <KeyboardProvider>
          <TestComponent
            combos="Escape"
            callback={lowPriorityHandler}
            priority={0}
          />
          <TestComponent
            combos="Escape"
            callback={highPriorityHandler}
            priority={100}
          />
        </KeyboardProvider>
      );

      const event = new KeyboardEvent('keydown', { key: 'Escape' });
      window.dispatchEvent(event);

      await waitFor(() => {
        expect(highPriorityHandler).toHaveBeenCalledTimes(1);
        expect(lowPriorityHandler).toHaveBeenCalledTimes(1);
      });
    });

    it('should not call disabled handlers', async () => {
      const enabledHandler = vi.fn();
      const disabledHandler = vi.fn();

      render(
        <KeyboardProvider>
          <TestComponent
            combos="Escape"
            callback={disabledHandler}
            priority={100}
            options={{ enabled: false }}
          />
          <TestComponent
            combos="Escape"
            callback={enabledHandler}
            priority={0}
          />
        </KeyboardProvider>
      );

      const event = new KeyboardEvent('keydown', { key: 'Escape' });
      window.dispatchEvent(event);

      await waitFor(() => {
        expect(disabledHandler).not.toHaveBeenCalled();
        expect(enabledHandler).toHaveBeenCalledTimes(1);
      });
    });
  });

  describe('Options handling', () => {
    it('should call preventDefault by default', async () => {
      const handler = vi.fn();

      render(
        <KeyboardProvider>
          <TestComponent combos="Escape" callback={handler} />
        </KeyboardProvider>
      );

      const event = new KeyboardEvent('keydown', {
        key: 'Escape',
        cancelable: true,
      });
      const preventDefaultSpy = vi.spyOn(event, 'preventDefault');

      window.dispatchEvent(event);

      await waitFor(() => {
        expect(preventDefaultSpy).toHaveBeenCalled();
      });
    });

    it('should not call preventDefault when disabled', async () => {
      const handler = vi.fn();

      render(
        <KeyboardProvider>
          <TestComponent
            combos="Escape"
            callback={handler}
            options={{ preventDefault: false }}
          />
        </KeyboardProvider>
      );

      const event = new KeyboardEvent('keydown', {
        key: 'Escape',
        cancelable: true,
      });
      const preventDefaultSpy = vi.spyOn(event, 'preventDefault');

      window.dispatchEvent(event);

      await waitFor(() => {
        expect(handler).toHaveBeenCalled();
        expect(preventDefaultSpy).not.toHaveBeenCalled();
      });
    });

    it('should call stopPropagation by default', async () => {
      const handler = vi.fn();

      render(
        <KeyboardProvider>
          <TestComponent combos="Escape" callback={handler} />
        </KeyboardProvider>
      );

      const event = new KeyboardEvent('keydown', {
        key: 'Escape',
        bubbles: true,
      });
      const stopPropagationSpy = vi.spyOn(event, 'stopPropagation');

      window.dispatchEvent(event);

      await waitFor(() => {
        expect(stopPropagationSpy).toHaveBeenCalled();
      });
    });

    it('should not call stopPropagation when disabled', async () => {
      const handler = vi.fn();

      render(
        <KeyboardProvider>
          <TestComponent
            combos="Escape"
            callback={handler}
            options={{ stopPropagation: false }}
          />
        </KeyboardProvider>
      );

      const event = new KeyboardEvent('keydown', {
        key: 'Escape',
        bubbles: true,
      });
      const stopPropagationSpy = vi.spyOn(event, 'stopPropagation');

      window.dispatchEvent(event);

      await waitFor(() => {
        expect(handler).toHaveBeenCalled();
        expect(stopPropagationSpy).not.toHaveBeenCalled();
      });
    });
  });

  describe('Edge cases', () => {
    it('should throw error when used outside provider', () => {
      // Suppress console.error for this test
      const consoleError = vi
        .spyOn(console, 'error')
        .mockImplementation(() => {});

      expect(() => {
        render(<TestComponent combos="Escape" callback={vi.fn()} />);
      }).toThrow('useKeyboardShortcut must be used within KeyboardProvider');

      consoleError.mockRestore();
    });

    it('should re-throw errors and stop handler chain', async () => {
      const errorHandler = vi.fn(() => {
        throw new Error('Handler error');
      });
      const fallbackHandler = vi.fn();
      const consoleError = vi
        .spyOn(console, 'error')
        .mockImplementation(() => {});

      // Spy on window error event
      const errorSpy = vi.fn();
      window.addEventListener('error', errorSpy);

      render(
        <KeyboardProvider>
          <TestComponent
            combos="Escape"
            callback={errorHandler}
            priority={10}
          />
          <TestComponent
            combos="Escape"
            callback={fallbackHandler}
            priority={0}
          />
        </KeyboardProvider>
      );

      const event = new KeyboardEvent('keydown', { key: 'Escape' });
      window.dispatchEvent(event);

      await waitFor(() => {
        expect(errorHandler).toHaveBeenCalled();
        expect(consoleError).toHaveBeenCalled();
      });

      expect(fallbackHandler).not.toHaveBeenCalled(); // Chain stopped

      window.removeEventListener('error', errorSpy);
      consoleError.mockRestore();
    });

    it('should handle rapid mount/unmount', async () => {
      const handler = vi.fn();

      // First render and unmount
      const { unmount } = render(
        <KeyboardProvider>
          <TestComponent combos="Escape" callback={handler} />
        </KeyboardProvider>
      );

      unmount();

      // Second render (fresh, not rerender)
      render(
        <KeyboardProvider>
          <TestComponent combos="Escape" callback={handler} />
        </KeyboardProvider>
      );

      const event = new KeyboardEvent('keydown', { key: 'Escape' });
      window.dispatchEvent(event);

      await waitFor(() => {
        expect(handler).toHaveBeenCalledTimes(1);
      });
    });

    it('should handle multiple handlers for different keys independently', async () => {
      const escapeHandler = vi.fn();
      const enterHandler = vi.fn();

      render(
        <KeyboardProvider>
          <TestComponent combos="Escape" callback={escapeHandler} />
          <TestComponent combos="Enter" callback={enterHandler} />
        </KeyboardProvider>
      );

      const escapeEvent = new KeyboardEvent('keydown', { key: 'Escape' });
      window.dispatchEvent(escapeEvent);

      const enterEvent = new KeyboardEvent('keydown', { key: 'Enter' });
      window.dispatchEvent(enterEvent);

      await waitFor(() => {
        expect(escapeHandler).toHaveBeenCalledTimes(1);
        expect(enterHandler).toHaveBeenCalledTimes(1);
      });
    });
  });

  describe('Error handling', () => {
    it('should re-throw errors from handlers immediately', async () => {
      const testError = new Error('Test error');
      const errorHandler = vi.fn(() => {
        throw testError;
      });
      const consoleError = vi
        .spyOn(console, 'error')
        .mockImplementation(() => {});

      // Spy on window error event to catch uncaught errors
      const errorSpy = vi.fn();
      window.addEventListener('error', errorSpy);

      render(
        <KeyboardProvider>
          <TestComponent combos="Escape" callback={errorHandler} />
        </KeyboardProvider>
      );

      const event = new KeyboardEvent('keydown', { key: 'Escape' });

      // dispatchEvent itself doesn't throw in tests, but the error should propagate
      window.dispatchEvent(event);

      // Wait for error to be logged
      await waitFor(() => {
        expect(consoleError).toHaveBeenCalledWith(
          '[KeyboardProvider] Error in handler for "Escape":',
          testError
        );
      });

      // The error should have propagated (uncaught)
      await waitFor(() => {
        expect(errorSpy).toHaveBeenCalled();
      });

      window.removeEventListener('error', errorSpy);
      consoleError.mockRestore();
    });

    it('should NOT call fallback handler when higher priority throws', async () => {
      const testError = new Error('High priority error');
      const errorHandler = vi.fn(() => {
        throw testError;
      });
      const fallbackHandler = vi.fn();
      const consoleError = vi
        .spyOn(console, 'error')
        .mockImplementation(() => {});

      // Spy on window error event
      const errorSpy = vi.fn();
      window.addEventListener('error', errorSpy);

      render(
        <KeyboardProvider>
          <TestComponent
            combos="Escape"
            callback={errorHandler}
            priority={10}
          />
          <TestComponent
            combos="Escape"
            callback={fallbackHandler}
            priority={0}
          />
        </KeyboardProvider>
      );

      const event = new KeyboardEvent('keydown', { key: 'Escape' });
      window.dispatchEvent(event);

      await waitFor(() => {
        // Error handler was called
        expect(errorHandler).toHaveBeenCalled();
      });

      // Fallback handler should NOT be called (error stops the chain)
      expect(fallbackHandler).not.toHaveBeenCalled();

      window.removeEventListener('error', errorSpy);
      consoleError.mockRestore();
    });

    it('should log error to console before re-throwing', async () => {
      const testError = new Error('Test error');
      const errorHandler = vi.fn(() => {
        throw testError;
      });
      const consoleError = vi
        .spyOn(console, 'error')
        .mockImplementation(() => {});

      // Spy on window error event
      const errorSpy = vi.fn();
      window.addEventListener('error', errorSpy);

      render(
        <KeyboardProvider>
          <TestComponent combos="Escape" callback={errorHandler} />
        </KeyboardProvider>
      );

      const event = new KeyboardEvent('keydown', { key: 'Escape' });
      window.dispatchEvent(event);

      await waitFor(() => {
        expect(consoleError).toHaveBeenCalledWith(
          '[KeyboardProvider] Error in handler for "Escape":',
          testError
        );
      });

      window.removeEventListener('error', errorSpy);
      consoleError.mockRestore();
    });

    it('should only fallback on "return false", not on errors', async () => {
      const highPriorityPass = vi.fn(() => false); // Returns false - should pass
      const lowPriorityHandler = vi.fn();

      render(
        <KeyboardProvider>
          <TestComponent
            combos="Escape"
            callback={highPriorityPass}
            priority={10}
          />
          <TestComponent
            combos="Escape"
            callback={lowPriorityHandler}
            priority={0}
          />
        </KeyboardProvider>
      );

      const event = new KeyboardEvent('keydown', { key: 'Escape' });
      window.dispatchEvent(event);

      await waitFor(() => {
        expect(highPriorityPass).toHaveBeenCalled();
        expect(lowPriorityHandler).toHaveBeenCalled(); // Should be called
      });
    });
  });

  describe('Dynamic enabled state', () => {
    it('should respect enabled option when component mounts/unmounts', async () => {
      const handler = vi.fn();

      function DynamicTestComponent({ show }: { show: boolean }) {
        return show ? (
          <TestComponent combos="Escape" callback={handler} priority={0} />
        ) : (
          <div>No handler</div>
        );
      }

      // Mount with handler enabled
      const { rerender } = render(
        <KeyboardProvider>
          <DynamicTestComponent show={true} />
        </KeyboardProvider>
      );

      // First key press - should work
      const event1 = new KeyboardEvent('keydown', { key: 'Escape' });
      window.dispatchEvent(event1);

      await waitFor(() => {
        expect(handler).toHaveBeenCalledTimes(1);
      });

      // Unmount handler by not showing
      rerender(
        <KeyboardProvider>
          <DynamicTestComponent show={false} />
        </KeyboardProvider>
      );

      // Wait for unmount to complete
      await new Promise(resolve => setTimeout(resolve, 50));

      // Second key press - should not work (handler unmounted)
      const event2 = new KeyboardEvent('keydown', { key: 'Escape' });
      window.dispatchEvent(event2);

      // Wait to ensure handler wasn't called
      await new Promise(resolve => setTimeout(resolve, 50));

      expect(handler).toHaveBeenCalledTimes(1); // Still 1, not 2
    });
  });
});
