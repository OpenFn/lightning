/**
 * Adaptor type definitions and Zod schemas
 *
 * Defines the shape of adaptor data that comes from the Phoenix backend
 * and provides runtime validation with Zod schemas.
 */

import type { PhoenixChannelProvider } from 'y-phoenix-channel';
import { z } from 'zod';

// =============================================================================
// ZOD SCHEMAS (Runtime Validation)
// =============================================================================

/**
 * Individual adaptor version schema
 */
export const AdaptorVersionSchema = z.object({
  version: z.string(),
});

/**
 * Single adaptor schema with all its versions
 */
export const AdaptorSchema = z.object({
  name: z.string(),
  versions: z.array(AdaptorVersionSchema),
  repo: z.string(),
  latest: z.string(),
});

/**
 * Complete adaptors list from the backend
 */
export const AdaptorsListSchema = z.array(AdaptorSchema);

// =============================================================================
// TYPESCRIPT TYPES (Compile-time)
// =============================================================================

/**
 * Individual adaptor version
 */
export type AdaptorVersion = z.infer<typeof AdaptorVersionSchema>;

/**
 * Single adaptor with all its versions and metadata
 */
export type Adaptor = z.infer<typeof AdaptorSchema>;

/**
 * Array of all available adaptors
 */
export type AdaptorsList = z.infer<typeof AdaptorsListSchema>;

/**
 * Adaptor store state interface
 */
export interface AdaptorState {
  /** Current list of available adaptors */
  adaptors: AdaptorsList;

  /** Project-specific adaptors used across workflows */
  projectAdaptors: AdaptorsList;

  /** Loading state for initial fetch */
  isLoading: boolean;

  /** Error state if adaptor loading fails */
  error: string | null;

  /** Timestamp of last successful load */
  lastUpdated: number | null;
}

/**
 * Adaptor store command interface (CQS pattern - Commands)
 */
export interface AdaptorCommands {
  /** Request adaptors list from server */
  requestAdaptors: () => Promise<void>;

  /** Request project-specific adaptors from server */
  requestProjectAdaptors: () => Promise<void>;

  /** Manually set adaptors (for testing/fallback) */
  setAdaptors: (adaptors: AdaptorsList) => void;

  /** Set loading state */
  setLoading: (loading: boolean) => void;

  /** Set error state */
  setError: (error: string | null) => void;

  /** Clear error state */
  clearError: () => void;
}

/**
 * Adaptor store query interface (CQS pattern - Queries)
 */
export interface AdaptorQueries {
  /** Get current adaptor state snapshot */
  getSnapshot: () => AdaptorState;

  /** Subscribe to state changes */
  subscribe: (listener: () => void) => () => void;

  /** Create memoized selector for referential stability */
  withSelector: <T>(selector: (state: AdaptorState) => T) => () => T;

  /** Find adaptor by name */
  findAdaptorByName: (name: string) => Adaptor | null;

  /** Get latest version for adaptor */
  getLatestVersion: (adaptorName: string) => string | null;

  /** Get all versions for adaptor */
  getVersions: (adaptorName: string) => AdaptorVersion[];
}

/**
 * Internal methods interface (not part of public API)
 */
export interface AdaptorInternals {
  _connectChannel: (provider: PhoenixChannelProvider) => () => void;
}

/**
 * Complete adaptor store interface combining commands and queries
 */
export type AdaptorStore = AdaptorCommands & AdaptorQueries & AdaptorInternals;
