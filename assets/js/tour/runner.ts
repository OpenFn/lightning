/**
 * DOM side of the guided tour engine.
 *
 * Listens for the `lightning:start-tour` CustomEvent, fetches the app map,
 * builds a plan (./plan.ts), and walks the user through it by spotlighting
 * the next element to click. State lives in sessionStorage so tours survive
 * LiveView navigations and full page loads.
 *
 * No libraries; styling is inline using the Tailwind CSS variables
 * (see .claude/rules/colours.md — no hex literals).
 */

import { buildTourPlan } from './plan';
import type {
  AppMapPage,
  Arrival,
  ElementStep,
  Spotlight,
  SpotlightElement,
  Step,
  TourRequest,
} from './plan';

const STORAGE_KEY = 'lightning:tour';
const ROOT_ID = 'lightning-tour-root';
const APP_MAP_URL = '/api/app_map';
const POLL_INTERVAL_MS = 150;
const POLL_TIMEOUT_MS = 8000;
// Element spotlights have no navigation to fall back to, so give up sooner.
const SPOTLIGHT_POLL_TIMEOUT_MS = 4000;
const MAX_STATE_AGE_MS = 10 * 60 * 1000;
const Z_INDEX = 10050; // above the app chrome (user menu panel is z-9999)

interface TourState {
  steps: Step[];
  index: number;
  arrival: Arrival;
  destinationPath: string;
  destinationHash?: string;
  startedAt: number;
}

// ---------------------------------------------------------------------------
// State persistence
// ---------------------------------------------------------------------------

function readState(): TourState | null {
  let raw: string | null = null;
  try {
    raw = sessionStorage.getItem(STORAGE_KEY);
  } catch {
    return null;
  }
  if (!raw) return null;
  let state: unknown;
  try {
    state = JSON.parse(raw);
  } catch {
    clearState();
    return null;
  }
  if (
    typeof state !== 'object' ||
    state === null ||
    !Array.isArray((state as TourState).steps) ||
    typeof (state as TourState).index !== 'number' ||
    typeof (state as TourState).destinationPath !== 'string' ||
    typeof (state as TourState).startedAt !== 'number'
  ) {
    clearState();
    return null;
  }
  const tourState = state as TourState;
  if (Date.now() - tourState.startedAt > MAX_STATE_AGE_MS) {
    clearState();
    return null;
  }
  return tourState;
}

function writeState(state: TourState): void {
  try {
    sessionStorage.setItem(STORAGE_KEY, JSON.stringify(state));
  } catch {
    // Storage unavailable: the tour still works within this page.
  }
}

function clearState(): void {
  try {
    sessionStorage.removeItem(STORAGE_KEY);
  } catch {
    // ignore
  }
}

// ---------------------------------------------------------------------------
// Rendering
// ---------------------------------------------------------------------------

const DIM = 'color-mix(in oklab, var(--color-gray-950) 55%, transparent)';
const RING = 'var(--color-indigo-500)';
const CARD_SHADOW =
  '0 10px 25px color-mix(in oklab, var(--color-gray-950) 25%, transparent)';
const CARD_WIDTH = 320;
const SPOTLIGHT_PADDING = 4;

let repositionScheduled = false;
let activeCleanup: (() => void) | null = null;
let pollTimer: ReturnType<typeof setInterval> | null = null;
let noticeTimer: ReturnType<typeof setTimeout> | null = null;

const NOTICE_DURATION_MS = 6000;

function getRoot(): HTMLElement {
  let root = document.getElementById(ROOT_ID);
  if (!root) {
    root = document.createElement('div');
    root.id = ROOT_ID;
    document.body.appendChild(root);
  }
  return root;
}

/** Tear down everything the tour put on the page (but keep stored state). */
function teardownUi(): void {
  if (activeCleanup) {
    activeCleanup();
    activeCleanup = null;
  }
  if (pollTimer !== null) {
    clearInterval(pollTimer);
    pollTimer = null;
  }
  if (noticeTimer !== null) {
    clearTimeout(noticeTimer);
    noticeTimer = null;
  }
  document.getElementById(ROOT_ID)?.remove();
}

/** End the tour entirely: UI gone, state gone. */
function endTour(): void {
  teardownUi();
  clearState();
}

