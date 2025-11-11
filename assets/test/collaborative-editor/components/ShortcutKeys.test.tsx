import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { render, screen } from '@testing-library/react';
import { ShortcutKeys } from '#/collaborative-editor/components/ShortcutKeys';

describe('ShortcutKeys', () => {
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
      render(
        <div data-testid="shortcut">
          <ShortcutKeys keys={['mod', 's']} />
        </div>
      );

      const kbdElements = document.querySelectorAll('kbd');
      const kbdTexts = Array.from(kbdElements).map(el => el.textContent);

      expect(kbdTexts).toEqual(['⌘', 'S']);
    });

    it('displays Shift as text', () => {
      render(
        <div data-testid="shortcut">
          <ShortcutKeys keys={['mod', 'shift', 's']} />
        </div>
      );

      const kbdElements = document.querySelectorAll('kbd');
      const kbdTexts = Array.from(kbdElements).map(el => el.textContent);

      expect(kbdTexts).toEqual(['⌘', 'Shift', 'S']);
    });

    it('displays Enter as text', () => {
      render(
        <div data-testid="shortcut">
          <ShortcutKeys keys={['mod', 'enter']} />
        </div>
      );

      const kbdElements = document.querySelectorAll('kbd');
      const kbdTexts = Array.from(kbdElements).map(el => el.textContent);

      expect(kbdTexts).toEqual(['⌘', 'Enter']);
    });

    it('displays Escape as text', () => {
      render(
        <div data-testid="shortcut">
          <ShortcutKeys keys={['escape']} />
        </div>
      );

      const kbd = document.querySelector('kbd');
      expect(kbd?.textContent).toBe('Escape');
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
      render(
        <div data-testid="shortcut">
          <ShortcutKeys keys={['mod', 's']} />
        </div>
      );

      const kbdElements = document.querySelectorAll('kbd');
      const kbdTexts = Array.from(kbdElements).map(el => el.textContent);

      expect(kbdTexts).toEqual(['Ctrl', 'S']);
    });

    it('displays Shift as text', () => {
      render(
        <div data-testid="shortcut">
          <ShortcutKeys keys={['mod', 'shift', 's']} />
        </div>
      );

      const kbdElements = document.querySelectorAll('kbd');
      const kbdTexts = Array.from(kbdElements).map(el => el.textContent);

      expect(kbdTexts).toEqual(['Ctrl', 'Shift', 'S']);
    });

    it('displays Enter as text', () => {
      render(
        <div data-testid="shortcut">
          <ShortcutKeys keys={['mod', 'enter']} />
        </div>
      );

      const kbdElements = document.querySelectorAll('kbd');
      const kbdTexts = Array.from(kbdElements).map(el => el.textContent);

      expect(kbdTexts).toEqual(['Ctrl', 'Enter']);
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
      render(
        <div data-testid="shortcut">
          <ShortcutKeys keys={['mod', 's']} />
        </div>
      );

      const kbdElements = document.querySelectorAll('kbd');
      const kbdTexts = Array.from(kbdElements).map(el => el.textContent);

      expect(kbdTexts).toEqual(['Ctrl', 'S']);
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
      render(
        <div data-testid="shortcut">
          <ShortcutKeys keys={['mod', 's']} />
        </div>
      );

      const kbdElements = document.querySelectorAll('kbd');
      const kbdTexts = Array.from(kbdElements).map(el => el.textContent);

      expect(kbdTexts[1]).toBe('S');
      expect(kbdTexts[1]).not.toBe('s');
    });

    it('handles multiple keys with space separator', () => {
      render(
        <div data-testid="shortcut">
          <ShortcutKeys keys={['mod', 'shift', 's']} />
        </div>
      );

      const container = screen.getByTestId('shortcut');
      expect(container.textContent).toBe('⌘ Shift S');

      const kbdElements = document.querySelectorAll('kbd');
      expect(kbdElements).toHaveLength(3);
    });

    it('handles single key', () => {
      render(
        <div data-testid="shortcut">
          <ShortcutKeys keys={['escape']} />
        </div>
      );

      const container = screen.getByTestId('shortcut');
      expect(container.textContent).toBe('Escape');
    });

    it('handles empty array', () => {
      render(
        <div data-testid="shortcut">
          <ShortcutKeys keys={[]} />
        </div>
      );

      const kbdElements = document.querySelectorAll('kbd');
      expect(kbdElements).toHaveLength(0);
    });
  });

  describe('iPad/iPhone detection', () => {
    it('treats iPad as macOS', () => {
      Object.defineProperty(global, 'navigator', {
        value: { platform: 'iPad' },
        configurable: true,
        writable: true,
      });

      render(
        <div data-testid="shortcut">
          <ShortcutKeys keys={['mod', 's']} />
        </div>
      );

      const kbdElements = document.querySelectorAll('kbd');
      const kbdTexts = Array.from(kbdElements).map(el => el.textContent);

      expect(kbdTexts).toEqual(['⌘', 'S']);
    });

    it('treats iPhone as macOS', () => {
      Object.defineProperty(global, 'navigator', {
        value: { platform: 'iPhone' },
        configurable: true,
        writable: true,
      });

      render(
        <div data-testid="shortcut">
          <ShortcutKeys keys={['mod', 's']} />
        </div>
      );

      const kbdElements = document.querySelectorAll('kbd');
      const kbdTexts = Array.from(kbdElements).map(el => el.textContent);

      expect(kbdTexts).toEqual(['⌘', 'S']);
    });
  });

  describe('kbd element styling', () => {
    beforeEach(() => {
      Object.defineProperty(global, 'navigator', {
        value: { platform: 'MacIntel' },
        configurable: true,
        writable: true,
      });
    });

    it('applies correct Tailwind classes to kbd elements', () => {
      render(
        <div data-testid="shortcut">
          <ShortcutKeys keys={['mod', 's']} />
        </div>
      );

      const kbdElements = document.querySelectorAll('kbd');
      kbdElements.forEach(kbd => {
        expect(kbd.className).toContain('rounded');
        expect(kbd.className).toContain('border');
        expect(kbd.className).toContain('bg-gray-800');
        expect(kbd.className).toContain('text-gray-200');
      });
    });
  });
});
