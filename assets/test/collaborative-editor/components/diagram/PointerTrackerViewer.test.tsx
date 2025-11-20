/**
 * PointerTrackerViewer Component Tests
 *
 * Tests for the PointerTrackerViewer component that tracks mouse movements
 * on the workflow diagram and broadcasts cursor position to other users.
 *
 * Test coverage:
 * - Mouse movement tracking and cursor updates
 * - Mouse leave detection and cursor clearing
 * - Viewport transform handling
 * - Event listener lifecycle
 * - Coordinate normalization integration
 * - Edge cases and boundary conditions
 */

import { fireEvent, render } from '@testing-library/react';
import { ReactFlowProvider } from '@xyflow/react';
import { afterEach, beforeEach, describe, expect, test, vi } from 'vitest';
import { Awareness } from 'y-protocols/awareness';
import * as Y from 'yjs';

import { PointerTrackerViewer } from '../../../../js/collaborative-editor/components/diagram/PointerTrackerViewer';
import { StoreContext } from '../../../../js/collaborative-editor/contexts/StoreProvider';
import type { AwarenessStoreInstance } from '../../../../js/collaborative-editor/stores/createAwarenessStore';
import { createAwarenessStore } from '../../../../js/collaborative-editor/stores/createAwarenessStore';

// Mock the @xyflow/react hooks
vi.mock('@xyflow/react', async () => {
  const actual = await vi.importActual('@xyflow/react');
  return {
    ...actual,
    useViewport: vi.fn(() => ({ x: 0, y: 0, zoom: 1 })),
  };
});

