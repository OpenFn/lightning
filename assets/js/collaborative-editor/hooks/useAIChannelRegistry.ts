/**
 * useAIChannelRegistry Hook
 *
 * Provides access to the AI Channel Registry for managing Phoenix Channel connections.
 *
 * ## Usage Pattern
 *
 * ```typescript
 * // In AIAssistantPanelWrapper or component that needs AI channel
 * const { registry } = useAIChannelRegistry();
 * const subscriberId = useId();
 *
 * // Subscribe to channel when needed
 * useEffect(() => {
 *   if (!aiMode || !isOpen) return;
 *
 *   const topic = buildTopic(aiMode.type, sessionId);
 *   registry.subscribe(topic, subscriberId, aiMode.context);
 *
 *   return () => {
 *     registry.unsubscribe(topic, subscriberId);
 *   };
 * }, [aiMode, sessionId, isOpen]);
 *
 * // Send message
 * const handleSendMessage = (content: string, options?: MessageOptions) => {
 *   const topic = buildTopic(aiMode.type, sessionId);
 *   registry.sendMessage(topic, content, options);
 * };
 * ```
 *
 * ## Benefits Over Direct Channel Management
 *
 * 1. **No race conditions** - Multiple channels can coexist during transitions
 * 2. **Fast switching** - Channels reused within 10s window
 * 3. **Simple component code** - Just subscribe/unsubscribe
 * 4. **Centralized state** - All channel state in one place
 */

import { useMemo } from 'react';

import { useSocket } from '../../react/contexts/SocketProvider';
import { AIChannelRegistry } from '../lib/AIChannelRegistry';
import type { SessionType } from '../types/ai-assistant';

import { useAIStore } from './useAIAssistant';

// Module-level singleton registry cache
// Uses WeakMap to allow garbage collection when socket/store are no longer referenced
let registryInstance: AIChannelRegistry | null = null;
let registrySocket: unknown = null;
let registryStore: unknown = null;

/**
 * Get or create the singleton registry instance
 * Returns the same instance as long as socket and store haven't changed
 */
function getOrCreateRegistry(
  socket: unknown,
  store: unknown
): AIChannelRegistry | null {
  if (!socket || !store) {
    return null;
  }

  // Return existing registry if socket and store haven't changed
  if (
    registryInstance &&
    registrySocket === socket &&
    registryStore === store
  ) {
    return registryInstance;
  }

  // Create new registry (socket or store changed)
  // eslint-disable-next-line @typescript-eslint/no-unsafe-argument, @typescript-eslint/no-explicit-any
  registryInstance = new AIChannelRegistry(socket as any, store as any);
  registrySocket = socket;
  registryStore = store;

  return registryInstance;
}

/**
 * Hook to access the AI Channel Registry
 *
 * The registry is a singleton shared across all components.
 * This ensures channels created by useAISession can be accessed by useAISessionCommands.
 */
export const useAIChannelRegistry = () => {
  const { socket } = useSocket();
  const store = useAIStore();

  // Get singleton registry (memoized to avoid unnecessary re-renders)
  const registry = useMemo(() => {
    return getOrCreateRegistry(socket, store);
  }, [socket, store]);

  return { registry };
};

/**
 * Helper to build channel topic from session type and ID
 *
 * @param sessionType - 'job_code' or 'workflow_template'
 * @param sessionId - Session ID or 'new' for new sessions
 * @returns Channel topic string
 */
export const buildChannelTopic = (
  sessionType: SessionType,
  sessionId: string | null
): string => {
  return `ai_assistant:${sessionType}:${sessionId || 'new'}`;
};

/**
 * Hook that provides registry methods for the current AI session
 *
 * This is a convenience hook that automatically builds the topic and provides
 * typed methods for common operations.
 *
 * ## Usage
 *
 * ```typescript
 * const { sendMessage, retryMessage, isConnected } = useAISessionCommands();
 *
 * const handleSend = () => {
 *   sendMessage('Hello AI!', { attach_code: true });
 * };
 * ```
 */
export const useAISessionCommands = () => {
  const { registry } = useAIChannelRegistry();
  const store = useAIStore();

  const state = store?.getSnapshot();
  const sessionType = state?.sessionType;
  const sessionId = state?.sessionId;

  const topic = useMemo(() => {
    if (!sessionType) return null;
    return buildChannelTopic(sessionType, sessionId);
  }, [sessionType, sessionId]);

  const sendMessage = (
    content: string,
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    options?: any
  ) => {
    if (!registry || !topic) {
      console.warn('Cannot send message: registry or topic not available');
      return;
    }
    // eslint-disable-next-line @typescript-eslint/no-unsafe-argument
    registry.sendMessage(topic, content, options);
  };

  const retryMessage = (messageId: string) => {
    if (!registry || !topic) {
      console.warn('Cannot retry message: registry or topic not available');
      return;
    }
    registry.retryMessage(topic, messageId);
  };

  const markDisclaimerRead = () => {
    if (!registry || !topic) {
      console.warn('Cannot mark disclaimer: registry or topic not available');
      return;
    }
    registry.markDisclaimerRead(topic);
  };

  const loadSessions = (offset = 0, limit = 20) => {
    if (!registry || !topic) {
      console.warn('Cannot load sessions: registry or topic not available');
      return Promise.reject(new Error('Registry or topic not available'));
    }
    return registry.loadSessions(topic, offset, limit);
  };

  const updateContext = (context: {
    job_adaptor?: string;
    job_body?: string;
    job_name?: string;
  }) => {
    if (!registry || !topic) {
      console.warn('Cannot update context: registry or topic not available');
      return;
    }
    registry.updateContext(topic, context);
  };

  const isConnected = topic
    ? registry?.getChannelStatus(topic) === 'connected'
    : false;

  return {
    sendMessage,
    retryMessage,
    markDisclaimerRead,
    loadSessions,
    updateContext,
    isConnected,
    topic,
  };
};
