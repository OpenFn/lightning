/**
 * Global constants defined by esbuild at build time.
 *
 * ENABLE_DEVTOOLS is set via --define flag in config/config.exs:
 * - true in :dev and :test environments
 * - false in :prod environment
 */
declare const ENABLE_DEVTOOLS: boolean;
