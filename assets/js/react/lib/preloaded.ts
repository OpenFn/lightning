import type { Root } from 'react-dom/client';

/**
 * Components whose module was loaded with the page, so the `ReactComponent`
 * hook can render them synchronously when it mounts instead of importing
 * them lazily and drawing a fallback first. A module may also render into
 * its container before the LiveView joins; the hook adopts that root.
 */
const registry = new Map<string, React.ComponentType<object>>();
const roots = new Map<Element, Root>();
const claimed = new WeakSet<Element>();

export const registerComponent = (
  name: string,
  component: React.ComponentType<object>
) => {
  registry.set(name, component);
};

export const preloadedComponent = (name: string) => registry.get(name);

/** Marks a container as the hook's, so a module loading later leaves it alone. */
export const claimContainer = (el: Element) => {
  claimed.add(el);
};

export const isClaimed = (el: Element) => claimed.has(el);

/** Remembers a root rendered into `el` before the hook mounted. */
export const keepPrerenderedRoot = (el: Element, root: Root) => {
  roots.set(el, root);
};

/** Hands a prerendered root to the hook, once. */
export const adoptPrerenderedRoot = (el: Element) => {
  const root = roots.get(el);
  roots.delete(el);
  return root;
};
