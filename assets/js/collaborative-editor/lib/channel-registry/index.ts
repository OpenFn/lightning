/**
 * Channel Registry Infrastructure
 *
 * Unified channel registry pattern combining:
 * - Reference counting for multiple subscribers
 * - State machine for channel lifecycle
 * - Pluggable resource managers
 *
 * This infrastructure is used by stores (SessionStore, AIAssistantStore)
 * to manage Phoenix channel connections.
 */

export * from './types';
export * from './helpers';
export * from './resourceManagers';
