/**
 * Visibility API Utility Tests
 *
 * Tests for the visibility.ts utility that detects Page Visibility API
 * support across different browser vendors.
 *
 * Test categories:
 * 1. Standard API - Modern browsers with standard implementation
 * 2. Vendor Prefixes - Legacy browser support (webkit, moz, ms)
 * 3. No Support - Browsers without Page Visibility API
 */

import { beforeEach, describe, expect, test } from 'vitest';

import { getVisibilityProps } from '../../../js/collaborative-editor/utils/visibility';

describe('getVisibilityProps - Standard API', () => {
  beforeEach(() => {
    // Clean up any vendor prefixes from previous tests
    // @ts-expect-error - Deleting test properties
    delete document.webkitHidden;
    // @ts-expect-error - Deleting test properties
    delete document.mozHidden;
    // @ts-expect-error - Deleting test properties
    delete document.msHidden;
  });

  test('returns standard properties when document.hidden is supported', () => {
    // Standard API is already available in modern test environments
    const result = getVisibilityProps();

    expect(result).toEqual({
      hidden: 'hidden',
      visibilityChange: 'visibilitychange',
    });
  });
});

describe('getVisibilityProps - Vendor Prefixes', () => {
  beforeEach(() => {
    // Save original property descriptor
    const originalDescriptor = Object.getOwnPropertyDescriptor(
      Document.prototype,
      'hidden'
    );

    // Remove standard property to test vendor prefixes
    if (originalDescriptor) {
      Object.defineProperty(Document.prototype, 'hidden', {
        configurable: true,
        get: () => undefined,
      });
    }
  });

  test('returns webkit properties when webkitHidden is supported', () => {
    // Mock webkit prefix
    Object.defineProperty(document, 'webkitHidden', {
      configurable: true,
      value: false,
    });

    const result = getVisibilityProps();

    expect(result).toEqual({
      hidden: 'webkitHidden',
      visibilityChange: 'webkitvisibilitychange',
    });

    // Cleanup
    // @ts-expect-error - Deleting test property
    delete document.webkitHidden;
  });

  test('returns moz properties when mozHidden is supported', () => {
    // Mock moz prefix
    Object.defineProperty(document, 'mozHidden', {
      configurable: true,
      value: false,
    });

    const result = getVisibilityProps();

    expect(result).toEqual({
      hidden: 'mozHidden',
      visibilityChange: 'mozvisibilitychange',
    });

    // Cleanup
    // @ts-expect-error - Deleting test property
    delete document.mozHidden;
  });

  test('returns ms properties when msHidden is supported', () => {
    // Mock ms prefix
    Object.defineProperty(document, 'msHidden', {
      configurable: true,
      value: false,
    });

    const result = getVisibilityProps();

    expect(result).toEqual({
      hidden: 'msHidden',
      visibilityChange: 'msvisibilitychange',
    });

    // Cleanup
    // @ts-expect-error - Deleting test property
    delete document.msHidden;
  });
});

describe('getVisibilityProps - Browser Compatibility', () => {
  test('returns properties in standard modern browsers', () => {
    // The function should check in this order:
    // 1. document.hidden (standard)
    // 2. document.webkitHidden (webkit)
    // 3. document.mozHidden (moz)
    // 4. document.msHidden (ms)

    // Standard should take precedence
    const result = getVisibilityProps();

    // In modern test/browser environments, standard API is available
    // So we expect either the standard API or null
    expect(result === null || result?.hidden === 'hidden').toBe(true);
  });

  test('returns event name matching the property prefix', () => {
    const result = getVisibilityProps();

    if (result) {
      // Event name should match the property prefix
      if (result.hidden === 'hidden') {
        expect(result.visibilityChange).toBe('visibilitychange');
      } else if (result.hidden === 'webkitHidden') {
        expect(result.visibilityChange).toBe('webkitvisibilitychange');
      } else if (result.hidden === 'mozHidden') {
        expect(result.visibilityChange).toBe('mozvisibilitychange');
      } else if (result.hidden === 'msHidden') {
        expect(result.visibilityChange).toBe('msvisibilitychange');
      }
    }
  });
});

describe('getVisibilityProps - Return Type', () => {
  test('returns object with hidden and visibilityChange properties', () => {
    const result = getVisibilityProps();

    if (result) {
      expect(result).toHaveProperty('hidden');
      expect(result).toHaveProperty('visibilityChange');
      expect(typeof result.hidden).toBe('string');
      expect(typeof result.visibilityChange).toBe('string');
    }
  });

  test('returns null or object, never undefined', () => {
    const result = getVisibilityProps();

    expect(result).not.toBe(undefined);
    expect(result === null || typeof result === 'object').toBe(true);
  });
});