function styleCard(card: HTMLElement): void {
  Object.assign(card.style, {
    position: 'fixed',
    width: `${CARD_WIDTH}px`,
    maxWidth: 'calc(100vw - 16px)',
    boxSizing: 'border-box',
    padding: '16px',
    borderRadius: '12px',
    background: 'var(--color-white)',
    color: 'var(--color-gray-900)',
    boxShadow: CARD_SHADOW,
    border: '1px solid var(--color-gray-200)',
    font: '14px/1.5 ui-sans-serif, system-ui, sans-serif',
    zIndex: `${Z_INDEX + 2}`,
    pointerEvents: 'auto',
  });
}

function makeButton(label: string): HTMLButtonElement {
  const button = document.createElement('button');
  button.type = 'button';
  button.textContent = label;
  Object.assign(button.style, {
    font: 'inherit',
    fontWeight: '500',
    color: 'var(--color-white)',
    background: 'var(--color-indigo-600)',
    border: 'none',
    borderRadius: '8px',
    padding: '6px 12px',
    cursor: 'pointer',
  });
  return button;
}

function cardText(card: HTMLElement, title: string, body: string): void {
  const titleEl = document.createElement('div');
  titleEl.textContent = title;
  Object.assign(titleEl.style, {
    fontWeight: '600',
    marginBottom: '4px',
    color: 'var(--color-gray-900)',
  });
  const bodyEl = document.createElement('div');
  bodyEl.textContent = body;
  Object.assign(bodyEl.style, { color: 'var(--color-gray-600)' });
  card.append(titleEl, bodyEl);
}

function positionCard(card: HTMLElement, targetRect: DOMRect): void {
  const viewportWidth = window.innerWidth || 1024;
  const viewportHeight = window.innerHeight || 768;
  const cardHeight = card.offsetHeight || 120;

  let left = targetRect.right + 16;
  if (left + CARD_WIDTH > viewportWidth - 8) {
    left = targetRect.left;
  }
  left = Math.max(8, Math.min(left, viewportWidth - CARD_WIDTH - 8));

  let top = targetRect.top;
  if (left >= targetRect.left && left < targetRect.right) {
    // Card overlaps the target horizontally: place it below (or above).
    top = targetRect.bottom + 12;
    if (top + cardHeight > viewportHeight - 8) {
      top = targetRect.top - cardHeight - 12;
    }
  }
  top = Math.max(
    8,
    Math.min(top, Math.max(8, viewportHeight - cardHeight - 8))
  );

  card.style.left = `${left}px`;
  card.style.top = `${top}px`;
}

function isVisible(el: Element): boolean {
  return el.getClientRects().length > 0;
}

/** The spotlight ring: a transparent box over the target whose huge
 * box-shadow dims everything else. pointer-events: none so the target stays
 * clickable. */
function makeRing(): HTMLElement {
  const ring = document.createElement('div');
  Object.assign(ring.style, {
    position: 'fixed',
    pointerEvents: 'none',
    borderRadius: '8px',
    boxShadow: `0 0 0 3px ${RING}, 0 0 0 9999px ${DIM}`,
    zIndex: `${Z_INDEX}`,
    transition: 'top 150ms, left 150ms, width 150ms, height 150ms',
  });
  return ring;
}

/** Position the ring and card over the target now, and keep them there on
 * scroll/resize (rAF-throttled). Returns the listener-removal function. */
function wireReposition(
  target: Element,
  ring: HTMLElement,
  card: HTMLElement
): () => void {
  const reposition = () => {
    const rect = target.getBoundingClientRect();
    ring.style.top = `${rect.top - SPOTLIGHT_PADDING}px`;
    ring.style.left = `${rect.left - SPOTLIGHT_PADDING}px`;
    ring.style.width = `${rect.width + SPOTLIGHT_PADDING * 2}px`;
    ring.style.height = `${rect.height + SPOTLIGHT_PADDING * 2}px`;
    positionCard(card, rect);
  };
  reposition();

  const scheduleReposition = () => {
    if (repositionScheduled) return;
    repositionScheduled = true;
    requestAnimationFrame(() => {
      repositionScheduled = false;
      reposition();
    });
  };

  window.addEventListener('scroll', scheduleReposition, true);
  window.addEventListener('resize', scheduleReposition);
  return () => {
    window.removeEventListener('scroll', scheduleReposition, true);
    window.removeEventListener('resize', scheduleReposition);
  };
}

