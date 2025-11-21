/**
 * Type declarations for tinykeys
 *
 * This is a workaround for tinykeys package.json not properly exposing types
 * through its "exports" field. The library has types at dist/tinykeys.d.ts,
 * but TypeScript can't resolve them due to the exports configuration.
 *
 * See: https://github.com/jamiebuilds/tinykeys/issues/115
 */

declare module 'tinykeys' {
  export interface KeyBindingMap {
    [keybinding: string]: (event: KeyboardEvent) => void;
  }

  export interface KeyBindingOptions {
    /**
     * Key presses will listen to this event (default: "keydown").
     */
    event?: 'keydown' | 'keyup';
    /**
     * Key presses will use a capture listener (default: false)
     */
    capture?: boolean;
    /**
     * Keybinding sequences will wait this long between key presses before
     * cancelling (default: 1000).
     */
    timeout?: number;
  }

  /**
   * Subscribes to keybindings.
   * Returns an unsubscribe method.
   */
  export function tinykeys(
    target: Window | HTMLElement,
    keyBindingMap: KeyBindingMap,
    options?: KeyBindingOptions
  ): () => void;
}
