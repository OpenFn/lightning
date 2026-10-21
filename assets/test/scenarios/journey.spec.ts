// The journey check: what happens between pages, which the page specs
// cannot see. One signed-in superuser clicks through the sidebar across the
// live sessions (dashboard → a project's workflows → history → admin audit →
// profile tokens → back). A probe installed in every document records, for
// each animation frame, whether the sidebar is drawn, and the layout shift
// so far; a window marker set before each click says whether a full page
// load happened. After each click the page gets 2 s, then the record is read.
//
// Targets: no painted frame without a sidebar once the document is parsed
// (before that, any page may be half there); a full load only where the
// router forces one today (a link into another live_session). The layout
// shift is recorded in the test's annotations for comparison, not asserted.
import { expect, test, type Page } from '@playwright/test';

import { expectAt, seedProject, signInAs, sql, user } from './steps';

const ME = 'super@openfn.org';
const SETTLE = 2000;

interface Frame {
  t: number;
  /** The document had finished parsing: what is missing is missing. */
  parsed: boolean;
  sidebar: boolean;
}

interface Reading {
  frames: Frame[];
  marker: string | undefined;
  cls: number;
}

interface Step {
  name: string;
  go: (page: Page) => Promise<void>;
  lands: string | RegExp;
  /** Whether today's router forces a full page load for this hop. */
  reloads: boolean;
}

interface Probe {
  __frames: Frame[];
  __cls: number;
  __journey?: string;
}

// Runs in every new document, before anything is painted.
const installProbe = () => {
  const w = window as unknown as Probe;
  w.__frames = [];
  w.__cls = 0;
  const tick = (t: number) => {
    const nav = document.getElementById('side-menu');
    w.__frames.push({
      t,
      parsed: document.readyState !== 'loading',
      sidebar: nav !== null && nav.getBoundingClientRect().width > 0,
    });
    requestAnimationFrame(tick);
  };
  requestAnimationFrame(tick);
  new PerformanceObserver(list => {
    for (const entry of list.getEntries() as (PerformanceEntry & {
      value: number;
      hadRecentInput: boolean;
    })[])
      if (!entry.hadRecentInput) w.__cls += entry.value;
  }).observe({ type: 'layout-shift', buffered: true });
};

const sidebar = (page: Page) => page.locator('#side-menu');

// The marker a full load erases. Frames before it are the previous step's.
const mark = (page: Page, name: string) =>
  page.evaluate(n => {
    const w = window as unknown as Probe;
    w.__journey = n;
    w.__frames = [];
  }, name);

const read = (page: Page): Promise<Reading> =>
  page.evaluate(() => {
    const w = window as unknown as Probe;
    return { frames: w.__frames, marker: w.__journey, cls: w.__cls };
  });

test('the sidebar stays through a journey across the live sessions', async ({
  page,
}) => {
  const project = seedProject('Journey', { [ME]: 'owner' });
  const [{ name: myName }] = sql<{ name: string }>(
    `select first_name || ' ' || last_name as name from users where id = '${user(ME).id}'`
  );
  await page.addInitScript(installProbe);

  const steps: Step[] = [
    {
      name: 'project workflows',
      // The dashboard's rows open the project; the name is a cell, not a link.
      go: p => p.getByRole('cell', { name: 'Journey', exact: true }).click(),
      lands: `/projects/${project.id}/w`,
      reloads: true, // /projects is in the :services session, the project in :default
    },
    {
      name: 'history',
      go: p =>
        sidebar(p).getByRole('link', { name: 'History', exact: true }).click(),
      lands: `/projects/${project.id}/history`,
      reloads: false,
    },
    {
      name: 'admin menu',
      go: p =>
        sidebar(p)
          .getByRole('link', { name: 'Admin Menu', exact: true })
          .click(),
      lands: '/settings/projects',
      reloads: true, // :default → :settings
    },
    {
      name: 'admin audit',
      go: p =>
        sidebar(p).getByRole('link', { name: 'Audit', exact: true }).click(),
      lands: '/settings/audit',
      reloads: false,
    },
    {
      name: 'profile tokens',
      go: async p => {
        await p.getByRole('button', { name: new RegExp(`${myName}$`) }).click();
        await p.getByRole('menuitem', { name: 'API Tokens' }).click();
      },
      lands: '/profile/tokens',
      reloads: true, // :settings → :default
    },
    {
      name: 'back',
      go: p => p.goBack(),
      lands: '/settings/audit',
      reloads: true, // :default → :settings
    },
  ];

  try {
    await signInAs(page, ME);
    await page.goto('/projects');
    await page.locator('.phx-connected').first().waitFor();
    await expect(sidebar(page)).toBeVisible();

    const report: string[] = [];
    for (const step of steps) {
      await mark(page, step.name);
      await step.go(page);
      await page.waitForTimeout(SETTLE);
      await expectAt(page, step.lands);
      await page.locator('.phx-connected').first().waitFor();
      const { frames, marker, cls } = await read(page);

      const painted = frames.filter(f => f.parsed);
      const empty = painted.filter(f => !f.sidebar);
      const reloaded = marker !== step.name;
      const line =
        `${step.name}: ${reloaded ? 'full load' : 'live navigation'}, ` +
        `${frames.length} frames (${painted.length} after parsing), ` +
        `${empty.length} without a sidebar, layout shift ${cls.toFixed(3)}`;
      report.push(line);
      test.info().annotations.push({ type: step.name, description: line });

      expect
        .soft(empty.length, `${step.name}: painted frames without a sidebar`)
        .toBe(0);
      expect
        .soft(
          reloaded,
          `${step.name}: ${step.reloads ? 'should' : 'should not'} be a full load`
        )
        .toBe(step.reloads);
    }
    console.log(report.join('\n'));
  } finally {
    project.remove();
  }
});