/**
 * Render the spotlight + info card for one element step. Returns a cleanup
 * function; registers reposition handlers (rAF-throttled) and the advance
 * listener.
 */
function renderStep(
  target: Element,
  step: ElementStep,
  stepNumber: number,
  stepCount: number,
  onAdvance: () => void
): void {
  const root = getRoot();
  root.replaceChildren();

  const spotlight = makeRing();

  const card = document.createElement('div');
  styleCard(card);
  cardText(card, step.title, step.body);

  const footer = document.createElement('div');
  Object.assign(footer.style, {
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'space-between',
    marginTop: '12px',
  });
  const progress = document.createElement('span');
  progress.textContent = `${stepNumber} of ${stepCount}`;
  progress.style.color = 'var(--color-gray-500)';
  const exitButton = document.createElement('button');
  exitButton.type = 'button';
  exitButton.textContent = 'Exit tour';
  Object.assign(exitButton.style, {
    font: 'inherit',
    color: 'var(--color-gray-600)',
    background: 'transparent',
    border: '1px solid var(--color-gray-300)',
    borderRadius: '8px',
    padding: '4px 10px',
    cursor: 'pointer',
  });
  exitButton.addEventListener('click', () => endTour());
  footer.append(progress, exitButton);
  card.appendChild(footer);

  root.append(spotlight, card);

  const removeReposition = wireReposition(target, spotlight, card);

  // Advance listener. For clicks, listen in the capture phase on the document
  // so we still catch the click if LiveView morphs the element under us.
  const onDocumentClick = (event: Event) => {
    const clicked = event.target as Element | null;
    if (clicked?.closest?.(step.selector)) {
      removeListeners();
      onAdvance();
    }
  };
  const onHashChange = () => {
    if (!step.advanceOn.startsWith('hash:')) return;
    const wanted = `#${step.advanceOn.slice('hash:'.length)}`;
    if (window.location.hash === wanted) {
      removeListeners();
      onAdvance();
    }
  };

  if (step.advanceOn === 'click') {
    document.addEventListener('click', onDocumentClick, true);
  } else {
    window.addEventListener('hashchange', onHashChange);
  }

  function removeListeners(): void {
    document.removeEventListener('click', onDocumentClick, true);
    window.removeEventListener('hashchange', onHashChange);
    removeReposition();
  }

  activeCleanup = removeListeners;
}

/**
 * Render the terminal "here it is" spotlight for an element request: ring +
 * card with the element's label, description, and a Done button. Nothing is
 * persisted; Done, Escape, or navigating away dismisses it.
 */
function renderSpotlight(target: Element, element: SpotlightElement): void {
  const root = getRoot();
  root.replaceChildren();

  const ring = makeRing();

  const card = document.createElement('div');
  styleCard(card);
  cardText(card, element.label, element.description);

  const footer = document.createElement('div');
  Object.assign(footer.style, {
    display: 'flex',
    justifyContent: 'flex-end',
    marginTop: '12px',
  });
  const doneButton = makeButton('Done');
  doneButton.addEventListener('click', () => endTour());
  footer.appendChild(doneButton);
  card.appendChild(footer);

  root.append(ring, card);

  activeCleanup = wireReposition(target, ring, card);
}

/** First *visible* match for an anchor selector (anchors like canvas-step
 * can appear on several nodes — the first on-screen one wins). */
function findAnchor(selector: string): Element | null {
  for (const el of Array.from(document.querySelectorAll(selector))) {
    if (isVisible(el)) return el;
  }
  return null;
}

interface ChainPosition {
  index: number;
  target: Element;
}

/** The deepest member of the spotlight sequence (prerequisites then target)
 * whose anchor is on screen, searching no earlier than `minIndex`. */
function resolveDeepest(
  sequence: SpotlightElement[],
  minIndex: number
): ChainPosition | null {
  for (let i = sequence.length - 1; i >= minIndex; i -= 1) {
    const member = sequence[i];
    if (!member) continue;
    const target = findAnchor(member.selector);
    if (target) return { index: i, target };
  }
  return null;
}

/** Poll (briefly) until `resolve` finds an anchor, on the shared pollTimer so
 * every teardown path cancels it. */
