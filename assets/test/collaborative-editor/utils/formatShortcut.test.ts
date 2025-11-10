import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { formatShortcut } from '#/collaborative-editor/utils/formatShortcut';

describe('formatShortcut', () => {
  let originalNavigator: Navigator;

  beforeEach(() => {
    // Save original navigator
    originalNavigator = global.navigator;
  });

  afterEach(() => {
    // Restore original navigator
    Object.defineProperty(global, 'navigator', {
      value: originalNavigator,
      configurable: true,
      writable: true,
    });
  });

  describe('macOS platform', () => {
    beforeEach(() => {
      // Mock macOS platform
      Object.defineProperty(global, 'navigator', {
        value: { platform: 'MacIntel' },
        configurable: true,
        writable: true,
      });
    });

    it('displays ⌘ symbol for mod key', () => {
      expect(formatShortcut(['mod', 's'])).toBe('⌘ + S');
    });

    it('displays Shift as text', () => {
      expect(formatShortcut(['mod', 'shift', 's'])).toBe('⌘ + Shift + S');
    });

    it('displays Enter as text', () => {
      expect(formatShortcut(['mod', 'enter'])).toBe('⌘ + Enter');
    });

    it('displays Escape as text', () => {
      expect(formatShortcut(['escape'])).toBe('Escape');
    });
  });

  describe('Windows platform', () => {
    beforeEach(() => {
      // Mock Windows platform
      Object.defineProperty(global, 'navigator', {
        value: { platform: 'Win32' },
        configurable: true,
        writable: true,
      });
    });

    it('displays Ctrl text for mod key', () => {
      expect(formatShortcut(['mod', 's'])).toBe('Ctrl + S');
    });

    it('displays Shift as text', () => {
      expect(formatShortcut(['mod', 'shift', 's'])).toBe('Ctrl + Shift + S');
    });

    it('displays Enter as text', () => {
      expect(formatShortcut(['mod', 'enter'])).toBe('Ctrl + Enter');
    });
  });

  describe('Linux platform', () => {
    beforeEach(() => {
      // Mock Linux platform
      Object.defineProperty(global, 'navigator', {
        value: { platform: 'Linux x86_64' },
        configurable: true,
        writable: true,
      });
    });

    it('displays Ctrl text for mod key', () => {
      expect(formatShortcut(['mod', 's'])).toBe('Ctrl + S');
    });
  });

  describe('key formatting', () => {
    beforeEach(() => {
      // Use Mac for consistency
      Object.defineProperty(global, 'navigator', {
        value: { platform: 'MacIntel' },
        configurable: true,
        writable: true,
      });
    });

    it('capitalizes single letter keys', () => {
      const result = formatShortcut(['mod', 's']);
      expect(result).toContain('S');
      expect(result).not.toContain('s');
    });

    it('handles multiple keys with + separator', () => {
      const result = formatShortcut(['mod', 'shift', 's']);
      expect(result).toBe('⌘ + Shift + S');
    });

    it('handles single key without separator', () => {
      expect(formatShortcut(['escape'])).toBe('Escape');
    });

    it('handles empty array', () => {
      expect(formatShortcut([])).toBe('');
    });
  });

  describe('iPad/iPhone detection', () => {
    it('treats iPad as macOS', () => {
      Object.defineProperty(global, 'navigator', {
        value: { platform: 'iPad' },
        configurable: true,
        writable: true,
      });

      expect(formatShortcut(['mod', 's'])).toBe('⌘ + S');
    });

    it('treats iPhone as macOS', () => {
      Object.defineProperty(global, 'navigator', {
        value: { platform: 'iPhone' },
        configurable: true,
        writable: true,
      });

      expect(formatShortcut(['mod', 's'])).toBe('⌘ + S');
    });
  });
});
