// The design system reads Vite's import.meta.env; esbuild defines these two
// (config/config.exs) and Vitest provides them in tests.
interface ImportMeta {
  readonly env: { readonly DEV: boolean; readonly MODE: string };
}
