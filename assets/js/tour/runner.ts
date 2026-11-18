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
import { emitTourEvent } from './telemetry';

const STORAGE_KEY = 'lightning:tour';
const ROOT_ID = 'lightning-tour-root';
const APP_MAP_URL = '/api/app_map';
const POLL_INTERVAL_MS = 150;
const POLL_TIMEOUT_MS = 8000;
// Element spotlights have no navigation to fall back to, so give up sooner.
const SPOTLIGHT_POLL_TIMEOUT_MS = 4000;
/** How long autopilot lets the audience read a card before it clicks. Kept
 * under prefers-reduced-motion too: the pause is comprehension, not
 * decoration. */
const AUTOPILOT_PAUSE_MS = 1200;
/** Grand tours are capped at this many stops (Apollo's contract says 2-6). */
const MAX_TOUR_STOPS = 6;
const MAX_STATE_AGE_MS = 10 * 60 * 1000;
const Z_INDEX = 10050; // above the app chrome (user menu panel is z-9999)

interface TourState {
  steps: Step[];
  index: number;
  arrival: Arrival;
  destinationPath: string;
  destinationHash?: string;
  startedAt: number;
  /** App-map page id the tour targets, kept for telemetry context. */
  page?: string;
  /** Dedup flag: tour_started has been emitted for this tour, so a resume
   * after a (live or full) navigation must not re-emit it. */
  startedEmitted?: boolean;
  /** Autopilot drives the clicks itself; persisted so cross-page tours stay
   * on autopilot after navigation. */
  autopilot?: boolean;
  /** Grand tour: the ordered page ids being visited… */
  stops?: string[];
  /** …and which of them this state's plan is heading to. */
  stopIndex?: number;
  /** The request params, kept so later stops can be planned after navigation.
   */
  params?: TourRequest['params'];
}

// ---------------------------------------------------------------------------
// Telemetry
// ---------------------------------------------------------------------------

/** Context attached to tour lifecycle events. */
interface TelemetryContext {
  page?: string;
  element?: string;
}

let telemetryContext: TelemetryContext = {};

/** True while a tour attempt is underway and has not yet reached a terminal
 * event; guards tour_abandoned to at most one emission per tour. */
let tourLive = false;

function emitAbandoned(reason: 'escape' | 'exit' | 'timeout' | 'error'): void {
  if (!tourLive) return;
  tourLive = false;
  emitTourEvent('tour_abandoned', { reason, ...telemetryContext });
}

function emitCompleted(): void {
  tourLive = false;
  emitTourEvent('tour_completed', { ...telemetryContext });
}

/**
 * The stable set of notice_shown reasons:
 * - 'hint'         — a spotlight anchor never appeared; the element's hint
 *                    (or the generic missing-control text) was shown
 * - 'wrong_page'   — element guidance was requested from another page
 * - 'unknown_page' — the plan rejected the request (unknown page, tab, or
 *                    element id, or an unresolvable path parameter)
 * - 'error'        — app-map fetch/payload failures, malformed event detail,
 *                    or a dead end while continuing a tour
 */
type NoticeReason = 'hint' | 'wrong_page' | 'unknown_page' | 'error';

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
let autopilotTimer: ReturnType<typeof setTimeout> | null = null;

/** Autopilot's "let them read it, then act" pause. At most one pending action;
 * every teardown path cancels it, so Escape/Exit abort instantly. */
function scheduleAutopilot(action: () => void): void {
  if (autopilotTimer !== null) clearTimeout(autopilotTimer);
  autopilotTimer = setTimeout(() => {
    autopilotTimer = null;
    action();
  }, AUTOPILOT_PAUSE_MS);
}

/** Click a spotlit element the way a user would (works for SVG targets too).
 */
function autopilotClick(target: Element): void {
  if (target instanceof HTMLElement) {
    target.click();
  } else {
    target.dispatchEvent(
      new MouseEvent('click', { bubbles: true, cancelable: true })
    );
  }
}

