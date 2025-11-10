/**
 * Formats keyboard shortcut keys as a display string with platform-specific notation.
 *
 * On macOS: "mod" becomes "⌘", other platforms: "Ctrl"
 * All other keys are capitalized text (Shift, Enter, Esc, etc.)
 *
 * @param keys - Array of key names (e.g., ["mod", "s"] or ["mod", "shift", "enter"])
 * @returns Formatted shortcut string (e.g., "⌘ + S" or "Ctrl + Shift + Enter")
 *
 * @example
 * formatShortcut(["mod", "s"]) // "⌘ + S" on Mac, "Ctrl + S" elsewhere
 * formatShortcut(["mod", "shift", "s"]) // "⌘ + Shift + S" on Mac
 * formatShortcut(["escape"]) // "Escape"
 */
export function formatShortcut(keys: string[]): string {
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

  return keys.map(displayKey).join(' + ');
}
