/**
 * Components whose module was loaded with the page, so the `ReactComponent`
 * hook can render them synchronously when it mounts instead of importing
 * them lazily and drawing a fallback first.
 */
const registry = new Map<string, React.ComponentType<object>>();

export const registerComponent = (
  name: string,
  component: React.ComponentType<object>
) => {
  registry.set(name, component);
};

export const preloadedComponent = (name: string) => registry.get(name);
