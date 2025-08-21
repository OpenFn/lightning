import type { LiveSocket } from 'phoenix_live_view';

export {};

declare global {
  interface Window {
    liveSocket?: LiveSocket | undefined;
    triggerReconnect?: ((timeout?: number) => void) | undefined;
    triggerSessionReconnect?: ((timeout?: number) => void) | undefined;
  }
}
