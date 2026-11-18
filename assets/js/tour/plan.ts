/**
 * Pure planning logic for the guided tour engine.
 *
 * Given the app map (fetched from /api/app_map) and a tour request (from the
 * `lightning:start-tour` event), work out the sequence of elements the user
 * should click to reach the destination page. No DOM access here — the runner
 * (./runner.ts) owns all side effects.
 */

export type AppMapSection = 'project' | 'user' | 'admin' | 'auth';

export interface AppMapTab {
  hash: string;
  label: string;
  description: string;
}

/** A spotlightable control on a page. The target carries
 * `data-tour-anchor="<id>"` in the DOM. */
export interface AppMapElement {
  id: string;
  label: string;
  description: string;
  /** Instruction for when the element is not currently on screen (e.g. it
   * lives in a panel the user must open first). May be null or absent. */
  hint?: string | null;
  /** Id of another element on the SAME page that must be activated first
   * (e.g. a panel toggle). Chains may nest. */
  requires?: string | null;
}

export interface AppMapPage {
  id: string;
  path: string;
  module: string;
  label: string;
  section: AppMapSection;
  description: string;
  tabs?: AppMapTab[];
  elements?: AppMapElement[];
}

export interface TourRequest {
  page: string;
  tab?: string;
  /** App-map element id to spotlight. Only meaningful when the user is
   * already on the requested page — element requests never navigate. */
  element?: string;
  /** Runner-only: drive the tour automatically (clicks happen for the user).
   * Planning ignores it. */
  autopilot?: boolean;
  params: { project_id?: string };
}

/** A step that spotlights an element and waits for the user to act on it. */
export interface ElementStep {
  type: 'element';
  selector: string;
  title: string;
  body: string;
  /** Short name of what is being activated (page label, tab label, …), used
   * by autopilot's "Opening: {label}" card phrasing. */
  label?: string;
  /** 'click' → advance when the element is clicked; 'hash:<h>' → advance when
   * the URL hash becomes #<h> (covers clicking the tab link too). */
  advanceOn: 'click' | `hash:${string}`;
  /** True when acting on the element triggers a (live or full) navigation, so
   * the runner should persist and resume on the next page. */
  expectNavigation: boolean;
}

/** An automatic hop the runner performs itself (no known element to click). */
export interface NavigateStep {
  type: 'navigate';
  path: string;
}

export type Step = ElementStep | NavigateStep;

/** What the arrival card shows once the destination is reached. */
export interface Arrival {
  label: string;
  description: string;
  tabLabel?: string;
}

/** One spotlightable element, resolved for the runner: the anchor selector
 * and the card copy, plus the not-on-screen hint when the app map has one. */
export interface SpotlightElement {
  selector: string;
  label: string;
  description: string;
  hint?: string;
}

/** What the runner highlights for an element request: the prerequisite
 * elements to activate first (outermost first, often empty) and the final
 * target. The runner skips prerequisites whose anchors are already on
 * screen. */
export interface Spotlight {
  chain: SpotlightElement[];
  target: SpotlightElement;
}

export type TourPlan =
  | {
      steps: Step[];
      arrival: Arrival;
      destinationPath: string;
      destinationHash?: string;
    }
  | { fallbackPath: string; arrival: Arrival }
  | { alreadyHere: true; arrival: Arrival }
  | { wrongPage: true; pageLabel: string }
  | { spotlight: Spotlight }
  | { error: string };

export interface TourPlanOptions {
  /** The current window.location.pathname, used to recognise "you're already
   * on that page" when the destination has params we cannot fill in. */
  currentPath?: string;
}

/**
 * The project-section pages that have a direct link in the sidebar
 * (lib/lightning_web/live/components/menu.ex), identified by the suffix of
 * their path pattern after `/projects/:project_id`.
 */
const SIDEBAR_PATH_SUFFIXES = [
  '/w',
  '/channels',
  '/sandboxes',
  '/history',
  '/settings',
];

/**
 * The hrefs present in the user menu dropdown
 * (lib/lightning_web/components/layout_components.ex).
 */
const USER_MENU_PATHS = [
  '/projects',
  '/profile',
  '/credentials',
  '/profile/tokens',
];

/** Substitute `:project_id` (the only param we receive) into a path pattern.
 * `path` is always the (possibly still parameterised) result; `unresolved`
 * names the first `:param` left over, if any. */
function resolvePath(
  pattern: string,
  params: TourRequest['params']
): { path: string; unresolved: string | null } {
  let path = pattern;
  if (params.project_id) {
    path = path.replace(/:project_id(?=\/|$)/g, params.project_id);
  }
  const unresolved = /:[A-Za-z_]+/.exec(path);
  return { path, unresolved: unresolved ? unresolved[0] : null };
}

