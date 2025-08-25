/* Minimal types for Phoenix JS client sourced from deps. */

declare module "phoenix" {
  // export class Channel {
  //   on(event: string, callback: (data: unknown) => void): number;
  //   off(event: string, callback: (data: unknown) => void): void;
  // }
  export class Presence {}

  export class Socket {
    constructor(endPoint: string, opts?: Record<string, unknown>);
    connect(params?: Record<string, unknown>): void;
    disconnect(callback?: () => void, code?: number, reason?: string): void;
    isConnected(): boolean;
    onOpen(callback: () => void): number;
    onError(callback: (error: unknown) => void): number;
    onClose(callback: (event?: unknown) => void): number;
  }
}
