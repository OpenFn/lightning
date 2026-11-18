import { describe, expect, it } from 'vitest';

import { buildTourPlan, matchesPathPattern } from '#/tour/plan';
import type { AppMapPage, Step, TourPlan } from '#/tour/plan';

import { appMapPages } from './fixtures';

const PROJECT_ID = 'b1a2c3d4-0000-0000-0000-000000000001';

function expectSteps(plan: TourPlan): {
  steps: Step[];
  destinationPath: string;
  destinationHash?: string;
  arrival: { label: string; description: string; tabLabel?: string };
} {
  if (!('steps' in plan)) {
    throw new Error(`expected a steps plan, got ${JSON.stringify(plan)}`);
  }
  return plan;
}

describe('matchesPathPattern', () => {
  it('matches :param segments against any non-empty segment', () => {
    expect(
      matchesPathPattern('/projects/:project_id/w/:id', '/projects/abc/w/xyz')
    ).toBe(true);
  });

  it('matches literal patterns exactly', () => {
    expect(matchesPathPattern('/credentials', '/credentials')).toBe(true);
    expect(matchesPathPattern('/credentials', '/profile')).toBe(false);
  });

  it('rejects paths with fewer segments than the pattern', () => {
    expect(
      matchesPathPattern('/projects/:project_id/w/:id', '/projects/abc/w')
    ).toBe(false);
  });

  it('rejects paths with more segments than the pattern', () => {
    expect(
      matchesPathPattern(
        '/projects/:project_id/w/:id',
        '/projects/abc/w/xyz/health'
      )
    ).toBe(false);
  });

  it('rejects literal segment mismatches around params', () => {
    expect(
      matchesPathPattern(
        '/projects/:project_id/w/:id',
        '/projects/abc/history/xyz'
      )
    ).toBe(false);
  });

  it('tolerates trailing slashes', () => {
    expect(
      matchesPathPattern('/projects/:project_id/w', '/projects/abc/w/')
    ).toBe(true);
  });
});

