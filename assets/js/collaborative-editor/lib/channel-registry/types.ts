/**
 * Channel Registry Types
 *
 * Core interfaces for the unified channel registry pattern that combines:
 * 1. Reference counting - Multiple components subscribing to same topic
 * 2. State machine - connecting → settling → active → draining → destroyed
 * 3. Pluggable resources - ResourceManager<T> for Y.Doc/Awareness/etc.
 */

import type { Channel as PhoenixChannel } from 'phoenix';

/**
 * Channel lifecycle states during registration and cleanup
 *
 * Valid transitions:
 * - connecting → settling (if resourceManager has waitForSettled)
 * - connecting → active (if no settling needed)
 * - connecting → destroyed (on error or immediate cleanup)
 * - settling → active (settling complete)
 * - settling → destroyed (timeout or abort)
 * - active → draining (new channel supersedes)
 * - active → destroyed (immediate cleanup)
 * - draining → destroyed (grace period elapsed)
 */
export type ChannelState =
  | 'connecting' // Channel joining in progress
  | 'settling' // Joined, waiting for readiness criteria (optional)
  | 'active' // Fully operational
  | 'draining' // Superseded, awaiting cleanup
  | 'destroyed'; // Resources released

/**
 * Entry tracking a single channel with its resources and lifecycle
 */
export interface ChannelEntry<TResources> {
  /** Channel topic identifier */
  topic: string;

  /** Current lifecycle state */
  state: ChannelState;

  /** Component IDs subscribed to this channel (from React.useId()) */
  subscribers: Set<string>;

  /** Phoenix Channel instance */
  channel: PhoenixChannel;

  /** Managed resources (Y.Doc, Awareness, etc.) or null if none */
  resources: TResources | null;

  /** Timer for delayed cleanup in draining state */
  cleanupTimer: NodeJS.Timeout | null;

  /** AbortController for settling phase */
  settlingAbortController: AbortController | null;

  /** Error message if channel failed */
  error: string | null;
}

/**
 * Resource manager interface for pluggable resource types
 *
 * Implementations can manage Y.Doc/Awareness, AI assistant state,
 * or any other channel-specific resources.
 */
export interface ResourceManager<TResources> {
  /**
   * Create resources for a channel
   *
   * @param channel - Phoenix Channel instance
   * @returns Created resources
   */
  create(channel: PhoenixChannel): TResources;

  /**
   * Destroy resources when channel is cleaned up
   *
   * @param resources - Resources to destroy
   */
  destroy(resources: TResources): void;

  /**
   * Wait for resources to be ready (optional settling phase)
   *
   * If provided, the channel will enter 'settling' state after joining
   * and wait for this promise to resolve before becoming 'active'.
   *
   * @param resources - Resources to wait for
   * @param abortSignal - Signal to abort waiting
   * @returns Promise that resolves when resources are ready
   */
  waitForSettled?(
    resources: TResources,
    abortSignal: AbortSignal
  ): Promise<void>;
}

/**
 * Configuration for channel registry behavior
 */
export interface ChannelRegistryConfig<TResources, TContext> {
  /** Name for logging purposes */
  name: string;

  /** Cleanup delay in milliseconds (default: 2000ms) */
  cleanupDelayMs?: number;

  /** Settling timeout in milliseconds (default: 10000ms) */
  settlingTimeoutMs?: number;

  // Callbacks for store integration

  /**
   * Called when channel state changes
   *
   * @param topic - Channel topic
   * @param state - New state
   * @param entry - Channel entry
   */
  onStateChange?: (
    topic: string,
    state: ChannelState,
    entry: ChannelEntry<TResources>
  ) => void;

  /**
   * Called when channel join succeeds
   *
   * @param topic - Channel topic
   * @param response - Join response from server
   * @param entry - Channel entry
   */
  onJoinSuccess?: (
    topic: string,
    response: unknown,
    entry: ChannelEntry<TResources>
  ) => void;

  /**
   * Called when channel join fails
   *
   * @param topic - Channel topic
   * @param error - Error from join attempt
   * @param entry - Channel entry
   */
  onJoinError?: (
    topic: string,
    error: unknown,
    entry: ChannelEntry<TResources>
  ) => void;

  /**
   * Called when channel receives a message
   *
   * @param topic - Channel topic
   * @param event - Event name
   * @param payload - Message payload
   */
  onMessage?: (topic: string, event: string, payload: unknown) => void;

  /**
   * Build join parameters from context
   *
   * @param context - Context object for building params
   * @returns Join parameters object
   */
  buildJoinParams?: (context: TContext) => Record<string, unknown>;

  /**
   * Setup event handlers for the channel
   *
   * Called after channel is created but before joining.
   * Should attach event handlers and return a cleanup function.
   *
   * @param channel - Phoenix Channel instance
   * @param topic - Channel topic
   * @returns Cleanup function that removes event handlers
   */
  setupEventHandlers?: (channel: PhoenixChannel, topic: string) => () => void;
}
