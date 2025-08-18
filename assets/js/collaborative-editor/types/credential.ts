import type { PhoenixChannelProvider } from "y-phoenix-channel";
import * as z from "zod";

import { isoDateTimeSchema, uuidSchema } from "./common";

export const CredentialSchema = z.object({
  id: uuidSchema,
  project_credential_id: uuidSchema,
  name: z.string(),
  external_id: z.string(),
  production: z.boolean(),
  schema: z.string(),
  inserted_at: isoDateTimeSchema,
  updated_at: isoDateTimeSchema,
});

export const KeychainCredentialSchema = z.object({
  id: uuidSchema,
  name: z.string(),
  path: z.string(),
  default_credential_id: uuidSchema.nullable(),
  inserted_at: isoDateTimeSchema,
  updated_at: isoDateTimeSchema,
});

export const CredentialsListSchema = z.object({
  project_credentials: z.array(CredentialSchema),
  keychain_credentials: z.array(KeychainCredentialSchema),
});

export type ProjectCredential = z.infer<typeof CredentialSchema>;
export type KeychainCredential = z.infer<typeof KeychainCredentialSchema>;

export interface CredentialState {
  projectCredentials: ProjectCredential[];
  keychainCredentials: KeychainCredential[];
  isLoading: boolean;
  error: string | null;
  lastUpdated: number | null;
}

interface CredentialCommands {
  requestCredentials: () => void;
  setLoading: (loading: boolean) => void;
  setError: (error: string | null) => void;
  clearError: () => void;
}

interface CredentialQueries {
  getSnapshot: () => CredentialState;

  subscribe: (listener: () => void) => () => void;
  withSelector: <T>(selector: (state: CredentialState) => T) => () => T;
}

interface CredentialStoreInternals {
  _connectChannel: (provider: PhoenixChannelProvider) => () => void;
  _handleCredentialsReceived: (rawData: unknown) => void;
  _handleCredentialsUpdated: (rawData: unknown) => void;
}

export type CredentialStore = CredentialQueries &
  CredentialCommands &
  CredentialStoreInternals;