describe('buildTourPlan', () => {
  describe('project section', () => {
    it('plans a single sidebar click for a direct sidebar page', () => {
      const plan = expectSteps(
        buildTourPlan(appMapPages, {
          page: 'project_history',
          params: { project_id: PROJECT_ID },
        })
      );

      expect(plan.steps).toEqual([
        {
          type: 'element',
          selector: `#side-menu a[href="/projects/${PROJECT_ID}/history"]`,
          title: 'Go to History',
          body: 'Click "History" in the sidebar.',
          label: 'History',
          advanceOn: 'click',
          expectNavigation: true,
        },
      ]);
      expect(plan.destinationPath).toBe(`/projects/${PROJECT_ID}/history`);
      expect(plan.destinationHash).toBeUndefined();
      expect(plan.arrival).toEqual({
        label: 'History',
        description: expect.stringContaining('Search and filter'),
      });
    });

    it('appends a tab step when a tab is requested', () => {
      const plan = expectSteps(
        buildTourPlan(appMapPages, {
          page: 'project_settings',
          tab: 'vcs',
          params: { project_id: PROJECT_ID },
        })
      );

      expect(plan.steps).toHaveLength(2);
      expect(plan.steps[0]).toMatchObject({
        type: 'element',
        selector: `#side-menu a[href="/projects/${PROJECT_ID}/settings"]`,
        advanceOn: 'click',
        expectNavigation: true,
      });
      expect(plan.steps[1]).toEqual({
        type: 'element',
        selector: '#vcs-tab',
        title: 'Open the "Sync to GitHub" tab',
        body: 'Click the "Sync to GitHub" tab.',
        label: 'Sync to GitHub',
        advanceOn: 'hash:vcs',
        expectNavigation: false,
      });
      expect(plan.destinationHash).toBe('vcs');
      expect(plan.arrival).toEqual({
        label: 'Settings',
        description: expect.stringContaining('GitHub repository'),
        tabLabel: 'Sync to GitHub',
      });
    });

    it('handles tab hashes containing a dash', () => {
      const plan = expectSteps(
        buildTourPlan(appMapPages, {
          page: 'project_settings',
          tab: 'data-storage',
          params: { project_id: PROJECT_ID },
        })
      );

      expect(plan.steps[1]).toMatchObject({
        selector: '#data-storage-tab',
        advanceOn: 'hash:data-storage',
      });
    });

    it('plans sidebar click + navigate hop for a nested path (longest prefix)', () => {
      const plan = expectSteps(
        buildTourPlan(appMapPages, {
          page: 'channel_logs',
          params: { project_id: PROJECT_ID },
        })
      );

      expect(plan.steps).toEqual([
        expect.objectContaining({
          type: 'element',
          selector: `#side-menu a[href="/projects/${PROJECT_ID}/history"]`,
          expectNavigation: true,
        }),
        {
          type: 'navigate',
          path: `/projects/${PROJECT_ID}/history/channels`,
        },
      ]);
      expect(plan.destinationPath).toBe(
        `/projects/${PROJECT_ID}/history/channels`
      );
    });

    it('routes /channels/new through the Channels sidebar item, not History', () => {
      const plan = expectSteps(
        buildTourPlan(appMapPages, {
          page: 'channel_new',
          params: { project_id: PROJECT_ID },
        })
      );

      expect(plan.steps[0]).toMatchObject({
        selector: `#side-menu a[href="/projects/${PROJECT_ID}/channels"]`,
      });
      expect(plan.steps[1]).toEqual({
        type: 'navigate',
        path: `/projects/${PROJECT_ID}/channels/new`,
      });
    });

    it('hops from Settings to a nested settings page', () => {
      const plan = expectSteps(
        buildTourPlan(appMapPages, {
          page: 'project_delete',
          params: { project_id: PROJECT_ID },
        })
      );

      expect(plan.steps.map(s => s.type)).toEqual(['element', 'navigate']);
      expect(plan.steps[1]).toEqual({
        type: 'navigate',
        path: `/projects/${PROJECT_ID}/settings/delete`,
      });
    });
  });

  describe('user section', () => {
    it('plans the two user-menu steps', () => {
      const plan = expectSteps(
        buildTourPlan(appMapPages, { page: 'credentials', params: {} })
      );

      expect(plan.steps).toEqual([
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
          selector: '[role="menu"] a[href="/credentials"]',
          title: 'Go to Credentials',
          body: 'Click "Credentials" in the menu.',
          label: 'Credentials',
          advanceOn: 'click',
          expectNavigation: true,
        },
      ]);
      expect(plan.destinationPath).toBe('/credentials');
    });

    it('targets the exact menu href for API tokens', () => {
      const plan = expectSteps(
        buildTourPlan(appMapPages, { page: 'api_tokens', params: {} })
      );

      expect(plan.steps[1]).toMatchObject({
        selector: '[role="menu"] a[href="/profile/tokens"]',
      });
    });

    it('falls back for user pages that are not in the user menu', () => {
      const plan = buildTourPlan(appMapPages, {
        page: 'backup_codes',
        params: {},
      });

      expect(plan).toEqual({
        fallbackPath: '/profile/auth/backup_codes',
        arrival: {
          label: 'Backup codes',
          description: expect.stringContaining('one-time backup codes'),
        },
      });
    });
  });

  describe('admin and auth sections', () => {
    it('returns a fallback path for admin pages', () => {
      const plan = buildTourPlan(appMapPages, {
        page: 'admin_users',
        params: {},
      });

      expect(plan).toEqual({
        fallbackPath: '/settings/users',
        arrival: {
          label: 'Users',
          description: expect.stringContaining('Superuser list'),
        },
      });
    });

    it('returns a fallback path for auth pages', () => {
      const plan = buildTourPlan(appMapPages, { page: 'login', params: {} });

      expect(plan).toEqual({
        fallbackPath: '/users/log_in',
        arrival: expect.objectContaining({ label: 'Log in' }),
      });
    });
  });

  describe('already-here detection', () => {
    it('returns alreadyHere when the current path matches an unresolvable pattern', () => {
      const plan = buildTourPlan(
        appMapPages,
        { page: 'workflow_edit', params: { project_id: PROJECT_ID } },
        { currentPath: `/projects/${PROJECT_ID}/w/wf-123` }
      );

      expect(plan).toEqual({
        alreadyHere: true,
        arrival: {
          label: 'Workflow editor',
          description: expect.stringContaining('collaborative editor'),
        },
      });
    });

    it('does not claim alreadyHere for a different project', () => {
      const plan = buildTourPlan(
        appMapPages,
        { page: 'workflow_edit', params: { project_id: PROJECT_ID } },
        { currentPath: '/projects/other-project/w/wf-123' }
      );

      expect(plan).toEqual({
        error: `Cannot resolve ":id" in path "/projects/:project_id/w/:id"`,
      });
    });

    it('still errors when the current path does not match the pattern', () => {
      const plan = buildTourPlan(
        appMapPages,
        { page: 'workflow_edit', params: { project_id: PROJECT_ID } },
        { currentPath: `/projects/${PROJECT_ID}/history` }
      );

      expect(plan).toEqual({
        error: `Cannot resolve ":id" in path "/projects/:project_id/w/:id"`,
      });
    });

    it('matches on the raw pattern when no params are supplied at all', () => {
      const plan = buildTourPlan(
        appMapPages,
        { page: 'workflow_edit', params: {} },
        { currentPath: '/projects/abc/w/wf-123' }
      );

      expect(plan).toEqual({
        alreadyHere: true,
        arrival: expect.objectContaining({ label: 'Workflow editor' }),
      });
    });

    it('does not affect fully-resolvable plans', () => {
      const plan = buildTourPlan(
        appMapPages,
        { page: 'project_history', params: { project_id: PROJECT_ID } },
        { currentPath: `/projects/${PROJECT_ID}/history` }
      );

      expect('steps' in plan).toBe(true);
    });
  });

  describe('element requests', () => {
    const onEditorPage = {
      currentPath: `/projects/${PROJECT_ID}/w/wf-123`,
    };

    it('returns a spotlight when the current path matches the page', () => {
      const plan = buildTourPlan(
        appMapPages,
        {
          page: 'workflow_edit',
          element: 'credential-picker',
          params: { project_id: PROJECT_ID },
        },
        onEditorPage
      );

      expect(plan).toEqual({
        spotlight: {
          chain: [
            {
              selector: '[data-tour-anchor="canvas-step"]',
              label: 'Workflow step',
              description: expect.stringContaining('job step node'),
            },
          ],
          target: {
            selector: '[data-tour-anchor="credential-picker"]',
            label: 'Credential picker',
            description: expect.stringContaining('saved credential'),
            hint: 'Select a step on the canvas to open its configuration panel first.',
          },
        },
      });
    });

    it('omits hint and plans an empty chain when the element has neither', () => {
      const plan = buildTourPlan(
        appMapPages,
        { page: 'workflow_edit', element: 'run-button', params: {} },
        onEditorPage
      );

      expect(plan).toEqual({
        spotlight: {
          chain: [],
          target: {
            selector: '[data-tour-anchor="run-button"]',
            label: 'Run button',
            description: expect.stringContaining('Run the workflow'),
          },
        },
      });
      expect(
        'hint' in (plan as { spotlight: { target: object } }).spotlight.target
      ).toBe(false);
    });

    it('walks nested requires into an outermost-first chain', () => {
      const plan = buildTourPlan(
        appMapPages,
        { page: 'workflow_edit', element: 'docs-tab', params: {} },
        onEditorPage
      );

      expect(plan).toEqual({
        spotlight: {
          chain: [
            expect.objectContaining({
              selector: '[data-tour-anchor="canvas-step"]',
            }),
            expect.objectContaining({
              selector: '[data-tour-anchor="open-editor"]',
            }),
          ],
          target: expect.objectContaining({
            selector: '[data-tour-anchor="docs-tab"]',
            label: 'Docs tab',
          }),
        },
      });
    });

    describe('requires-chain guards', () => {
      const guardPage: AppMapPage = {
        id: 'guard_page',
        label: 'Guard page',
        module: 'X',
        path: '/guard',
        section: 'user',
        description: 'Inline fixture for requires-chain edge cases.',
        elements: [
          { id: 'a', label: 'A', description: 'a.', requires: 'b' },
          { id: 'b', label: 'B', description: 'b.', requires: 'a' },
          { id: 'ghostly', label: 'G', description: 'g.', requires: 'ghost' },
          { id: 'd1', label: 'D1', description: 'd.', requires: 'd2' },
          { id: 'd2', label: 'D2', description: 'd.', requires: 'd3' },
          { id: 'd3', label: 'D3', description: 'd.', requires: 'd4' },
          { id: 'd4', label: 'D4', description: 'd.', requires: 'd5' },
          { id: 'd5', label: 'D5', description: 'd.', requires: 'd6' },
          { id: 'd6', label: 'D6', description: 'd.' },
        ],
      };

      const chainOf = (plan: TourPlan): string[] => {
        if (!('spotlight' in plan)) {
          throw new Error(`expected a spotlight, got ${JSON.stringify(plan)}`);
        }
        return plan.spotlight.chain.map(e => e.selector);
      };

      const guardRequest = (element: string): TourPlan =>
        buildTourPlan(
          [guardPage],
          { page: 'guard_page', element, params: {} },
          { currentPath: '/guard' }
        );

      it('stops a cyclic requires chain instead of looping', () => {
        expect(chainOf(guardRequest('a'))).toEqual(['[data-tour-anchor="b"]']);
      });

      it('treats an unknown requires id as absent', () => {
        expect(chainOf(guardRequest('ghostly'))).toEqual([]);
      });

      it('caps the chain depth', () => {
        expect(chainOf(guardRequest('d1'))).toEqual([
          '[data-tour-anchor="d5"]',
          '[data-tour-anchor="d4"]',
          '[data-tour-anchor="d3"]',
          '[data-tour-anchor="d2"]',
        ]);
      });
    });

    it('errors on an unknown element id', () => {
      const plan = buildTourPlan(
        appMapPages,
        { page: 'workflow_edit', element: 'nope', params: {} },
        onEditorPage
      );

      expect(plan).toEqual({
        error: 'Unknown element "nope" on page "workflow_edit"',
      });
    });

    it('errors on an element request for a page without elements', () => {
      const plan = buildTourPlan(
        appMapPages,
        {
          page: 'project_history',
          element: 'credential-picker',
          params: { project_id: PROJECT_ID },
        },
        { currentPath: `/projects/${PROJECT_ID}/history` }
      );

      expect(plan).toEqual({
        error: 'Unknown element "credential-picker" on page "project_history"',
      });
    });

    it('returns wrongPage when the current path does not match the page', () => {
      const plan = buildTourPlan(
        appMapPages,
        {
          page: 'workflow_edit',
          element: 'credential-picker',
          params: { project_id: PROJECT_ID },
        },
        { currentPath: `/projects/${PROJECT_ID}/history` }
      );

      expect(plan).toEqual({ wrongPage: true, pageLabel: 'Workflow editor' });
    });

    it('returns wrongPage for a matching path shape in another project', () => {
      const plan = buildTourPlan(
        appMapPages,
        {
          page: 'workflow_edit',
          element: 'credential-picker',
          params: { project_id: PROJECT_ID },
        },
        { currentPath: '/projects/other-project/w/wf-123' }
      );

      expect(plan).toEqual({ wrongPage: true, pageLabel: 'Workflow editor' });
    });

    it('returns wrongPage when no current path is supplied', () => {
      const plan = buildTourPlan(appMapPages, {
        page: 'workflow_edit',
        element: 'credential-picker',
        params: {},
      });

      expect(plan).toEqual({ wrongPage: true, pageLabel: 'Workflow editor' });
    });

    it('does not change page navigation when no element is requested', () => {
      // workflow_edit now carries elements; a plain page request still plans
      // exactly as before (alreadyHere via the unresolvable-path route).
      const plan = buildTourPlan(
        appMapPages,
        { page: 'workflow_edit', params: { project_id: PROJECT_ID } },
        onEditorPage
      );

      expect(plan).toEqual({
        alreadyHere: true,
        arrival: expect.objectContaining({ label: 'Workflow editor' }),
      });
    });
  });

  describe('errors', () => {
    it('errors on an unknown page id', () => {
      const plan = buildTourPlan(appMapPages, {
        page: 'nope_not_a_page',
        params: {},
      });

      expect(plan).toEqual({
        error: 'Unknown app-map page id "nope_not_a_page"',
      });
    });

    it('errors when a path parameter cannot be resolved', () => {
      const plan = buildTourPlan(appMapPages, {
        page: 'run_show',
        params: { project_id: PROJECT_ID },
      });

      expect(plan).toEqual({
        error: `Cannot resolve ":id" in path "/projects/:project_id/runs/:id"`,
      });
    });

    it('errors when project_id is missing for a project page', () => {
      const plan = buildTourPlan(appMapPages, {
        page: 'project_history',
        params: {},
      });

      expect(plan).toEqual({
        error:
          'Cannot resolve ":project_id" in path "/projects/:project_id/history"',
      });
    });

    it('errors on an unknown tab', () => {
      const plan = buildTourPlan(appMapPages, {
        page: 'project_settings',
        tab: 'does-not-exist',
        params: { project_id: PROJECT_ID },
      });

      expect(plan).toEqual({
        error: 'Unknown tab "does-not-exist" on page "project_settings"',
      });
    });

    it('errors when a tab is requested on a page without tabs', () => {
      const plan = buildTourPlan(appMapPages, {
        page: 'project_history',
        tab: 'vcs',
        params: { project_id: PROJECT_ID },
      });

      expect(plan).toEqual({
        error: 'Unknown tab "vcs" on page "project_history"',
      });
    });
  });
});
