import type { PhoenixChannelProvider } from 'y-phoenix-channel';
import * as z from 'zod';

import { isoDateTimeSchema, uuidSchema } from './common';

export const CredentialOwnerSchema = z.object({
  id: uuidSchema,
  name: z.string(),
  email: z.string(),
});

export const CredentialSchema = z.object({
  id: uuidSchema,
  project_credential_id: uuidSchema,
  name: z.string(),
  external_id: z.string().nullable(),
  schema: z.string(),
  owner: CredentialOwnerSchema.nullable(),
  oauth_client_name: z.string().nullable(),
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

// Discriminated union types for credentials with type metadata
export type ProjectCredentialWithType = ProjectCredential & {
  type: 'project';
};

export type KeychainCredentialWithType = KeychainCredential & {
  type: 'keychain';
};

export type CredentialWithType =
  | ProjectCredentialWithType
  | KeychainCredentialWithType;

export interface CredentialState {
  projectCredentials: ProjectCredential[];
  keychainCredentials: KeychainCredential[];
  isLoading: boolean;
  error: string | null;
  lastUpdated: number | null;
}

interface CredentialCommands {
  requestCredentials: () => Promise<void>;
  setLoading: (loading: boolean) => void;
  setError: (error: string | null) => void;
  clearError: () => void;
}

interface CredentialQueries {
  getSnapshot: () => CredentialState;

  subscribe: (listener: () => void) => () => void;
  withSelector: <T>(selector: (state: CredentialState) => T) => () => T;

  // Credential lookup queries
  findCredentialById: (searchId: string | null) => CredentialWithType | null;
  credentialExists: (searchId: string | null) => boolean;
  getCredentialId: (cred: ProjectCredential | KeychainCredential) => string;
}

interface CredentialStoreInternals {
  _connectChannel: (provider: PhoenixChannelProvider) => () => void;
}

export type CredentialStore = CredentialQueries &
  CredentialCommands &
  CredentialStoreInternals;
