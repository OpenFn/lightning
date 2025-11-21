import type { Awareness } from 'y-protocols/awareness';
import type { RelativePosition } from 'yjs';
import { z } from 'zod';

import type { WithSelector } from '../stores/common';

/**
 * User information stored in awareness
 */
export interface AwarenessUser {
  clientId: number;
  user: {
    id: string;
    name: string;
    email: string;
    color: string;
  };
  cursor?: {
    x: number;
    y: number;
  };
  selection?: {
    anchor: RelativePosition;
    head: RelativePosition;
  };
  lastSeen?: number;
  connectionCount?: number;
}

/**
 * Local user data for awareness
 */
export interface LocalUserData {
  id: string;
  name: string;
  email: string;
  color: string;
}

/**
 * Awareness store state
 */
export interface AwarenessState {
  // Core awareness data
  users: AwarenessUser[];
  localUser: LocalUserData | null;
  isInitialized: boolean;

  // Map of user cursors keyed by clientId
  cursorsMap: Map<number, AwarenessUser>;

  // Raw awareness access (for components that need it)
  rawAwareness: Awareness | null;

  // Connection state
  isConnected: boolean;
  lastUpdated: number | null;
}

/**
 * Zod schema for validating awareness user data
 */
export const AwarenessUserDataSchema = z.object({
  id: z.string(),
  name: z.string(),
  email: z.email(),
  color: z.string(),
});

/**
 * Commands for updating awareness state
 */
export interface AwarenessCommands {
  // Initialization
  initializeAwareness: (awareness: Awareness, userData: LocalUserData) => void;
  destroyAwareness: () => void;

  // Local user updates
  updateLocalUserData: (userData: Partial<LocalUserData>) => void;
  updateLocalCursor: (cursor: { x: number; y: number } | null) => void;
  updateLocalSelection: (selection: AwarenessUser['selection'] | null) => void;
  updateLastSeen: () => void;

  // Connection state
  setConnected: (isConnected: boolean) => void;
}

/**
 * Queries for accessing awareness state
 */
export interface AwarenessQueries {
  // User queries
  getAllUsers: () => AwarenessUser[];
  getRemoteUsers: () => AwarenessUser[];
  getLocalUser: () => LocalUserData | null;
  getUserById: (userId: string) => AwarenessUser | null;
  getUserByClientId: (clientId: number) => AwarenessUser | null;

  // Connection queries
  isAwarenessReady: () => boolean;
  getConnectionState: () => boolean;

  // Raw awareness access
  getRawAwareness: () => Awareness | null;
}

/**
 * Complete awareness store interface following CQS pattern
 */
export interface AwarenessStore extends AwarenessCommands, AwarenessQueries {
  // Core store interface
  subscribe: (listener: () => void) => () => void;
  getSnapshot: () => AwarenessState;
  withSelector: WithSelector<AwarenessState>;

  // Internal methods (for SessionProvider integration)
  _internal: {
    handleAwarenessChange: () => void;
    setupLastSeenTimer: () => () => void;
  };
}
