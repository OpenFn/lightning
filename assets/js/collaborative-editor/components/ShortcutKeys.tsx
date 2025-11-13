/**
 * ShortcutKeys - Displays keyboard shortcut keys with platform-specific notation
 *
 * On macOS: "mod" becomes "⌘", other platforms: "Ctrl"
 * All other keys are capitalized text (Shift, Enter, Esc, etc.)
 * Keys are separated by a "+" symbol with spacing.
 * Each key is wrapped in a <kbd> element for semantic HTML.
 *
 * @example
 * <ShortcutKeys keys={['mod', 's']} /> // ⌘ + S on Mac, Ctrl + S elsewhere
 * <ShortcutKeys keys={['mod', 'shift', 'enter']} /> // ⌘ + Shift + Enter on Mac
 */
export function ShortcutKeys({ keys }: { keys: string[] }) {
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
          {index > 0 && <span className="mx-2">+</span>}
          <kbd>{displayKey(key)}</kbd>
        </span>
      ))}
    </>
  );
}
