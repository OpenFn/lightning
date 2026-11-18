import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import { appMapPages } from './fixtures';

const PROJECT_ID = 'b1a2c3d4-0000-0000-0000-000000000002';
const STORAGE_KEY = 'lightning:tour';
const ROOT_ID = 'lightning-tour-root';

type FetchMock = ReturnType<typeof vi.fn>;

/** Serves the app map; always 204s telemetry posts to /api/tour_events. */
function mockAppMapFetch(status = 200): FetchMock {
  const fetchMock = vi.fn((url: RequestInfo | URL) => {
    if (url === '/api/tour_events') {
      return Promise.resolve({ ok: true, status: 204 } as Response);
    }
    return Promise.resolve({
      ok: status === 200,
      status,
      json: () => Promise.resolve({ pages: appMapPages }),
    } as Response);
  });
  vi.stubGlobal('fetch', fetchMock);
  return fetchMock;
}

/** The parsed bodies posted to /api/tour_events, in order. */
function tourEvents(fetchMock: FetchMock): Array<Record<string, unknown>> {
  return fetchMock.mock.calls
    .filter(call => call[0] === '/api/tour_events')
    .map(
      call =>
        JSON.parse((call[1] as RequestInit).body as string) as Record<
          string,
          unknown
        >
    );
}

function startTour(detail: unknown): void {
  document.dispatchEvent(new CustomEvent('lightning:start-tour', { detail }));
}

let destroyRunner: (() => void) | null = null;

async function initTour(): Promise<void> {
  // The runner guards against double initialisation with module state, so get
  // a fresh module (and a fresh guard) for every test; afterEach destroys it
  // so stale instances can't react to later tests' events.
  vi.resetModules();
  const runner = await import('#/tour/runner');
  runner.initTour();
  destroyRunner = runner.destroyTour;
}