function pollForAnchor(
  resolve: () => ChainPosition | null,
  onFound: (found: ChainPosition) => void,
  onTimeout: () => void
): void {
  const deadline = Date.now() + SPOTLIGHT_POLL_TIMEOUT_MS;

  const attempt = (): boolean => {
    const found = resolve();
    if (!found) return false;
    if (pollTimer !== null) {
      clearInterval(pollTimer);
      pollTimer = null;
    }
    onFound(found);
    return true;
  };

  if (attempt()) return;

  pollTimer = setInterval(() => {
    if (attempt()) return;
    if (Date.now() >= deadline) {
      if (pollTimer !== null) {
        clearInterval(pollTimer);
        pollTimer = null;
      }
      onTimeout();
    }
  }, POLL_INTERVAL_MS);
}

function missingNotice(spotlight: Spotlight): string {
  return spotlight.target.hint ?? "Couldn't find that control on this page.";
}

/**
 * Run the in-page spotlight sequence from `index`: prerequisite members get a
 * "Click here" card that advances on click (no navigation), the last member —
 * always the target — gets the terminal Done card. After each click we poll
 * for the *deepest* next anchor, so a click that reveals several chain
 * members at once skips the redundant ones.
 */
function runChain(
  spotlight: Spotlight,
  steps: SpotlightElement[],
  index: number,
  target: Element
): void {
  const member = steps[index];
  if (!member) return;

  if (index === steps.length - 1) {
    renderSpotlight(target, spotlight.target);
    return;
  }

  const step: ElementStep = {
    type: 'element',
    selector: member.selector,
    title: `Click here: ${member.label}`,
    body: member.description,
    advanceOn: 'click',
    expectNavigation: false,
  };
  renderStep(target, step, index + 1, steps.length, () => {
    // Drop the old ring while the next anchor renders.
    getRoot().replaceChildren();
    pollForAnchor(
      () => resolveDeepest(steps, index + 1),
      found => runChain(spotlight, steps, found.index, found.target),
      () => renderNotice(missingNotice(spotlight))
    );
  });
}

/**
 * Entry point for an element request: if the target's anchor is already on
 * screen, spotlight it directly; otherwise start from the deepest prerequisite
 * whose anchor is present and walk the user through the clicks in between.
 * If nothing in the chain is on screen, show the target's hint (or a generic
 * notice).
 */
function startSpotlight(spotlight: Spotlight): void {
  const sequence = [...spotlight.chain, spotlight.target];

  pollForAnchor(
    () => resolveDeepest(sequence, 0),
    found => {
      // Slice so "n of m" counts only the steps the user actually has left.
      runChain(spotlight, sequence.slice(found.index), 0, found.target);
    },
    () => renderNotice(missingNotice(spotlight))
  );
}

function renderArrivalCard(arrival: Arrival): void {
  const root = getRoot();
  root.replaceChildren();

  const card = document.createElement('div');
  styleCard(card);
  Object.assign(card.style, { right: '16px', bottom: '16px' });

  const title = arrival.tabLabel
    ? `${arrival.label} — ${arrival.tabLabel}`
    : arrival.label;
  cardText(card, `You've arrived: ${title}`, arrival.description);

  const footer = document.createElement('div');
  Object.assign(footer.style, {
    display: 'flex',
    justifyContent: 'flex-end',
    marginTop: '12px',
  });
  const doneButton = makeButton('Done');
  doneButton.addEventListener('click', () => endTour());
  footer.appendChild(doneButton);
  card.appendChild(footer);

  root.appendChild(card);
}

/**
 * A small, visible "the tour couldn't start/continue" notice: bottom-centre,
 * auto-dismissed after a few seconds, with a close button. Lives inside the
 * single tour root so every cleanup path removes it too.
 */
