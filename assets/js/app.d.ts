import type { LiveSocket } from 'phoenix_live_view';

export {};

declare global {
  interface Window {
    liveSocket?: LiveSocket | undefined;
    triggerReconnect?: ((timeout?: number | undefined) => void) | undefined;
  }
}
