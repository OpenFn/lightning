import type { PhoenixChannelProvider } from "y-phoenix-channel";
import * as z from "zod";

import { isoDateTimeSchema, uuidSchema } from "./common";

export const UserContextSchema = z.object({
  id: uuidSchema,
  first_name: z.string(),
  last_name: z.string(),
  email: z.string().email(),
  email_confirmed: z.boolean(),
  inserted_at: isoDateTimeSchema,
});

export const ProjectContextSchema = z.object({
  id: uuidSchema,
  name: z.string(),
});

export const AppConfigSchema = z.object({
  require_email_verification: z.boolean(),
});

export const SessionContextResponseSchema = z.object({
  user: UserContextSchema.nullable(),
  project: ProjectContextSchema.nullable(),
  config: AppConfigSchema,
});

export type UserContext = z.infer<typeof UserContextSchema>;
export type ProjectContext = z.infer<typeof ProjectContextSchema>;
export type AppConfig = z.infer<typeof AppConfigSchema>;

export interface SessionContextState {
  user: UserContext | null;
  project: ProjectContext | null;
  config: AppConfig | null;
  isLoading: boolean;
  error: string | null;
  lastUpdated: number | null;
}

interface SessionContextCommands {
  requestSessionContext: () => Promise<void>;
  setLoading: (loading: boolean) => void;
  setError: (error: string | null) => void;
  clearError: () => void;
}

interface SessionContextQueries {
  getSnapshot: () => SessionContextState;

  subscribe: (listener: () => void) => () => void;
  withSelector: <T>(selector: (state: SessionContextState) => T) => () => T;
}

interface SessionContextStoreInternals {
  _connectChannel: (provider: PhoenixChannelProvider) => () => void;
}

export type SessionContextStore = SessionContextQueries &
  SessionContextCommands &
  SessionContextStoreInternals;
