import type { PhoenixChannelProvider } from 'y-phoenix-channel';
import { z } from 'zod';

// Zod schema for metadata validation
export const MetadataSchema = z.record(z.string(), z.unknown());

export const MetadataResponseSchema = z.object({
  job_id: z.string(),
  metadata: z.union([MetadataSchema, z.object({ error: z.string() })]),
});

export type Metadata = z.infer<typeof MetadataSchema>;
export type MetadataResponse = z.infer<typeof MetadataResponseSchema>;

// Per-job metadata state
export interface JobMetadataState {
  metadata: Metadata | null;
  error: string | null;
  isLoading: boolean;
  lastFetched: number | null;
  // Cache key to detect when to refetch
  cacheKey: string | null; // format: "adaptor:credentialId"
}

// Store state
export interface MetadataState {
  // Map of jobId → metadata state
  jobs: Map<string, JobMetadataState>;
}

// Commands
export interface MetadataCommands {
  requestMetadata: (
    jobId: string,
    adaptor: string,
    credentialId: string | null
  ) => Promise<void>;
  clearMetadata: (jobId: string) => void;
  clearAllMetadata: () => void;
}

// Queries
export interface MetadataQueries {
  getSnapshot: () => MetadataState;
  subscribe: (listener: () => void) => () => void;
  withSelector: <T>(selector: (state: MetadataState) => T) => () => T;
  getMetadataForJob: (jobId: string) => Metadata | null;
  isLoadingForJob: (jobId: string) => boolean;
  getErrorForJob: (jobId: string) => string | null;
}

// Internals
export interface MetadataInternals {
  _connectChannel: (provider: PhoenixChannelProvider) => () => void;
}

export type MetadataStore = MetadataCommands &
  MetadataQueries &
  MetadataInternals;
