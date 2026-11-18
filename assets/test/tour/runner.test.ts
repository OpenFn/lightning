import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import { appMapPages } from './fixtures';

const PROJECT_ID = 'b1a2c3d4-0000-0000-0000-000000000002';
const STORAGE_KEY = 'lightning:tour';
const ROOT_ID = 'lightning-tour-root';

function mockAppMapFetch(status = 200): void {
  vi.stubGlobal(
    'fetch',
    vi.fn().mockResolvedValue({
      ok: status === 200,
      status,
      json: () => Promise.resolve({ pages: appMapPages }),
    } as Response)
  );
}

function startTour(detail: unknown): void {
  document.dispatchEvent(new CustomEvent('lightning:start-tour', { detail }));
}

async function initTour(): Promise<void> {
  // The runner guards against double initialisation with module state, so get
  // a fresh module (and a fresh guard) for every test.
  vi.resetModules();
  const { initTour: init } = await import('#/tour/runner');
  init();
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
    mockAppMapFetch();
    await initTour();

    startTour({ page: 'project_history', params: { project_id: PROJECT_ID } });
    await vi.waitFor(() => {
      expect(document.getElementById(ROOT_ID)).toBeTruthy();
    });

    document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape' }));

    expect(document.getElementById(ROOT_ID)).toBeNull();
    expect(sessionStorage.getItem(STORAGE_KEY)).toBeNull();
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
    mockAppMapFetch();
    await initTour();

    startTour({ page: 'workflow_edit', params: { project_id: 'p1' } });

    await vi.waitFor(() => {
      expect(document.getElementById(ROOT_ID)?.textContent).toContain(
        "You've arrived: Workflow editor"
      );
    });
    expect(sessionStorage.getItem(STORAGE_KEY)).toBeNull();
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