describe('tour runner', () => {
  beforeEach(() => {
    sessionStorage.clear();
    document.body.innerHTML = '';
    window.history.replaceState({}, '', '/');
    // jsdom has no layout: make every element count as visible.
    vi.spyOn(Element.prototype, 'getClientRects').mockReturnValue([
      new DOMRect(10, 10, 120, 40),
    ] as unknown as DOMRectList);
  });

  afterEach(() => {
    destroyRunner?.();
    destroyRunner = null;
    document.getElementById(ROOT_ID)?.remove();
    vi.unstubAllGlobals();
    vi.restoreAllMocks();
    vi.useRealTimers();
  });

  it('stores state and renders the first step on lightning:start-tour', async () => {
    document.body.innerHTML = `
      <nav id="side-menu">
        <a class="menu-item" href="/projects/${PROJECT_ID}/history">History</a>
      </nav>`;
    mockAppMapFetch();
    await initTour();

    startTour({ page: 'project_history', params: { project_id: PROJECT_ID } });

    await vi.waitFor(() => {
      expect(document.getElementById(ROOT_ID)).toBeTruthy();
    });

    const state = JSON.parse(sessionStorage.getItem(STORAGE_KEY) ?? 'null') as {
      index: number;
      steps: unknown[];
      destinationPath: string;
    };
    expect(state).toMatchObject({
      index: 0,
      destinationPath: `/projects/${PROJECT_ID}/history`,
    });
    expect(state.steps).toHaveLength(1);

    const root = document.getElementById(ROOT_ID)!;
    expect(root.textContent).toContain('Go to History');
    expect(root.textContent).toContain('1 of 1');
    expect(root.textContent).toContain('Exit tour');
  });

  it('cleans up the UI and the stored state on Escape', async () => {
    document.body.innerHTML = `
      <nav id="side-menu">
        <a class="menu-item" href="/projects/${PROJECT_ID}/history">History</a>
      </nav>`;
    const fetchMock = mockAppMapFetch();
    await initTour();

    startTour({ page: 'project_history', params: { project_id: PROJECT_ID } });
    await vi.waitFor(() => {
      expect(document.getElementById(ROOT_ID)).toBeTruthy();
    });

    document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape' }));

    expect(document.getElementById(ROOT_ID)).toBeNull();
    expect(sessionStorage.getItem(STORAGE_KEY)).toBeNull();
    expect(
      tourEvents(fetchMock).filter(e => e.event === 'tour_abandoned')
    ).toEqual([
      { event: 'tour_abandoned', reason: 'escape', page: 'project_history' },
    ]);
  });

  it('advances to the next step when the spotlighted element is clicked', async () => {
    document.body.innerHTML = `
      <button id="user-menu-trigger">Me</button>
      <div role="menu">
        <a role="menuitem" href="/credentials">Credentials</a>
      </div>`;
    mockAppMapFetch();
    await initTour();

    startTour({ page: 'credentials', params: {} });
    await vi.waitFor(() => {
      expect(document.getElementById(ROOT_ID)?.textContent).toContain(
        'Open your user menu'
      );
    });

    document.getElementById('user-menu-trigger')!.click();

    await vi.waitFor(() => {
      expect(document.getElementById(ROOT_ID)?.textContent).toContain(
        'Go to Credentials'
      );
    });
    const state = JSON.parse(sessionStorage.getItem(STORAGE_KEY) ?? 'null') as {
      index: number;
    };
    expect(state.index).toBe(1);
  });

  it('aborts gracefully when the app map endpoint fails', async () => {
    const warn = vi.spyOn(console, 'warn').mockImplementation(() => {});
    mockAppMapFetch(500);
    await initTour();

    startTour({ page: 'project_history', params: { project_id: PROJECT_ID } });

    await vi.waitFor(() => {
      expect(warn).toHaveBeenCalledWith(
        expect.stringContaining('responded with 500')
      );
    });
    expect(sessionStorage.getItem(STORAGE_KEY)).toBeNull();
    // No tour starts, but the user sees a notice instead of a dead button.
    expect(document.getElementById(ROOT_ID)?.textContent).toContain(
      "Couldn't start a guided tour for that page."
    );
  });

  it('shows the arrival card when the user is already on an unaddressable page', async () => {
    window.history.replaceState({}, '', '/projects/p1/w/wf-1');
    const fetchMock = mockAppMapFetch();
    await initTour();

    startTour({ page: 'workflow_edit', params: { project_id: 'p1' } });

    await vi.waitFor(() => {
      expect(document.getElementById(ROOT_ID)?.textContent).toContain(
        "You've arrived: Workflow editor"
      );
    });
    expect(sessionStorage.getItem(STORAGE_KEY)).toBeNull();
    expect(
      tourEvents(fetchMock).filter(e => e.event === 'tour_completed')
    ).toEqual([{ event: 'tour_completed', page: 'workflow_edit' }]);
  });

  it('emits tour_started once and never again on resume', async () => {
    document.body.innerHTML = `
      <nav id="side-menu">
        <a class="menu-item" href="/projects/${PROJECT_ID}/history">History</a>
      </nav>`;
    const fetchMock = mockAppMapFetch();
    await initTour();

    startTour({ page: 'project_history', params: { project_id: PROJECT_ID } });
    await vi.waitFor(() => {
      expect(document.getElementById(ROOT_ID)).toBeTruthy();
    });

    const started = () =>
      tourEvents(fetchMock).filter(e => e.event === 'tour_started');
    expect(started()).toEqual([
      { event: 'tour_started', page: 'project_history', steps_total: 1 },
    ]);

    // A LiveView navigation resumes the persisted tour: no re-emission.
    window.dispatchEvent(new Event('phx:page-loading-stop'));
    await vi.waitFor(() => {
      expect(document.getElementById(ROOT_ID)?.textContent).toContain(
        'Go to History'
      );
    });
    expect(started()).toHaveLength(1);
  });

  it('renders an auto-dismissing notice when the tour cannot start', async () => {
    const warn = vi.spyOn(console, 'warn').mockImplementation(() => {});
    mockAppMapFetch();
    await initTour();
    vi.useFakeTimers();

    // Location is "/", which does not match /projects/:project_id/w/:id.
    startTour({ page: 'workflow_edit', params: { project_id: 'p1' } });

    await vi.waitFor(() => {
      expect(document.getElementById(ROOT_ID)?.textContent).toContain(
        "Couldn't start a guided tour for Workflow editor."
      );
    });
    expect(warn).toHaveBeenCalled();

    await vi.advanceTimersByTimeAsync(6500);
    expect(document.getElementById(ROOT_ID)).toBeNull();
  });

  describe('element spotlights', () => {
    it('spotlights the anchor with a card and Done button, persisting nothing', async () => {
      window.history.replaceState({}, '', '/projects/p1/w/wf-1');
      document.body.innerHTML = `
        <div data-tour-anchor="credential-picker">Credential</div>`;
      const fetchMock = mockAppMapFetch();
      await initTour();

      startTour({
        page: 'workflow_edit',
        element: 'credential-picker',
        params: { project_id: 'p1' },
      });

      await vi.waitFor(() => {
        expect(document.getElementById(ROOT_ID)?.textContent).toContain(
          'Credential picker'
        );
      });
      const root = document.getElementById(ROOT_ID)!;
      expect(root.textContent).toContain('saved credential');
      expect(root.textContent).toContain('Done');
      // Target already on screen: no prerequisite step, straight to the card.
      expect(root.textContent).not.toContain('Click here');
      expect(sessionStorage.getItem(STORAGE_KEY)).toBeNull();
      // The dimming ring is decoration only.
      expect(root.querySelector('[aria-hidden="true"]')).toBeTruthy();

      const context = { page: 'workflow_edit', element: 'credential-picker' };
      expect(
        tourEvents(fetchMock).filter(e => e.event !== 'button_shown')
      ).toEqual([
        { event: 'tour_started', ...context, steps_total: 2 },
        { event: 'spotlight_shown', ...context },
        { event: 'tour_completed', ...context },
      ]);

      // Done dismisses the spotlight — a completion, not an abandonment.
      [...root.querySelectorAll('button')]
        .find(b => b.textContent === 'Done')!
        .click();
      expect(document.getElementById(ROOT_ID)).toBeNull();
      expect(
        tourEvents(fetchMock).filter(e => e.event === 'tour_abandoned')
      ).toEqual([]);
    });

    it('renders an accessible dialog card and restores focus on Done', async () => {
      window.history.replaceState({}, '', '/projects/p1/w/wf-1');
      document.body.innerHTML = `
        <button id="origin">origin</button>
        <div data-tour-anchor="run-button">Run</div>`;
      document.getElementById('origin')!.focus();
      mockAppMapFetch();
      await initTour();

      startTour({
        page: 'workflow_edit',
        element: 'run-button',
        params: { project_id: 'p1' },
      });
      await vi.waitFor(() => {
        expect(document.querySelector('[role="dialog"]')).toBeTruthy();
      });

      const dialog = document.querySelector('[role="dialog"]')!;
      // Non-modal by design: the page stays interactive.
      expect(dialog.getAttribute('aria-modal')).toBeNull();
      const titleId = dialog.getAttribute('aria-labelledby')!;
      const bodyId = dialog.getAttribute('aria-describedby')!;
      expect(document.getElementById(titleId)?.textContent).toBe('Run button');
      expect(document.getElementById(bodyId)?.textContent).toContain(
        'Run the workflow'
      );

      const done = [...dialog.querySelectorAll('button')].find(
        b => b.textContent === 'Done'
      )!;
      expect(document.activeElement).toBe(done);

      done.click();
      expect(document.getElementById(ROOT_ID)).toBeNull();
      expect(document.activeElement).toBe(document.getElementById('origin'));
    });

    it('walks the requires chain from the visible prerequisite to the target', async () => {
      window.history.replaceState({}, '', '/projects/p1/w/wf-1');
      // Only the prerequisite (a canvas node) is on screen; the picker lives
      // in the panel that clicking the node opens.
      document.body.innerHTML = `
        <div data-tour-anchor="canvas-step">Step A</div>
        <div data-tour-anchor="canvas-step">Step B</div>`;
      mockAppMapFetch();
      await initTour();

      startTour({
        page: 'workflow_edit',
        element: 'credential-picker',
        params: { project_id: 'p1' },
      });

      await vi.waitFor(() => {
        expect(document.getElementById(ROOT_ID)?.textContent).toContain(
          'Click here: Workflow step'
        );
      });
      const root = document.getElementById(ROOT_ID)!;
      expect(root.textContent).toContain('1 of 2');
      expect(root.textContent).not.toContain('Done');

      // Clicking the node "opens" the panel, revealing the picker anchor.
      (
        document.querySelector(
          '[data-tour-anchor="canvas-step"]'
        ) as HTMLElement
      ).click();
      const picker = document.createElement('div');
      picker.setAttribute('data-tour-anchor', 'credential-picker');
      picker.textContent = 'Picker';
      document.body.appendChild(picker);

      await vi.waitFor(() => {
        expect(document.getElementById(ROOT_ID)?.textContent).toContain(
          'Credential picker'
        );
      });
      expect(document.getElementById(ROOT_ID)!.textContent).toContain('Done');
      expect(sessionStorage.getItem(STORAGE_KEY)).toBeNull();
    });

    it('cleans up mid-chain on Escape', async () => {
      window.history.replaceState({}, '', '/projects/p1/w/wf-1');
      document.body.innerHTML = `
        <div data-tour-anchor="canvas-step">Step</div>`;
      mockAppMapFetch();
      await initTour();

      startTour({
        page: 'workflow_edit',
        element: 'credential-picker',
        params: { project_id: 'p1' },
      });
      await vi.waitFor(() => {
        expect(document.getElementById(ROOT_ID)?.textContent).toContain(
          'Click here: Workflow step'
        );
      });

      document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape' }));

      expect(document.getElementById(ROOT_ID)).toBeNull();
      expect(sessionStorage.getItem(STORAGE_KEY)).toBeNull();
    });

    it("shows the element's hint when the anchor never appears", async () => {
      window.history.replaceState({}, '', '/projects/p1/w/wf-1');
      const fetchMock = mockAppMapFetch();
      await initTour();
      vi.useFakeTimers();

      startTour({
        page: 'workflow_edit',
        element: 'credential-picker',
        params: { project_id: 'p1' },
      });

      await vi.advanceTimersByTimeAsync(0); // fetch + plan settle
      await vi.advanceTimersByTimeAsync(4500); // past the 4s spotlight window

      const notice = document.querySelector('[role="status"]');
      expect(notice?.textContent).toContain(
        'Select a step on the canvas to open its configuration panel first.'
      );

      const context = { page: 'workflow_edit', element: 'credential-picker' };
      expect(
        tourEvents(fetchMock).filter(e => e.event !== 'tour_started')
      ).toEqual([
        { event: 'tour_abandoned', reason: 'timeout', ...context },
        { event: 'notice_shown', reason: 'hint', ...context },
      ]);
    });

    it('falls back to a generic notice when the element has no hint', async () => {
      window.history.replaceState({}, '', '/projects/p1/w/wf-1');
      mockAppMapFetch();
      await initTour();
      vi.useFakeTimers();

      startTour({
        page: 'workflow_edit',
        element: 'run-button',
        params: { project_id: 'p1' },
      });

      await vi.advanceTimersByTimeAsync(0);
      await vi.advanceTimersByTimeAsync(4500);

      expect(document.getElementById(ROOT_ID)?.textContent).toContain(
        "Couldn't find that control on this page."
      );
    });

    it('shows a wrong-page notice when asked from another page', async () => {
      // Location is "/", which is not the workflow editor.
      const fetchMock = mockAppMapFetch();
      await initTour();

      startTour({
        page: 'workflow_edit',
        element: 'credential-picker',
        params: { project_id: 'p1' },
      });

      await vi.waitFor(() => {
        expect(document.getElementById(ROOT_ID)?.textContent).toContain(
          'That guidance is for the Workflow editor page — ask again from there.'
        );
      });
      expect(sessionStorage.getItem(STORAGE_KEY)).toBeNull();
      expect(tourEvents(fetchMock)).toEqual([
        {
          event: 'notice_shown',
          reason: 'wrong_page',
          page: 'workflow_edit',
          element: 'credential-picker',
        },
      ]);
    });
  });

  describe('grand tours', () => {
    const sideMenu = `
      <nav id="side-menu">
        <a href="/projects/${PROJECT_ID}/w">Workflows</a>
        <a href="/projects/${PROJECT_ID}/history">History</a>
      </nav>`;

    it('runs stops sequentially with a Next stop button, persisting across navigation', async () => {
      window.history.replaceState({}, '', `/projects/${PROJECT_ID}/w`);
      document.body.innerHTML = sideMenu;
      const fetchMock = mockAppMapFetch();
      await initTour();

      startTour({
        tour: ['project_workflows', 'project_history'],
        params: { project_id: PROJECT_ID },
      });

      // Stop 1 is the current page: its arrival card shows with Next stop.
      const root = () => document.getElementById(ROOT_ID);
      await vi.waitFor(() => {
        expect(root()?.textContent).toContain("You've arrived: Workflows");
      });
      expect(root()!.textContent).toContain('Next stop (2 of 2) →');
      expect(
        tourEvents(fetchMock).filter(e => e.event === 'tour_started')
      ).toEqual([
        {
          event: 'tour_started',
          page: 'project_workflows,project_history',
          steps_total: 2,
        },
      ]);
      // A mid-tour arrival is not a completion.
      expect(
        tourEvents(fetchMock).filter(e => e.event === 'tour_completed')
      ).toEqual([]);

      [...root()!.querySelectorAll('button')]
        .find(b => b.textContent?.startsWith('Next stop'))!
        .click();

      await vi.waitFor(() => {
        expect(root()?.textContent).toContain('Go to History');
      });
      const state = JSON.parse(
        sessionStorage.getItem(STORAGE_KEY) ?? 'null'
      ) as { stops: string[]; stopIndex: number; page: string };
      expect(state).toMatchObject({
        stops: ['project_workflows', 'project_history'],
        stopIndex: 1,
        page: 'project_history',
      });

      // The user clicks the sidebar link; "LiveView" navigates.
      document
        .querySelector<HTMLElement>(
          `#side-menu a[href="/projects/${PROJECT_ID}/history"]`
        )!
        .click();
      window.history.replaceState({}, '', `/projects/${PROJECT_ID}/history`);
      window.dispatchEvent(new Event('phx:page-loading-stop'));

      await vi.waitFor(() => {
        expect(root()?.textContent).toContain("You've arrived: History");
      });
      expect(root()!.textContent).toContain('Done');
      expect(root()!.textContent).not.toContain('Next stop');
      expect(
        tourEvents(fetchMock).filter(e => e.event === 'tour_completed')
      ).toEqual([{ event: 'tour_completed', page: 'project_history' }]);
      expect(sessionStorage.getItem(STORAGE_KEY)).toBeNull();
    });

    it('ends the whole tour on Escape at a stop arrival card', async () => {
      window.history.replaceState({}, '', `/projects/${PROJECT_ID}/w`);
      document.body.innerHTML = sideMenu;
      const fetchMock = mockAppMapFetch();
      await initTour();

      startTour({
        tour: ['project_workflows', 'project_history'],
        params: { project_id: PROJECT_ID },
      });
      await vi.waitFor(() => {
        expect(document.getElementById(ROOT_ID)?.textContent).toContain(
          'Next stop'
        );
      });

      document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape' }));

      expect(document.getElementById(ROOT_ID)).toBeNull();
      expect(sessionStorage.getItem(STORAGE_KEY)).toBeNull();
      expect(
        tourEvents(fetchMock).filter(e => e.event === 'tour_abandoned')
      ).toEqual([
        {
          event: 'tour_abandoned',
          reason: 'escape',
          page: 'project_workflows',
        },
      ]);
    });

    it('drops untourable stops and tours the rest', async () => {
      window.history.replaceState({}, '', `/projects/${PROJECT_ID}/w`);
      document.body.innerHTML = sideMenu;
      const fetchMock = mockAppMapFetch();
      await initTour();

      startTour({
        tour: ['bogus_page', 'project_workflows', 'project_history'],
        params: { project_id: PROJECT_ID },
      });

      await vi.waitFor(() => {
        expect(document.getElementById(ROOT_ID)?.textContent).toContain(
          'Next stop (2 of 2) →'
        );
      });
      expect(
        tourEvents(fetchMock).filter(e => e.event === 'tour_started')
      ).toEqual([
        {
          event: 'tour_started',
          page: 'project_workflows,project_history',
          steps_total: 2,
        },
      ]);
    });

    it('falls back to a single-page tour when only one stop is valid', async () => {
      document.body.innerHTML = sideMenu;
      const fetchMock = mockAppMapFetch();
      await initTour();

      startTour({
        tour: ['bogus_page', 'project_history'],
        params: { project_id: PROJECT_ID },
      });

      await vi.waitFor(() => {
        expect(document.getElementById(ROOT_ID)?.textContent).toContain(
          'Go to History'
        );
      });
      expect(
        tourEvents(fetchMock).filter(e => e.event === 'tour_started')
      ).toEqual([
        { event: 'tour_started', page: 'project_history', steps_total: 1 },
      ]);
    });
  });

  describe('autopilot', () => {
    it('narrates with Opening cards and clicks each step after the pause', async () => {
      document.body.innerHTML = `
        <button id="user-menu-trigger">Me</button>
        <div role="menu">
          <a role="menuitem" href="/credentials">Credentials</a>
        </div>`;
      mockAppMapFetch();
      await initTour();
      vi.useFakeTimers();

      startTour({ page: 'credentials', params: {}, autopilot: true });
      await vi.advanceTimersByTimeAsync(0);

      const root = () => document.getElementById(ROOT_ID);
      expect(root()?.textContent).toContain('Opening: your user menu');

      // Nothing happens until the comprehension pause elapses…
      await vi.advanceTimersByTimeAsync(1000);
      expect(root()?.textContent).toContain('Opening: your user menu');

      // …then autopilot clicks the trigger and the next step renders.
      await vi.advanceTimersByTimeAsync(300);
      expect(root()?.textContent).toContain('Opening: Credentials');
      const state = JSON.parse(
        sessionStorage.getItem(STORAGE_KEY) ?? 'null'
      ) as { index: number; autopilot?: boolean };
      expect(state).toMatchObject({ index: 1, autopilot: true });
    });

    it('Escape aborts instantly, cancelling the pending click', async () => {
      document.body.innerHTML = `
        <button id="user-menu-trigger">Me</button>
        <div role="menu">
          <a role="menuitem" href="/credentials">Credentials</a>
        </div>`;
      mockAppMapFetch();
      await initTour();
      vi.useFakeTimers();

      startTour({ page: 'credentials', params: {}, autopilot: true });
      await vi.advanceTimersByTimeAsync(0);
      expect(document.getElementById(ROOT_ID)?.textContent).toContain(
        'Opening: your user menu'
      );

      const clicks = vi.fn();
      document
        .getElementById('user-menu-trigger')!
        .addEventListener('click', clicks);
      document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape' }));

      await vi.advanceTimersByTimeAsync(5000);
      expect(clicks).not.toHaveBeenCalled();
      expect(document.getElementById(ROOT_ID)).toBeNull();
    });

    it('auto-clicks chain prerequisites but never the terminal target', async () => {
      window.history.replaceState({}, '', '/projects/p1/w/wf-1');
      document.body.innerHTML = `
        <div data-tour-anchor="canvas-step">Step</div>`;
      mockAppMapFetch();
      await initTour();
      vi.useFakeTimers();

      startTour({
        page: 'workflow_edit',
        element: 'credential-picker',
        params: { project_id: 'p1' },
        autopilot: true,
      });
      await vi.advanceTimersByTimeAsync(0);

      const root = () => document.getElementById(ROOT_ID);
      expect(root()?.textContent).toContain('Opening: Workflow step');

      // Reveal the picker (as clicking the node would) before autopilot acts.
      const picker = document.createElement('div');
      picker.setAttribute('data-tour-anchor', 'credential-picker');
      document.body.appendChild(picker);
      const pickerClicks = vi.fn();
      picker.addEventListener('click', pickerClicks);

      await vi.advanceTimersByTimeAsync(1300); // autopilot clicks canvas-step
      expect(root()?.textContent).toContain('Credential picker');
      expect(root()?.textContent).toContain('Done');

      // The terminal card is the end state: it stays, unclicked.
      await vi.advanceTimersByTimeAsync(5000);
      expect(pickerClicks).not.toHaveBeenCalled();
      expect(root()?.textContent).toContain('Credential picker');
    });
  });

  it('discards stale state on resume', async () => {
    sessionStorage.setItem(
      STORAGE_KEY,
      JSON.stringify({
        steps: [],
        index: 0,
        arrival: { label: 'History', description: 'x' },
        destinationPath: '/somewhere',
        startedAt: Date.now() - 11 * 60 * 1000,
      })
    );
    mockAppMapFetch();
    await initTour();

    expect(sessionStorage.getItem(STORAGE_KEY)).toBeNull();
    expect(document.getElementById(ROOT_ID)).toBeNull();
  });
});