/**
 * Does a concrete pathname match a path pattern, segment by segment?
 * `:param` segments match any single non-empty segment.
 */
export function matchesPathPattern(pattern: string, pathname: string): boolean {
  const patternSegments = pattern.split('/').filter(s => s !== '');
  const pathSegments = pathname.split('/').filter(s => s !== '');
  if (patternSegments.length !== pathSegments.length) return false;
  for (let i = 0; i < patternSegments.length; i += 1) {
    const expected = patternSegments[i];
    const actual = pathSegments[i];
    if (expected === undefined || actual === undefined) return false;
    if (expected.startsWith(':')) continue;
    if (expected !== actual) return false;
  }
  return true;
}

function isPathPrefix(prefix: string, path: string): boolean {
  return path === prefix || path.startsWith(`${prefix}/`);
}

function arrivalFor(page: AppMapPage, tab?: AppMapTab): Arrival {
  const arrival: Arrival = {
    label: page.label,
    description: tab ? tab.description : page.description,
  };
  if (tab) arrival.tabLabel = tab.label;
  return arrival;
}

function tabStep(tab: AppMapTab): ElementStep {
  return {
    type: 'element',
    selector: `#${tab.hash}-tab`,
    title: `Open the "${tab.label}" tab`,
    body: `Click the "${tab.label}" tab.`,
    label: tab.label,
    advanceOn: `hash:${tab.hash}`,
    expectNavigation: false,
  };
}

function sidebarStep(
  sidebarPage: AppMapPage,
  resolvedSidebarPath: string
): ElementStep {
  return {
    type: 'element',
    selector: `#side-menu a[href="${resolvedSidebarPath}"]`,
    title: `Go to ${sidebarPage.label}`,
    body: `Click "${sidebarPage.label}" in the sidebar.`,
    label: sidebarPage.label,
    advanceOn: 'click',
    expectNavigation: true,
  };
}

function planProjectSection(
  pages: AppMapPage[],
  destination: AppMapPage,
  destinationPath: string,
  params: TourRequest['params'],
  tab: AppMapTab | undefined
): TourPlan {
  // Sidebar-linkable pages: project-section pages whose path pattern is
  // exactly `/projects/:project_id<suffix>` for one of the sidebar suffixes.
  const sidebarPages = pages.filter(
    p =>
      p.section === 'project' &&
      SIDEBAR_PATH_SUFFIXES.some(
        suffix => p.path === `/projects/:project_id${suffix}`
      )
  );

  // Longest-prefix match of a sidebar page's resolved path against the
  // destination path (e.g. /history is the prefix of /history/channels).
  let best: { page: AppMapPage; path: string } | null = null;
  for (const page of sidebarPages) {
    const resolved = resolvePath(page.path, params);
    if (resolved.unresolved) continue;
    if (!isPathPrefix(resolved.path, destinationPath)) continue;
    if (!best || resolved.path.length > best.path.length) {
      best = { page, path: resolved.path };
    }
  }

  const arrival = arrivalFor(destination, tab);

  if (!best) {
    // Not reachable from the sidebar — navigate directly.
    return { fallbackPath: destinationPath, arrival };
  }

  const steps: Step[] = [sidebarStep(best.page, best.path)];

  if (best.path !== destinationPath) {
    // The sidebar gets us partway (e.g. History); hop the rest automatically.
    steps.push({ type: 'navigate', path: destinationPath });
  }

  if (tab) {
    steps.push(tabStep(tab));
    return { steps, arrival, destinationPath, destinationHash: tab.hash };
  }

  return { steps, arrival, destinationPath };
}

function planUserSection(
  destination: AppMapPage,
  destinationPath: string
): TourPlan {
  const arrival = arrivalFor(destination);

  if (!USER_MENU_PATHS.includes(destinationPath)) {
    // Not linked from the user menu — navigate directly.
    return { fallbackPath: destinationPath, arrival };
  }

  const steps: Step[] = [
    {
      type: 'element',
      selector: '#user-menu-trigger',
      title: 'Open your user menu',
      body: 'Click your name at the bottom of the sidebar.',
      label: 'your user menu',
      advanceOn: 'click',
      expectNavigation: false,
    },
    {
      type: 'element',
      selector: `[role="menu"] a[href="${destinationPath}"]`,
      title: `Go to ${destination.label}`,
      body: `Click "${destination.label}" in the menu.`,
      label: destination.label,
      advanceOn: 'click',
      expectNavigation: true,
    },
  ];

  return { steps, arrival, destinationPath };
}

/** How many `requires` hops we will follow before giving up. */
const MAX_REQUIRES_DEPTH = 4;

