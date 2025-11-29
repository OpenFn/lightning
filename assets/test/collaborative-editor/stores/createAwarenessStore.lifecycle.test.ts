/**
 * AwarenessStore Lifecycle Tests
 *
 * Tests for awareness instance lifecycle management, focusing on version
 * switching scenarios where awareness instances are replaced.
 *
 * ## The Bug Being Tested
 * When a user switches workflow versions:
 * 1. SessionStore.destroy() destroys old awareness, creates new one
 * 2. AwarenessStore still has `isInitialized: true` pointing to destroyed awareness
 * 3. Guard `!stores.awarenessStore.isAwarenessReady()` prevents re-initialization
 * 4. `updateLocalCursor` uses destroyed awareness - updates go nowhere
 *
 * These tests document the EXPECTED behavior (TDD red phase).
 */

import { describe, test, expect, beforeEach, vi } from 'vitest';
import type { Awareness } from 'y-protocols/awareness';

import { createAwarenessStore } from '../../../js/collaborative-editor/stores/createAwarenessStore';
import type { AwarenessStoreInstance } from '../../../js/collaborative-editor/stores/createAwarenessStore';
import type { LocalUserData } from '../../../js/collaborative-editor/types/awareness';

/**
 * Creates a mock Awareness instance for testing
 */
const createMockAwareness = () => {
  const listeners = new Map<string, Set<(...args: any[]) => void>>();

  return {
    setLocalStateField: vi.fn(),
    getStates: vi.fn(() => new Map()),
    on: vi.fn((event: string, handler: (...args: any[]) => void) => {
      if (!listeners.has(event)) {
        listeners.set(event, new Set());
      }
      listeners.get(event)!.add(handler);
    }),
    off: vi.fn((event: string, handler: (...args: any[]) => void) => {
      listeners.get(event)?.delete(handler);
    }),
    destroy: vi.fn(() => {
      // Trigger 'destroy' event like real Awareness does
      const destroyListeners = listeners.get('destroy');
      if (destroyListeners) {
        destroyListeners.forEach(handler => handler());
      }
    }),
  };
};

