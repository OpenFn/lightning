import type { ReactNode } from 'react';

/**
 * Formats keyboard shortcut keys as JSX with <kbd> elements and platform-specific notation.
 *
 * On macOS: "mod" becomes "⌘", other platforms: "Ctrl"
 * All other keys are capitalized text (Shift, Enter, Esc, etc.)
 * Each key is wrapped in a <kbd> element for semantic HTML.
 *
 * @param keys - Array of key names (e.g., ["mod", "s"] or ["mod", "shift", "enter"])
 * @returns JSX with <kbd> elements (e.g., <kbd>⌘</kbd> <kbd>S</kbd>)
 *
 * @example
 * formatShortcut(["mod", "s"]) // <kbd>⌘</kbd> <kbd>S</kbd> on Mac
 * formatShortcut(["mod", "shift", "s"]) // <kbd>⌘</kbd> <kbd>Shift</kbd> <kbd>S</kbd>
 * formatShortcut(["escape"]) // <kbd>Escape</kbd>
 */
export function formatShortcut(keys: string[]): ReactNode {
  const isMac =
    typeof navigator !== 'undefined'
      ? /Mac|iPod|iPhone|iPad/.test(navigator.platform)
      : false;

  const displayKey = (key: string): string => {
    // Only "mod" gets special symbol on Mac, everything else is text
    if (key.toLowerCase() === 'mod') {
      return isMac ? '⌘' : 'Ctrl';
    }

    // Capitalize first letter for readability (shift -> Shift, enter -> Enter)
    return key.charAt(0).toUpperCase() + key.slice(1);
  };

  return (
    <>
      {keys.map((key, index) => (
        <span key={index}>
          {index > 0 && ' '}
          <kbd className="rounded border border-gray-600 bg-gray-800 px-1.5 py-0.5 text-xs font-semibold text-gray-200">
            {displayKey(key)}
          </kbd>
        </span>
      ))}
    </>
  );
}
