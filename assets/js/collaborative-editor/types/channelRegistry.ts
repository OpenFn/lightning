import type { Socket } from 'phoenix';
import type { PhoenixChannelProvider } from 'y-phoenix-channel';
import type { Awareness } from 'y-protocols/awareness';
import type { Doc as YDoc } from 'yjs';

/**
 * State machine for channel lifecycle during version transitions
 *
 * Flow:
 * - connecting: Provider created, joining channel
 * - settling: Joined, waiting for sync + first Y.Doc update
 * - active: Fully synced, primary channel
 * - draining: Superseded, awaiting cleanup
 * - destroyed: Resources released
 */
export type ChannelState =
  | 'connecting'
  | 'settling'
  | 'active'
  | 'draining'
  | 'destroyed';

/**
 * Entry tracking a single channel connection with its Y.Doc, Provider, and
 * Awareness instances
 */
export interface ChannelEntry {
  roomname: string;
  ydoc: YDoc;
  provider: PhoenixChannelProvider;
  awareness: Awareness;
  state: ChannelState;
  createdAt: number;
  settledAt: number | null;
}

/**
 * Registry managing concurrent channel connections during version transitions
 *
 * During a version switch, the registry:
 * 1. Creates new entry in `connecting` state
 * 2. Marks old entry as `draining`
 * 3. New entry progresses: `connecting` → `settling` → `active`
 * 4. Once new entry is `active`, starts drain timer on old entry
 * 5. After grace period, destroys draining entry
 *
 * This prevents flickering by keeping both channels alive during transition.
 */
export interface ChannelRegistry {
  /**
   * Migrate to a new channel, starting transition from current to new
   *
   * @param socket - Phoenix Socket instance
   * @param newRoomname - Target channel/version roomname
   * @param joinParams - Parameters for channel join
   * @returns Promise that resolves when new channel is active
   */
  migrate(
    socket: Socket,
    newRoomname: string,
    joinParams: object
  ): Promise<void>;

  /**
   * Get the current active channel entry
   *
   * @returns Current entry or null if no active channel
   */
  getCurrentEntry(): ChannelEntry | null;

  /**
   * Get the draining channel entry if one exists
   *
   * @returns Draining entry or null if no draining channel
   */
  getDrainingEntry(): ChannelEntry | null;

  /**
   * Check if registry is in transition state
   *
   * @returns True if there is a draining entry
   */
  isTransitioning(): boolean;

  /**
   * Subscribe to registry state changes
   *
   * @param callback - Called when registry state changes
   * @returns Unsubscribe function
   */
  subscribe(callback: () => void): () => void;

  /**
   * Destroy the registry and all managed resources
   */
  destroy(): void;
}