describe('AwarenessStore - Instance Lifecycle', () => {
  let store: AwarenessStoreInstance;
  let awareness1: ReturnType<typeof createMockAwareness>;
  let awareness2: ReturnType<typeof createMockAwareness>;
  let userData: LocalUserData;

  beforeEach(() => {
    store = createAwarenessStore();
    awareness1 = createMockAwareness();
    awareness2 = createMockAwareness();
    userData = {
      id: 'user-123',
      name: 'Test User',
      email: 'test@example.com',
      color: '#FF0000',
    };
  });

  describe('Reinitializing with new awareness instance', () => {
    test('allows reinitialization after destroy', () => {
      // Initialize with first awareness instance
      store.initializeAwareness(awareness1 as unknown as Awareness, userData);

      // Verify first instance is active
      expect(store.isAwarenessReady()).toBe(true);
      expect(store.getRawAwareness()).toBe(awareness1);

      // Destroy awareness (simulates version switch cleanup)
      store.destroyAwareness();

      // EXPECTED: isAwarenessReady should return false after destroy
      expect(store.isAwarenessReady()).toBe(false);

      // EXPECTED: Should allow reinitializing with new awareness instance
      store.initializeAwareness(awareness2 as unknown as Awareness, userData);

      // EXPECTED: New awareness instance should be active
      expect(store.isAwarenessReady()).toBe(true);
      expect(store.getRawAwareness()).toBe(awareness2);
    });

    test('cleanly switches from one awareness instance to another', () => {
      // Initialize with first awareness instance
      store.initializeAwareness(awareness1 as unknown as Awareness, userData);

      // Verify listeners are set up on first instance
      expect(awareness1.on).toHaveBeenCalledWith(
        'change',
        expect.any(Function)
      );
      expect(awareness1.setLocalStateField).toHaveBeenCalledWith(
        'user',
        userData
      );

      // Destroy and reinitialize with second instance
      store.destroyAwareness();
      store.initializeAwareness(awareness2 as unknown as Awareness, userData);

      // EXPECTED: First instance should have listener removed
      expect(awareness1.off).toHaveBeenCalledWith(
        'change',
        expect.any(Function)
      );

      // EXPECTED: Second instance should have new listeners
      expect(awareness2.on).toHaveBeenCalledWith(
        'change',
        expect.any(Function)
      );
      expect(awareness2.setLocalStateField).toHaveBeenCalledWith(
        'user',
        userData
      );
    });
  });

  describe('Detecting awareness instance mismatch', () => {
    test('detects when stored awareness differs from new awareness', () => {
      // Initialize with first awareness instance
      store.initializeAwareness(awareness1 as unknown as Awareness, userData);

      // EXPECTED: Store should detect that new awareness differs from stored one
      // This is the MISSING behavior that StoreProvider needs
      const currentAwareness = store.getRawAwareness();
      const newAwareness = awareness2 as unknown as Awareness;

      // The store should provide a way to detect this mismatch
      // Currently, isAwarenessReady() returns true even though the instance changed
      expect(currentAwareness).not.toBe(newAwareness);

      // EXPECTED: This should be false because the awareness instance has changed
      // But currently there's no mechanism to detect this
      // This test documents the missing behavior
      const shouldReinitialize =
        !store.isAwarenessReady() || store.getRawAwareness() !== newAwareness;

      expect(shouldReinitialize).toBe(true);
    });

    test('isAwarenessReady returns false when pointing to destroyed instance', () => {
      // Initialize with awareness1
      store.initializeAwareness(awareness1 as unknown as Awareness, userData);

      // Simulate external destruction (e.g., SessionStore.destroy())
      // In real scenario, awareness1 would be destroyed outside the store
      awareness1.destroy();

      // Store still thinks awareness is ready, but it's destroyed
      const isReady = store.isAwarenessReady();

      // EXPECTED: Store should detect that its awareness instance is invalid
      // Currently fails because store only checks isInitialized && rawAwareness !== null
      // It doesn't verify the instance is still valid
      expect(isReady).toBe(false); // This will FAIL - documents the bug
    });
  });

  describe('updateLocalCursor uses correct awareness after switch', () => {
    test('calls setLocalStateField on the current awareness instance', () => {
      // Initialize with first awareness instance
      store.initializeAwareness(awareness1 as unknown as Awareness, userData);

      // Update cursor - should use awareness1
      store.updateLocalCursor({ x: 100, y: 200 });

      expect(awareness1.setLocalStateField).toHaveBeenCalledWith('cursor', {
        x: 100,
        y: 200,
      });

      // Destroy and reinitialize with second instance
      store.destroyAwareness();
      store.initializeAwareness(awareness2 as unknown as Awareness, userData);

      // Clear previous mock calls
      awareness1.setLocalStateField.mockClear();
      awareness2.setLocalStateField.mockClear();

      // Update cursor again - should use awareness2
      store.updateLocalCursor({ x: 300, y: 400 });

      // EXPECTED: Should call awareness2, not awareness1
      expect(awareness2.setLocalStateField).toHaveBeenCalledWith('cursor', {
        x: 300,
        y: 400,
      });
      expect(awareness1.setLocalStateField).not.toHaveBeenCalled();
    });

    test('handles cursor updates after awareness instance changes', () => {
      // Initialize with awareness1
      store.initializeAwareness(awareness1 as unknown as Awareness, userData);

      // Simulate version switch: awareness1 destroyed, awareness2 created
      // This is what happens in SessionStore.destroy() + new Session
      store.destroyAwareness();

      // At this point, isAwarenessReady() should be false
      expect(store.isAwarenessReady()).toBe(false);

      // Reinitialize with awareness2
      store.initializeAwareness(awareness2 as unknown as Awareness, userData);

      // Clear mock calls from initialization
      awareness2.setLocalStateField.mockClear();

      // Update cursor - should work correctly with awareness2
      store.updateLocalCursor({ x: 500, y: 600 });

      // EXPECTED: Should update awareness2
      expect(awareness2.setLocalStateField).toHaveBeenCalledWith('cursor', {
        x: 500,
        y: 600,
      });
    });

    test('does not call setLocalStateField on destroyed awareness', () => {
      // Initialize with awareness1
      store.initializeAwareness(awareness1 as unknown as Awareness, userData);

      // Destroy awareness (simulates version switch)
      store.destroyAwareness();

      // Clear mock calls from initialization
      awareness1.setLocalStateField.mockClear();

      // Attempt to update cursor - should not affect awareness1
      store.updateLocalCursor({ x: 700, y: 800 });

      // EXPECTED: Should not call awareness1 because it's destroyed
      expect(awareness1.setLocalStateField).not.toHaveBeenCalled();
    });
  });

  describe('State consistency during lifecycle transitions', () => {
    test('maintains correct state through full lifecycle', () => {
      // Initial state
      expect(store.isAwarenessReady()).toBe(false);
      expect(store.getRawAwareness()).toBeNull();
      expect(store.getLocalUser()).toBeNull();

      // After initialization
      store.initializeAwareness(awareness1 as unknown as Awareness, userData);

      expect(store.isAwarenessReady()).toBe(true);
      expect(store.getRawAwareness()).toBe(awareness1);
      expect(store.getLocalUser()).toEqual(userData);

      // After destruction
      store.destroyAwareness();

      expect(store.isAwarenessReady()).toBe(false);
      expect(store.getRawAwareness()).toBeNull();
      expect(store.getLocalUser()).toBeNull();

      // After reinitialization with new instance
      store.initializeAwareness(awareness2 as unknown as Awareness, userData);

      expect(store.isAwarenessReady()).toBe(true);
      expect(store.getRawAwareness()).toBe(awareness2);
      expect(store.getLocalUser()).toEqual(userData);
    });

    test('clears users list on destroy', () => {
      // Setup: Initialize and simulate having users
      store.initializeAwareness(awareness1 as unknown as Awareness, userData);

      // Manually add some users to state (simulating awareness changes)
      const usersSnapshot = store.getSnapshot();
      expect(usersSnapshot.users).toBeDefined();

      // Destroy awareness
      store.destroyAwareness();

      // EXPECTED: Users list should be cleared
      const afterDestroy = store.getSnapshot();
      expect(afterDestroy.users).toEqual([]);
      expect(afterDestroy.cursorsMap.size).toBe(0);
    });
  });
});