/** The element focused before the tour moved focus into a card, restored when
 * the tour UI goes away. Only set by focusPrimary (notices never move focus).
 */
let previousFocus: Element | null = null;

/** Move focus to a card's primary button, remembering where focus came from
 * (once per tour) so teardown can restore it. */
function focusPrimary(button: HTMLElement): void {
  if (previousFocus === null) previousFocus = document.activeElement;
  button.focus();
}

function prefersReducedMotion(): boolean {
  return (
    window.matchMedia?.('(prefers-reduced-motion: reduce)').matches ?? false
  );
}

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
  if (autopilotTimer !== null) {
    clearTimeout(autopilotTimer);
    autopilotTimer = null;
  }
  document.getElementById(ROOT_ID)?.remove();
  if (previousFocus instanceof HTMLElement && previousFocus.isConnected) {
    previousFocus.focus();
  }
  previousFocus = null;
}

/** End the tour entirely: UI gone, state gone. A user-initiated reason
 * ('escape' | 'exit') emits tour_abandoned for a still-live tour. */
function endTour(reason?: 'escape' | 'exit'): void {
  if (reason) emitAbandoned(reason);
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

const CARD_TITLE_ID = 'lightning-tour-card-title';
const CARD_BODY_ID = 'lightning-tour-card-body';

/**
 * A styled tour card announced as a (non-modal) dialog: the page stays
 * interactive by design, so aria-modal is deliberately NOT set. Only one tour
 * card exists at a time, so the title/body ids are static.
 */
function dialogCard(title: string, body: string): HTMLElement {
  const card = document.createElement('div');
  styleCard(card);
  card.setAttribute('role', 'dialog');
  card.setAttribute('aria-labelledby', CARD_TITLE_ID);
  card.setAttribute('aria-describedby', CARD_BODY_ID);

  const titleEl = document.createElement('div');
  titleEl.id = CARD_TITLE_ID;
  titleEl.textContent = title;
  Object.assign(titleEl.style, {
    fontWeight: '600',
    marginBottom: '4px',
    color: 'var(--color-gray-900)',
  });
  const bodyEl = document.createElement('div');
  bodyEl.id = CARD_BODY_ID;
  bodyEl.textContent = body;
  Object.assign(bodyEl.style, { color: 'var(--color-gray-600)' });
  card.append(titleEl, bodyEl);
  return card;
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
  ring.setAttribute('aria-hidden', 'true');
  Object.assign(ring.style, {
    position: 'fixed',
    pointerEvents: 'none',
    borderRadius: '8px',
    boxShadow: `0 0 0 3px ${RING}, 0 0 0 9999px ${DIM}`,
    zIndex: `${Z_INDEX}`,
    // Movement easing is decoration; drop it for reduced-motion users.
    ...(prefersReducedMotion()
      ? {}
      : { transition: 'top 150ms, left 150ms, width 150ms, height 150ms' }),
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
  onAdvance: () => void,
  autopilot = false
): void {
  const root = getRoot();
  root.replaceChildren();

  const spotlight = makeRing();

  // Autopilot drives the click itself, so the card narrates instead of
  // instructing.
  const card = autopilot
    ? dialogCard(`Opening: ${step.label ?? step.title}`, step.body)
    : dialogCard(step.title, step.body);

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
  exitButton.addEventListener('click', () => endTour('exit'));
  footer.append(progress, exitButton);
  card.appendChild(footer);

  root.append(spotlight, card);
  focusPrimary(exitButton);

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

  if (autopilot) {
    // The programmatic click flows through the same advance listeners as a
    // real one, so everything downstream behaves exactly as today.
    scheduleAutopilot(() => autopilotClick(target));
  }
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

  const card = dialogCard(element.label, element.description);

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
  focusPrimary(doneButton);

  activeCleanup = wireReposition(target, ring, card);

  // Reaching the terminal card IS the end state (Done just dismisses it).
  emitTourEvent('spotlight_shown', { ...telemetryContext });
  emitCompleted();
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
  target: Element,
  autopilot: boolean
): void {
  const member = steps[index];
  if (!member) return;

  if (index === steps.length - 1) {
    // Terminal target card. Never auto-clicked, even on autopilot: this is
    // the "here it is" end state.
    renderSpotlight(target, spotlight.target);
    return;
  }

  const step: ElementStep = {
    type: 'element',
    selector: member.selector,
    title: `Click here: ${member.label}`,
    body: member.description,
    label: member.label,
    advanceOn: 'click',
    expectNavigation: false,
  };
  renderStep(
    target,
    step,
    index + 1,
    steps.length,
    () => {
      // Drop the old ring while the next anchor renders.
      getRoot().replaceChildren();
      pollForAnchor(
        () => resolveDeepest(steps, index + 1),
        found =>
          runChain(spotlight, steps, found.index, found.target, autopilot),
        () => {
          emitAbandoned('timeout');
          renderNotice(missingNotice(spotlight), 'hint');
        }
      );
    },
    autopilot
  );
}

/**
 * Entry point for an element request: if the target's anchor is already on
 * screen, spotlight it directly; otherwise start from the deepest prerequisite
 * whose anchor is present and walk the user through the clicks in between.
 * If nothing in the chain is on screen, show the target's hint (or a generic
 * notice).
 */
function startSpotlight(spotlight: Spotlight, autopilot: boolean): void {
  const sequence = [...spotlight.chain, spotlight.target];

  pollForAnchor(
    () => resolveDeepest(sequence, 0),
    found => {
      // Slice so "n of m" counts only the steps the user actually has left.
      runChain(
        spotlight,
        sequence.slice(found.index),
        0,
        found.target,
        autopilot
      );
    },
    () => {
      emitAbandoned('timeout');
      renderNotice(missingNotice(spotlight), 'hint');
    }
  );
}

function renderArrivalCard(arrival: Arrival): void {
  const root = getRoot();
  root.replaceChildren();

  const title = arrival.tabLabel
    ? `${arrival.label} — ${arrival.tabLabel}`
    : arrival.label;
  const card = dialogCard(`You've arrived: ${title}`, arrival.description);
  Object.assign(card.style, { right: '16px', bottom: '16px' });

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
  focusPrimary(doneButton);
}

/**
 * A small, visible "the tour couldn't start/continue" notice: bottom-centre,
 * auto-dismissed after a few seconds, with a close button. Lives inside the
 * single tour root so every cleanup path removes it too.
 */
function renderNotice(message: string, reason: NoticeReason): void {
  emitTourEvent('notice_shown', { reason, ...telemetryContext });
  teardownUi();
  const root = getRoot();

  const card = document.createElement('div');
  styleCard(card);
  // Polite live region: announced without stealing focus.
  card.setAttribute('role', 'status');
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
  if (state.page) telemetryContext = { page: state.page };

  const { stops, stopIndex } = state;
  if (
    Array.isArray(stops) &&
    typeof stopIndex === 'number' &&
    stopIndex < stops.length - 1
  ) {
    // Mid grand-tour: the card advances to the next stop instead of closing,
    // and completion is only emitted at the final stop.
    renderStopArrivalCard(state, stops, stopIndex);
    return;
  }

  renderArrivalCard(state.arrival);
  emitCompleted();
}

/** The arrival card for a non-final grand-tour stop: same card, but the
 * primary action continues to the next stop (Escape/Exit still end it all).
 */
function renderStopArrivalCard(
  state: TourState,
  stops: string[],
  stopIndex: number
): void {
  const root = getRoot();
  root.replaceChildren();

  const card = dialogCard(
    `You've arrived: ${state.arrival.label}`,
    state.arrival.description
  );
  Object.assign(card.style, { right: '16px', bottom: '16px' });

  const footer = document.createElement('div');
  Object.assign(footer.style, {
    display: 'flex',
    justifyContent: 'flex-end',
    marginTop: '12px',
  });
  const nextButton = makeButton(
    `Next stop (${stopIndex + 2} of ${stops.length}) →`
  );
  const goNext = () => {
    void continueGrandTour({
      stops,
      stopIndex: stopIndex + 1,
      params: state.params ?? {},
      autopilot: state.autopilot === true,
    });
  };
  nextButton.addEventListener('click', goNext);
  footer.appendChild(nextButton);
  card.appendChild(footer);

  root.appendChild(card);
  focusPrimary(nextButton);

  if (state.autopilot) scheduleAutopilot(goNext);
}

/** Give up on spotlighting: jump straight to the destination. */
function fallBackToDirectNavigation(state: TourState): void {
  if (!state.destinationPath) {
    console.warn('Tour ended: no destination to fall back to');
    clearState();
    emitAbandoned('timeout');
    renderNotice("Couldn't continue the guided tour.", 'error');
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
      renderStep(
        target,
        step,
        stepNumber,
        elementSteps.length,
        () => advance(state),
        state.autopilot === true
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
  // A persisted tour is live again (fresh page loads reset module state).
  // tour_started was emitted when it began (state.startedEmitted), never here.
  tourLive = true;
  telemetryContext = state.page ? { page: state.page } : {};
  showCurrentStep(state);
}

// ---------------------------------------------------------------------------
// Start
// ---------------------------------------------------------------------------

/**
 * The full lightning:start-tour event detail: a single page/element request,
 * or a multi-stop grand tour (`tour`), optionally on autopilot.
 */
interface StartTourDetail {
  page?: string;
  tab?: string;
  element?: string;
  tour?: string[];
  autopilot?: boolean;
  params?: TourRequest['params'];
}

function isValidTourArray(tour: unknown): tour is string[] {
  return (
    Array.isArray(tour) &&
    tour.length > 0 &&
    tour.every(id => typeof id === 'string' && id.length > 0)
  );
}

function isStartTourDetail(detail: unknown): detail is StartTourDetail {
  if (typeof detail !== 'object' || detail === null) return false;
  const d = detail as StartTourDetail;
  return typeof d.page === 'string' || isValidTourArray(d.tour);
}

const GENERIC_NOTICE = "Couldn't start a guided tour for that page.";

/** Fetch and loosely validate the app map; null (with a console warning) on
 * any failure. Trust the server's shape beyond "pages is an array";
 * buildTourPlan only fails soft on malformed entries. */
async function fetchAppMap(): Promise<AppMapPage[] | null> {
  try {
    const response = await fetch(APP_MAP_URL, {
      headers: { accept: 'application/json' },
    });
    if (!response.ok) {
      console.warn(
        `Tour aborted: ${APP_MAP_URL} responded with ${response.status}`
      );
      return null;
    }
    const pages = ((await response.json()) as { pages?: unknown }).pages;
    if (!Array.isArray(pages)) {
      console.warn('Tour aborted: unexpected app map payload');
      return null;
    }
    return pages as AppMapPage[];
  } catch (error) {
    console.warn('Tour aborted: could not fetch the app map', error);
    return null;
  }
}

/** What a grand tour carries from stop to stop. */
interface GrandTourContext {
  stops: string[];
  stopIndex: number;
  params: TourRequest['params'];
  autopilot: boolean;
}

/** Plan and run one grand-tour stop with the ordinary page machinery. */
function runStop(appMap: AppMapPage[], ctx: GrandTourContext): void {
  const { stops, stopIndex, params, autopilot } = ctx;
  const page = stops[stopIndex];
  if (!page) {
    endTour();
    return;
  }

  telemetryContext = { page };
  const plan = buildTourPlan(
    appMap,
    { page, params },
    { currentPath: window.location.pathname }
  );

  // Page-only requests can only yield steps/fallback/alreadyHere/error, and
  // the stops were validated at start — but a stop whose plannability relied
  // on the then-current path can stop planning after navigation. Skip it.
  if ('error' in plan || 'wrongPage' in plan || 'spotlight' in plan) {
    if (stopIndex < stops.length - 1) {
      runStop(appMap, { ...ctx, stopIndex: stopIndex + 1 });
    } else {
      emitAbandoned('error');
      renderNotice(GENERIC_NOTICE, 'error');
    }
    return;
  }

  const grandFields = {
    page,
    startedEmitted: true, // the grand tour emitted its own tour_started
    stops,
    stopIndex,
    params,
    ...(autopilot ? { autopilot: true } : {}),
  };

  if ('alreadyHere' in plan) {
    arrive({
      steps: [],
      index: 0,
      arrival: plan.arrival,
      destinationPath: window.location.pathname,
      startedAt: Date.now(),
      ...grandFields,
    });
    return;
  }

  const state: TourState = {
    steps: 'steps' in plan ? plan.steps : [],
    index: 0,
    arrival: plan.arrival,
    destinationPath: 'steps' in plan ? plan.destinationPath : plan.fallbackPath,
    ...('steps' in plan && plan.destinationHash !== undefined
      ? { destinationHash: plan.destinationHash }
      : {}),
    startedAt: Date.now(),
    ...grandFields,
  };
  writeState(state);

  if ('fallbackPath' in plan && !atDestination(state)) {
    window.location.assign(plan.fallbackPath);
    return;
  }

  showCurrentStep(state);
}

/** Continue a grand tour from a stop's arrival card ("Next stop" / autopilot).
 */
async function continueGrandTour(ctx: GrandTourContext): Promise<void> {
  const appMap = await fetchAppMap();
  if (!appMap) {
    emitAbandoned('error');
    renderNotice(GENERIC_NOTICE, 'error');
    return;
  }
  runStop(appMap, ctx);
}

function startGrandTour(appMap: AppMapPage[], detail: StartTourDetail): void {
  const params = detail.params ?? {};
  const autopilot = detail.autopilot === true;

  // Keep only stops the planner can actually route right now.
  const stops = (detail.tour ?? []).slice(0, MAX_TOUR_STOPS).filter(id => {
    const plan = buildTourPlan(
      appMap,
      { page: id, params },
      { currentPath: window.location.pathname }
    );
    return !('error' in plan);
  });

  if (stops.length === 0) {
    console.warn('Tour aborted: no tourable stops in the requested tour');
    emitAbandoned('error');
    renderNotice(GENERIC_NOTICE, 'unknown_page');
    return;
  }

  endTour(); // Replace any tour already in progress.

  if (stops.length === 1) {
    // Degenerate tour: run the one valid stop as a plain single-page tour.
    void startTour({
      page: stops[0] as string,
      params,
      ...(autopilot ? { autopilot: true } : {}),
    });
    return;
  }

  telemetryContext = { page: stops.join(',') };
  emitTourEvent('tour_started', {
    page: stops.join(','),
    steps_total: stops.length,
  });
  runStop(appMap, { stops, stopIndex: 0, params, autopilot });
}

async function startTour(detail: StartTourDetail): Promise<void> {
  telemetryContext = {};
  if (isValidTourArray(detail.tour)) {
    telemetryContext.page = detail.tour.join(',');
  } else if (typeof detail.page === 'string') {
    telemetryContext.page = detail.page;
  }
  if (typeof detail.element === 'string') {
    telemetryContext.element = detail.element;
  }
  tourLive = true;

  const appMap = await fetchAppMap();
  if (!appMap) {
    emitAbandoned('error');
    renderNotice(GENERIC_NOTICE, 'error');
    return;
  }

  if (isValidTourArray(detail.tour)) {
    startGrandTour(appMap, detail);
    return;
  }

  // The isStartTourDetail guard ensures `page` is a string here.
  const request = detail as TourRequest;
  const plan = buildTourPlan(appMap, request, {
    currentPath: window.location.pathname,
  });
  if ('error' in plan) {
    console.warn(`Tour aborted: ${plan.error}`);
    const label = appMap.find(p => p.id === request.page)?.label;
    emitAbandoned('error');
    renderNotice(
      label ? `Couldn't start a guided tour for ${label}.` : GENERIC_NOTICE,
      'unknown_page'
    );
    return;
  }

  if ('wrongPage' in plan) {
    // Element guidance only applies to the page the user is on. Like the
    // error path above, this only shows a notice (any stored tour state is
    // left alone). Not an abandonment: no tour ever began.
    tourLive = false;
    renderNotice(
      `That guidance is for the ${plan.pageLabel} page — ask again from there.`,
      'wrong_page'
    );
    return;
  }

  endTour(); // Replace any tour already in progress.

  if ('spotlight' in plan) {
    // In-page highlight (with any prerequisite clicks first): no persistence —
    // dismissed by Done, Escape, or navigating away. One startSpotlight call
    // per request, so no started-dedup flag is needed here.
    emitTourEvent('tour_started', {
      ...telemetryContext,
      steps_total: plan.spotlight.chain.length + 1,
    });
    startSpotlight(plan.spotlight, request.autopilot === true);
    return;
  }

  if ('alreadyHere' in plan) {
    // The user is already on the destination page (we just can't address it
    // by params): no steps to run, show the arrival card where they stand.
    renderArrivalCard(plan.arrival);
    emitCompleted();
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
          page: request.page,
          startedEmitted: false,
          ...(request.autopilot === true ? { autopilot: true } : {}),
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
          page: request.page,
          startedEmitted: false,
          ...(request.autopilot === true ? { autopilot: true } : {}),
        };
  if ('steps' in plan && !state.startedEmitted) {
    // Persisted flag: a resume after navigation must never re-emit this.
    state.startedEmitted = true;
    emitTourEvent('tour_started', {
      page: request.page,
      steps_total: plan.steps.length,
    });
  }
  writeState(state);

  if ('fallbackPath' in plan && !atDestination(state)) {
    window.location.assign(plan.fallbackPath);
    return;
  }

  showCurrentStep(state);
}

let initialized = false;
let removeInitListeners: (() => void) | null = null;

/**
 * Wire the tour engine up. Called once from app.js.
 */
export function initTour(): void {
  if (initialized) return;
  initialized = true;

  const onStartTour = (event: Event) => {
    const detail = (event as CustomEvent).detail as unknown;
    if (!isStartTourDetail(detail)) {
      console.warn('Tour aborted: malformed lightning:start-tour detail');
      telemetryContext = {};
      renderNotice(GENERIC_NOTICE, 'error');
      return;
    }
    void startTour(detail);
  };
  document.addEventListener('lightning:start-tour', onStartTour);

  // Resume across LiveView navigations and tab (hash) changes.
  const onLoadingStop = () => resume();
  window.addEventListener('phx:page-loading-stop', onLoadingStop);
  const onHashChange = () => {
    // Steps advancing on a hash manage themselves; this catches arrival when
    // the user lands on the destination hash some other way.
    const state = readState();
    if (state && atDestination(state)) {
      teardownUi();
      arrive(state);
    }
  };
  window.addEventListener('hashchange', onHashChange);

  // On document (not the card), so Escape works wherever focus is.
  const onKeydown = (event: KeyboardEvent) => {
    if (event.key === 'Escape' && document.getElementById(ROOT_ID)) {
      endTour('escape');
    }
  };
  document.addEventListener('keydown', onKeydown);

  // Resume on a fresh page load.
  const onReady = () => resume();
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', onReady, { once: true });
  } else {
    resume();
  }

  removeInitListeners = () => {
    document.removeEventListener('lightning:start-tour', onStartTour);
    window.removeEventListener('phx:page-loading-stop', onLoadingStop);
    window.removeEventListener('hashchange', onHashChange);
    document.removeEventListener('keydown', onKeydown);
    document.removeEventListener('DOMContentLoaded', onReady);
  };
}

/**
 * Undo initTour: remove the global listeners and any tour UI. Stored state is
 * left alone (a re-init resumes it). For tests and hot reloads.
 */
export function destroyTour(): void {
  if (!initialized) return;
  initialized = false;
  removeInitListeners?.();
  removeInitListeners = null;
  teardownUi();
}