function renderNotice(message: string): void {
  teardownUi();
  const root = getRoot();

  const card = document.createElement('div');
  styleCard(card);
  Object.assign(card.style, {
    left: '50%',
    bottom: '16px',
    transform: 'translateX(-50%)',
    display: 'flex',
    alignItems: 'center',
    gap: '12px',
  });

  const text = document.createElement('span');
  text.textContent = message;
  text.style.color = 'var(--color-gray-700)';

  const closeButton = document.createElement('button');
  closeButton.type = 'button';
  closeButton.textContent = '×';
  closeButton.setAttribute('aria-label', 'Dismiss');
  Object.assign(closeButton.style, {
    font: 'inherit',
    fontSize: '18px',
    lineHeight: '1',
    color: 'var(--color-gray-500)',
    background: 'transparent',
    border: 'none',
    cursor: 'pointer',
    padding: '2px 4px',
    flexShrink: '0',
  });
  closeButton.addEventListener('click', () => teardownUi());

  card.append(text, closeButton);
  root.appendChild(card);

  noticeTimer = setTimeout(() => {
    noticeTimer = null;
    teardownUi();
  }, NOTICE_DURATION_MS);
}

// ---------------------------------------------------------------------------
// Tour progression
// ---------------------------------------------------------------------------

function atDestination(state: TourState): boolean {
  if (window.location.pathname !== state.destinationPath) return false;
  if (state.destinationHash) {
    return window.location.hash === `#${state.destinationHash}`;
  }
  return true;
}

function arrive(state: TourState): void {
  // Clear the stored state now so a reload doesn't resurrect the card, but
  // leave the card up until "Done", Escape, or the next navigation.
  clearState();
  renderArrivalCard(state.arrival);
}

/** Give up on spotlighting: jump straight to the destination. */
function fallBackToDirectNavigation(state: TourState): void {
  if (!state.destinationPath) {
    console.warn('Tour ended: no destination to fall back to');
    clearState();
    renderNotice("Couldn't continue the guided tour.");
    return;
  }
  teardownUi();
  writeState({ ...state, index: state.steps.length });
  const hash = state.destinationHash ? `#${state.destinationHash}` : '';
  window.location.assign(state.destinationPath + hash);
}

function advance(state: TourState): void {
  const next: TourState = { ...state, index: state.index + 1 };
  writeState(next);
  const step = state.steps[state.index];
  if (step && step.type === 'element' && step.expectNavigation) {
    // Navigation is coming; drop the UI and let resume() pick up on the next
    // page (phx:page-loading-stop or a fresh module init).
    teardownUi();
  } else {
    showCurrentStep(next);
  }
}

function showCurrentStep(state: TourState): void {
  if (pollTimer !== null) {
    clearInterval(pollTimer);
    pollTimer = null;
  }

  if (atDestination(state)) {
    teardownUi();
    arrive(state);
    return;
  }

  if (state.index >= state.steps.length) {
    // Finished all steps but we're somewhere else (redirect, permissions…):
    // end quietly rather than risking a navigation loop.
    endTour();
    return;
  }

  const step = state.steps[state.index];
  if (!step) {
    endTour();
    return;
  }

  if (step.type === 'navigate') {
    teardownUi();
    writeState({ ...state, index: state.index + 1 });
    window.location.assign(step.path);
    return;
  }

  // Poll for the element (it may still be rendering after a live navigation).
  const deadline = Date.now() + POLL_TIMEOUT_MS;
  const elementSteps = state.steps.filter(s => s.type === 'element');
  const stepNumber = Math.max(1, elementSteps.indexOf(step) + 1);

  const tryRender = (): boolean => {
    const target = document.querySelector(step.selector);
    if (target && isVisible(target)) {
      if (pollTimer !== null) {
        clearInterval(pollTimer);
        pollTimer = null;
      }
      if (activeCleanup) {
        activeCleanup();
        activeCleanup = null;
      }
      renderStep(target, step, stepNumber, elementSteps.length, () =>
        advance(state)
      );
      return true;
    }
    return false;
  };

  if (tryRender()) return;

  pollTimer = setInterval(() => {
    if (tryRender()) return;
    if (Date.now() >= deadline) {
      if (pollTimer !== null) {
        clearInterval(pollTimer);
        pollTimer = null;
      }
      fallBackToDirectNavigation(state);
    }
  }, POLL_INTERVAL_MS);
}

/** Re-read persisted state and render whatever step we're on. */
function resume(): void {
  const state = readState();
  if (!state) {
    // No active tour; make sure nothing is left behind (e.g. an arrival card
    // from a finished tour, once the user navigates away).
    teardownUi();
    return;
  }
  showCurrentStep(state);
}