describe('PointerTrackerViewer', () => {
  let awarenessStore: AwarenessStoreInstance;
  let mockAwareness: Awareness;
  let ydoc: Y.Doc;
  let containerEl: HTMLDivElement;
  let updateLocalCursorSpy: ReturnType<typeof vi.spyOn>;

  beforeEach(() => {
    awarenessStore = createAwarenessStore();
    ydoc = new Y.Doc();
    mockAwareness = new Awareness(ydoc);

    // Initialize the awareness store
    awarenessStore.initializeAwareness(mockAwareness, {
      id: 'local-user',
      name: 'Local User',
      email: 'local@example.com',
      color: '#CCCCCC',
    });

    updateLocalCursorSpy = vi.spyOn(awarenessStore, 'updateLocalCursor');

    // Create a container element for the component
    containerEl = document.createElement('div');
    containerEl.style.width = '800px';
    containerEl.style.height = '600px';
    containerEl.style.position = 'relative';
    document.body.appendChild(containerEl);

    // Mock getBoundingClientRect for the container
    vi.spyOn(containerEl, 'getBoundingClientRect').mockReturnValue({
      left: 100,
      top: 50,
      right: 900,
      bottom: 650,
      width: 800,
      height: 600,
      x: 100,
      y: 50,
      toJSON: () => {},
    });
  });

  afterEach(() => {
    document.body.removeChild(containerEl);
    vi.restoreAllMocks();
  });

  const renderWithProviders = (component: React.ReactElement) => {
    return render(
      <StoreContext.Provider value={{ awarenessStore }}>
        <ReactFlowProvider>{component}</ReactFlowProvider>
      </StoreContext.Provider>
    );
  };

  describe('mouse movement tracking', () => {
    test('updates local cursor on mouse move', () => {
      renderWithProviders(<PointerTrackerViewer containerEl={containerEl} />);

      // Simulate mouse move at screen position (200, 150)
      // Relative to container: (200 - 100, 150 - 50) = (100, 100)
      fireEvent.mouseMove(containerEl, {
        clientX: 200,
        clientY: 150,
      });

      expect(updateLocalCursorSpy).toHaveBeenCalledWith({ x: 100, y: 100 });
    });

    test('tracks multiple mouse movements', () => {
      renderWithProviders(<PointerTrackerViewer containerEl={containerEl} />);

      // First movement
      fireEvent.mouseMove(containerEl, {
        clientX: 200,
        clientY: 150,
      });

      expect(updateLocalCursorSpy).toHaveBeenCalledWith({ x: 100, y: 100 });

      // Second movement
      fireEvent.mouseMove(containerEl, {
        clientX: 300,
        clientY: 250,
      });

      expect(updateLocalCursorSpy).toHaveBeenCalledWith({ x: 200, y: 200 });

      expect(updateLocalCursorSpy).toHaveBeenCalledTimes(2);
    });

    test('handles mouse move at container origin', () => {
      renderWithProviders(<PointerTrackerViewer containerEl={containerEl} />);

      // Mouse at top-left corner of container
      fireEvent.mouseMove(containerEl, {
        clientX: 100,
        clientY: 50,
      });

      expect(updateLocalCursorSpy).toHaveBeenCalledWith({ x: 0, y: 0 });
    });

    test('handles mouse move at container boundaries', () => {
      renderWithProviders(<PointerTrackerViewer containerEl={containerEl} />);

      // Bottom-right corner
      fireEvent.mouseMove(containerEl, {
        clientX: 900,
        clientY: 650,
      });

      expect(updateLocalCursorSpy).toHaveBeenCalledWith({ x: 800, y: 600 });
    });

    test('handles mouse move outside container bounds', () => {
      renderWithProviders(<PointerTrackerViewer containerEl={containerEl} />);

      // Move beyond container (this can happen during drag)
      fireEvent.mouseMove(containerEl, {
        clientX: 1000,
        clientY: 700,
      });

      // Should still calculate relative position (even if negative or beyond bounds)
      expect(updateLocalCursorSpy).toHaveBeenCalledWith({ x: 900, y: 650 });
    });

    test('handles negative relative positions', () => {
      renderWithProviders(<PointerTrackerViewer containerEl={containerEl} />);

      // Move before container start
      fireEvent.mouseMove(containerEl, {
        clientX: 50,
        clientY: 25,
      });

      expect(updateLocalCursorSpy).toHaveBeenCalledWith({ x: -50, y: -25 });
    });

    test('handles fractional pixel positions', () => {
      renderWithProviders(<PointerTrackerViewer containerEl={containerEl} />);

      fireEvent.mouseMove(containerEl, {
        clientX: 150.5,
        clientY: 100.7,
      });

      expect(updateLocalCursorSpy).toHaveBeenCalledWith({
        x: 50.5,
        y: 50.7,
      });
    });
  });

  describe('mouse leave handling', () => {
    test('clears cursor on mouse leave', () => {
      renderWithProviders(<PointerTrackerViewer containerEl={containerEl} />);

      // First move the mouse
      fireEvent.mouseMove(containerEl, {
        clientX: 200,
        clientY: 150,
      });

      expect(updateLocalCursorSpy).toHaveBeenCalledWith({ x: 100, y: 100 });

      // Then leave
      fireEvent.mouseLeave(containerEl);

      expect(updateLocalCursorSpy).toHaveBeenCalledWith(null);
    });

    test('cursor can be re-established after leaving', () => {
      renderWithProviders(<PointerTrackerViewer containerEl={containerEl} />);

      // Move
      fireEvent.mouseMove(containerEl, {
        clientX: 200,
        clientY: 150,
      });

      // Leave
      fireEvent.mouseLeave(containerEl);

      // Move again
      fireEvent.mouseMove(containerEl, {
        clientX: 300,
        clientY: 250,
      });

      expect(updateLocalCursorSpy).toHaveBeenLastCalledWith({ x: 200, y: 200 });
    });
  });

  describe('viewport transform integration', () => {
    test('applies viewport pan to cursor position', async () => {
      const { useViewport } = await import('@xyflow/react');

      // Set viewport with pan offset
      vi.mocked(useViewport).mockReturnValue({ x: 50, y: 30, zoom: 1 });

      renderWithProviders(<PointerTrackerViewer containerEl={containerEl} />);

      // Mouse at (200, 150) screen coords = (100, 100) container-relative
      fireEvent.mouseMove(containerEl, {
        clientX: 200,
        clientY: 150,
      });

      // With pan (50, 30) and no zoom:
      // normalized = ((100 - 50) / 1, (100 - 30) / 1) = (50, 70)
      expect(updateLocalCursorSpy).toHaveBeenCalledWith({ x: 50, y: 70 });
    });

    test('applies viewport zoom to cursor position', async () => {
      const { useViewport } = await import('@xyflow/react');

      // Set viewport with 2x zoom
      vi.mocked(useViewport).mockReturnValue({ x: 0, y: 0, zoom: 2 });

      renderWithProviders(<PointerTrackerViewer containerEl={containerEl} />);

      // Mouse at (200, 150) screen coords = (100, 100) container-relative
      fireEvent.mouseMove(containerEl, {
        clientX: 200,
        clientY: 150,
      });

      // With 2x zoom: normalized = (100 / 2, 100 / 2) = (50, 50)
      expect(updateLocalCursorSpy).toHaveBeenCalledWith({ x: 50, y: 50 });
    });

    test('applies combined pan and zoom', async () => {
      const { useViewport } = await import('@xyflow/react');

      // Pan and zoom
      vi.mocked(useViewport).mockReturnValue({ x: 50, y: 30, zoom: 2 });

      renderWithProviders(<PointerTrackerViewer containerEl={containerEl} />);

      fireEvent.mouseMove(containerEl, {
        clientX: 200,
        clientY: 150,
      });

      // Container-relative: (100, 100)
      // With pan and zoom: ((100 - 50) / 2, (100 - 30) / 2) = (25, 35)
      expect(updateLocalCursorSpy).toHaveBeenCalledWith({ x: 25, y: 35 });
    });

    test('handles viewport changes reactively', async () => {
      const { useViewport } = await import('@xyflow/react');

      // Start with no transform
      vi.mocked(useViewport).mockReturnValue({ x: 0, y: 0, zoom: 1 });

      const { rerender } = renderWithProviders(
        <PointerTrackerViewer containerEl={containerEl} />
      );

      fireEvent.mouseMove(containerEl, {
        clientX: 200,
        clientY: 150,
      });

      expect(updateLocalCursorSpy).toHaveBeenCalledWith({ x: 100, y: 100 });

      // Change viewport
      vi.mocked(useViewport).mockReturnValue({ x: 50, y: 50, zoom: 2 });

      rerender(
        <StoreContext.Provider value={{ awarenessStore }}>
          <ReactFlowProvider>
            <PointerTrackerViewer containerEl={containerEl} />
          </ReactFlowProvider>
        </StoreContext.Provider>
      );

      // Move mouse again with new viewport
      fireEvent.mouseMove(containerEl, {
        clientX: 200,
        clientY: 150,
      });

      // New calculation: ((100 - 50) / 2, (100 - 50) / 2) = (25, 25)
      expect(updateLocalCursorSpy).toHaveBeenCalledWith({ x: 25, y: 25 });
    });

    test('handles extreme zoom levels', async () => {
      const { useViewport } = await import('@xyflow/react');

      vi.mocked(useViewport).mockReturnValue({ x: 0, y: 0, zoom: 10 });

      renderWithProviders(<PointerTrackerViewer containerEl={containerEl} />);

      fireEvent.mouseMove(containerEl, {
        clientX: 200,
        clientY: 150,
      });

      // (100 / 10, 100 / 10) = (10, 10)
      expect(updateLocalCursorSpy).toHaveBeenCalledWith({ x: 10, y: 10 });
    });

    test('handles zoom out (scale < 1)', async () => {
      const { useViewport } = await import('@xyflow/react');

      vi.mocked(useViewport).mockReturnValue({ x: 0, y: 0, zoom: 0.5 });

      renderWithProviders(<PointerTrackerViewer containerEl={containerEl} />);

      fireEvent.mouseMove(containerEl, {
        clientX: 200,
        clientY: 150,
      });

      // (100 / 0.5, 100 / 0.5) = (200, 200)
      expect(updateLocalCursorSpy).toHaveBeenCalledWith({ x: 200, y: 200 });
    });

    test('handles negative pan offsets', async () => {
      const { useViewport } = await import('@xyflow/react');

      vi.mocked(useViewport).mockReturnValue({ x: -50, y: -30, zoom: 1 });

      renderWithProviders(<PointerTrackerViewer containerEl={containerEl} />);

      fireEvent.mouseMove(containerEl, {
        clientX: 200,
        clientY: 150,
      });

      // ((100 - (-50)) / 1, (100 - (-30)) / 1) = (150, 130)
      expect(updateLocalCursorSpy).toHaveBeenCalledWith({ x: 150, y: 130 });
    });
  });

  describe('event listener lifecycle', () => {
    test('adds event listeners on mount', () => {
      const addEventListenerSpy = vi.spyOn(containerEl, 'addEventListener');

      renderWithProviders(<PointerTrackerViewer containerEl={containerEl} />);

      expect(addEventListenerSpy).toHaveBeenCalledWith(
        'mousemove',
        expect.any(Function)
      );
      expect(addEventListenerSpy).toHaveBeenCalledWith(
        'mouseleave',
        expect.any(Function)
      );
    });

    test('removes event listeners on unmount', () => {
      const removeEventListenerSpy = vi.spyOn(
        containerEl,
        'removeEventListener'
      );

      const { unmount } = renderWithProviders(
        <PointerTrackerViewer containerEl={containerEl} />
      );

      unmount();

      expect(removeEventListenerSpy).toHaveBeenCalledWith(
        'mousemove',
        expect.any(Function)
      );
      expect(removeEventListenerSpy).toHaveBeenCalledWith(
        'mouseleave',
        expect.any(Function)
      );
    });

    test('cleans up and re-adds listeners when container changes', () => {
      const { rerender } = renderWithProviders(
        <PointerTrackerViewer containerEl={containerEl} />
      );

      const removeEventListenerSpy = vi.spyOn(
        containerEl,
        'removeEventListener'
      );

      // Create new container
      const newContainerEl = document.createElement('div');
      newContainerEl.style.width = '800px';
      newContainerEl.style.height = '600px';
      document.body.appendChild(newContainerEl);

      const addEventListenerSpy = vi.spyOn(newContainerEl, 'addEventListener');

      rerender(
        <StoreContext.Provider value={{ awarenessStore }}>
          <ReactFlowProvider>
            <PointerTrackerViewer containerEl={newContainerEl} />
          </ReactFlowProvider>
        </StoreContext.Provider>
      );

      // Should remove from old container
      expect(removeEventListenerSpy).toHaveBeenCalled();

      // Should add to new container
      expect(addEventListenerSpy).toHaveBeenCalledWith(
        'mousemove',
        expect.any(Function)
      );
      expect(addEventListenerSpy).toHaveBeenCalledWith(
        'mouseleave',
        expect.any(Function)
      );

      document.body.removeChild(newContainerEl);
    });

    test('handles rapid viewport updates without losing listeners', async () => {
      const { useViewport } = await import('@xyflow/react');

      vi.mocked(useViewport).mockReturnValue({ x: 0, y: 0, zoom: 1 });

      const { rerender } = renderWithProviders(
        <PointerTrackerViewer containerEl={containerEl} />
      );

      // Rapidly change viewport multiple times
      for (let i = 0; i < 10; i++) {
        vi.mocked(useViewport).mockReturnValue({
          x: i * 10,
          y: i * 10,
          zoom: 1,
        });

        rerender(
          <StoreContext.Provider value={{ awarenessStore }}>
            <ReactFlowProvider>
              <PointerTrackerViewer containerEl={containerEl} />
            </ReactFlowProvider>
          </StoreContext.Provider>
        );
      }

      // Event listeners should still work
      fireEvent.mouseMove(containerEl, {
        clientX: 200,
        clientY: 150,
      });

      expect(updateLocalCursorSpy).toHaveBeenCalled();
    });
  });

  describe('edge cases', () => {
    test('handles container with zero bounds', () => {
      const zeroBoundsContainer = document.createElement('div');
      document.body.appendChild(zeroBoundsContainer);

      vi.spyOn(zeroBoundsContainer, 'getBoundingClientRect').mockReturnValue({
        left: 0,
        top: 0,
        right: 0,
        bottom: 0,
        width: 0,
        height: 0,
        x: 0,
        y: 0,
        toJSON: () => {},
      });

      renderWithProviders(
        <PointerTrackerViewer containerEl={zeroBoundsContainer} />
      );

      fireEvent.mouseMove(zeroBoundsContainer, {
        clientX: 100,
        clientY: 100,
      });

      // Should still call updateLocalCursor
      expect(updateLocalCursorSpy).toHaveBeenCalled();

      document.body.removeChild(zeroBoundsContainer);
    });

    test('handles very large container', () => {
      const largeBoundsContainer = document.createElement('div');
      document.body.appendChild(largeBoundsContainer);

      vi.spyOn(largeBoundsContainer, 'getBoundingClientRect').mockReturnValue({
        left: 0,
        top: 0,
        right: 10000,
        bottom: 10000,
        width: 10000,
        height: 10000,
        x: 0,
        y: 0,
        toJSON: () => {},
      });

      renderWithProviders(
        <PointerTrackerViewer containerEl={largeBoundsContainer} />
      );

      fireEvent.mouseMove(largeBoundsContainer, {
        clientX: 5000,
        clientY: 5000,
      });

      expect(updateLocalCursorSpy).toHaveBeenCalledWith({ x: 5000, y: 5000 });

      document.body.removeChild(largeBoundsContainer);
    });

    test('handles container positioned off-screen', () => {
      const offScreenContainer = document.createElement('div');
      document.body.appendChild(offScreenContainer);

      vi.spyOn(offScreenContainer, 'getBoundingClientRect').mockReturnValue({
        left: -1000,
        top: -1000,
        right: -200,
        bottom: -400,
        width: 800,
        height: 600,
        x: -1000,
        y: -1000,
        toJSON: () => {},
      });

      renderWithProviders(
        <PointerTrackerViewer containerEl={offScreenContainer} />
      );

      fireEvent.mouseMove(offScreenContainer, {
        clientX: -900,
        clientY: -900,
      });

      // -900 - (-1000) = 100
      expect(updateLocalCursorSpy).toHaveBeenCalledWith({ x: 100, y: 100 });

      document.body.removeChild(offScreenContainer);
    });

    test('handles rapid mouse movements', () => {
      renderWithProviders(<PointerTrackerViewer containerEl={containerEl} />);

      // Simulate 100 rapid movements
      for (let i = 0; i < 100; i++) {
        fireEvent.mouseMove(containerEl, {
          clientX: 100 + i,
          clientY: 50 + i,
        });
      }

      expect(updateLocalCursorSpy).toHaveBeenCalledTimes(100);
    });

    test('handles mouse events with no clientX/clientY (edge case)', () => {
      renderWithProviders(<PointerTrackerViewer containerEl={containerEl} />);

      // Some browsers might send events without proper coordinates
      fireEvent.mouseMove(containerEl, {} as any);

      // Should handle gracefully (NaN coordinates)
      expect(updateLocalCursorSpy).toHaveBeenCalled();
    });
  });

  describe('performance considerations', () => {
    test('handles awareness store updates during mouse movement', async () => {
      renderWithProviders(<PointerTrackerViewer containerEl={containerEl} />);

      // Move mouse
      fireEvent.mouseMove(containerEl, {
        clientX: 200,
        clientY: 150,
      });

      // Update awareness store while mouse is moving
      // Simulate a remote user appearing
      const remoteState = {
        user: { id: 'user-1', name: 'Alice', color: '#FF0000' },
        cursor: { x: 50, y: 50 },
      };
      mockAwareness.states.set(999, remoteState);
      awarenessStore._internal.handleAwarenessChange();

      // Continue moving
      fireEvent.mouseMove(containerEl, {
        clientX: 300,
        clientY: 250,
      });

      // Should still work correctly
      expect(updateLocalCursorSpy).toHaveBeenCalled();
    });
  });
});