function toSpotlightElement(element: AppMapElement): SpotlightElement {
  const spotlit: SpotlightElement = {
    selector: `[data-tour-anchor="${element.id}"]`,
    label: element.label,
    description: element.description,
  };
  if (typeof element.hint === 'string' && element.hint.length > 0) {
    spotlit.hint = element.hint;
  }
  return spotlit;
}

/**
 * Walk the target's `requires` chain, outermost prerequisite first. Guarded
 * against cycles and capped at MAX_REQUIRES_DEPTH hops; a `requires` naming
 * an unknown element id is treated as absent (the chain stops there).
 */
function requiresChain(
  page: AppMapPage,
  target: AppMapElement
): AppMapElement[] {
  const chain: AppMapElement[] = [];
  const seen = new Set<string>([target.id]);
  let current = target;
  while (chain.length < MAX_REQUIRES_DEPTH) {
    const requiredId = current.requires;
    if (typeof requiredId !== 'string' || seen.has(requiredId)) break;
    const required = page.elements?.find(e => e.id === requiredId);
    if (!required) break;
    chain.unshift(required);
    seen.add(requiredId);
    current = required;
  }
  return chain;
}

/**
 * Plan an element request: spotlight a control on the page the user is
 * already on. Element requests never produce navigation steps — if the
 * current path does not match the page's pattern, the answer is "ask again
 * from there".
 */
function planElement(
  destination: AppMapPage,
  elementId: string,
  params: TourRequest['params'],
  currentPath: string | undefined
): TourPlan {
  const element = destination.elements?.find(e => e.id === elementId);
  if (!element) {
    return {
      error: `Unknown element "${elementId}" on page "${destination.id}"`,
    };
  }

  // Match the partially-substituted pattern (like the alreadyHere check), so
  // any params we did substitute must agree with the current path.
  const resolved = resolvePath(destination.path, params);
  if (!currentPath || !matchesPathPattern(resolved.path, currentPath)) {
    return { wrongPage: true, pageLabel: destination.label };
  }

  return {
    spotlight: {
      chain: requiresChain(destination, element).map(toSpotlightElement),
      target: toSpotlightElement(element),
    },
  };
}

/**
 * Build a tour plan.
 *
 * Returns one of:
 * - `{steps, arrival, destinationPath, destinationHash?}` — spotlight steps to
 *   walk through;
 * - `{fallbackPath, arrival}` — no click path is known; navigate directly and
 *   show the arrival card there;
 * - `{alreadyHere, arrival}` — the destination has params we cannot fill in,
 *   but `options.currentPath` already matches its pattern: the user is on the
 *   page, so show the arrival card where they stand;
 * - `{spotlight}` — an element request and the user is on the page: highlight
 *   the control where they stand, walking its `requires` prerequisites first
 *   when the control is not yet on screen;
 * - `{wrongPage, pageLabel}` — an element request from some other page: tell
 *   the user to ask again from the right one;
 * - `{error}` — the request cannot be satisfied (unknown page/tab/element, or
 *   a path parameter we cannot fill in).
 */
export function buildTourPlan(
  pages: AppMapPage[],
  request: TourRequest,
  options: TourPlanOptions = {}
): TourPlan {
  const destination = pages.find(p => p.id === request.page);
  if (!destination) {
    return { error: `Unknown app-map page id "${request.page}"` };
  }

  // Element requests take a separate, navigation-free path. A non-string
  // `element` on a forged event is treated as absent (same rule as the
  // NavigateButton fence parser).
  if (typeof request.element === 'string') {
    return planElement(
      destination,
      request.element,
      request.params ?? {},
      options.currentPath
    );
  }

  let tab: AppMapTab | undefined;
  if (request.tab !== undefined) {
    tab = destination.tabs?.find(t => t.hash === request.tab);
    if (!tab) {
      return {
        error: `Unknown tab "${request.tab}" on page "${destination.id}"`,
      };
    }
  }

  const resolved = resolvePath(destination.path, request.params ?? {});
  if (resolved.unresolved) {
    // We can't build a route to the page, but the user may already be on it
    // (e.g. "take me to the workflow editor" from inside the editor). Match
    // the partially-resolved pattern so any substituted params must agree.
    if (
      options.currentPath &&
      matchesPathPattern(resolved.path, options.currentPath)
    ) {
      return { alreadyHere: true, arrival: arrivalFor(destination, tab) };
    }
    return {
      error: `Cannot resolve "${resolved.unresolved}" in path "${destination.path}"`,
    };
  }
  const destinationPath = resolved.path;

  switch (destination.section) {
    case 'project':
      return planProjectSection(
        pages,
        destination,
        destinationPath,
        request.params ?? {},
        tab
      );
    case 'user':
      return planUserSection(destination, destinationPath);
    case 'admin':
    case 'auth':
      return {
        fallbackPath: destinationPath,
        arrival: arrivalFor(destination, tab),
      };
  }
}