// ---------------------------------------------------------------------------
// Start
// ---------------------------------------------------------------------------

function isTourRequest(detail: unknown): detail is TourRequest {
  return (
    typeof detail === 'object' &&
    detail !== null &&
    typeof (detail as TourRequest).page === 'string'
  );
}

const GENERIC_NOTICE = "Couldn't start a guided tour for that page.";

async function startTour(request: TourRequest): Promise<void> {
  let pages: unknown;
  try {
    const response = await fetch(APP_MAP_URL, {
      headers: { accept: 'application/json' },
    });
    if (!response.ok) {
      console.warn(
        `Tour aborted: ${APP_MAP_URL} responded with ${response.status}`
      );
      renderNotice(GENERIC_NOTICE);
      return;
    }
    pages = ((await response.json()) as { pages?: unknown }).pages;
  } catch (error) {
    console.warn('Tour aborted: could not fetch the app map', error);
    renderNotice(GENERIC_NOTICE);
    return;
  }
  if (!Array.isArray(pages)) {
    console.warn('Tour aborted: unexpected app map payload');
    renderNotice(GENERIC_NOTICE);
    return;
  }

  // Trust the server's shape beyond "it's an array"; buildTourPlan only fails
  // soft (unknown page id / unresolved path) on malformed entries.
  const appMap = pages as AppMapPage[];
  const plan = buildTourPlan(appMap, request, {
    currentPath: window.location.pathname,
  });
  if ('error' in plan) {
    console.warn(`Tour aborted: ${plan.error}`);
    const label = appMap.find(p => p.id === request.page)?.label;
    renderNotice(
      label ? `Couldn't start a guided tour for ${label}.` : GENERIC_NOTICE
    );
    return;
  }

  if ('wrongPage' in plan) {
    // Element guidance only applies to the page the user is on. Like the
    // error path above, this only shows a notice (any stored tour state is
    // left alone).
    renderNotice(
      `That guidance is for the ${plan.pageLabel} page — ask again from there.`
    );
    return;
  }

  endTour(); // Replace any tour already in progress.

  if ('spotlight' in plan) {
    // In-page highlight (with any prerequisite clicks first): no persistence —
    // dismissed by Done, Escape, or navigating away.
    startSpotlight(plan.spotlight);
    return;
  }

  if ('alreadyHere' in plan) {
    // The user is already on the destination page (we just can't address it
    // by params): no steps to run, show the arrival card where they stand.
    renderArrivalCard(plan.arrival);
    return;
  }

  const state: TourState =
    'fallbackPath' in plan
      ? {
          steps: [],
          index: 0,
          arrival: plan.arrival,
          destinationPath: plan.fallbackPath,
          startedAt: Date.now(),
        }
      : {
          steps: plan.steps,
          index: 0,
          arrival: plan.arrival,
          destinationPath: plan.destinationPath,
          ...(plan.destinationHash !== undefined
            ? { destinationHash: plan.destinationHash }
            : {}),
          startedAt: Date.now(),
        };
  writeState(state);

  if ('fallbackPath' in plan && !atDestination(state)) {
    window.location.assign(plan.fallbackPath);
    return;
  }

  showCurrentStep(state);
}

let initialized = false;

/**
 * Wire the tour engine up. Called once from app.js.
 */
export function initTour(): void {
  if (initialized) return;
  initialized = true;

  document.addEventListener('lightning:start-tour', event => {
    const detail = (event as CustomEvent).detail as unknown;
    if (!isTourRequest(detail)) {
      console.warn('Tour aborted: malformed lightning:start-tour detail');
      renderNotice(GENERIC_NOTICE);
      return;
    }
    void startTour(detail);
  });

  // Resume across LiveView navigations and tab (hash) changes.
  window.addEventListener('phx:page-loading-stop', resume);
  window.addEventListener('hashchange', () => {
    // Steps advancing on a hash manage themselves; this catches arrival when
    // the user lands on the destination hash some other way.
    const state = readState();
    if (state && atDestination(state)) {
      teardownUi();
      arrive(state);
    }
  });

  document.addEventListener('keydown', event => {
    if (event.key === 'Escape' && document.getElementById(ROOT_ID)) {
      endTour();
    }
  });

  // Resume on a fresh page load.
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', resume, { once: true });
  } else {
    resume();
  }
}
