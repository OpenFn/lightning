// Scenarios from annotations/views/workflow-health.md.
//
// Who's who: "I" is editor@openfn.org (Esther Editor), a viewer on the project
// each test seeds ("Malawi HIV") with its workflow "Daily sync" (jobs "Fetch"
// and "Load") and removes again. "Another user" is owner@openfn.org. Work
// orders are inserted straight into the database, so the charts have exactly
// the numbers a scenario names. Every test also puts editor's account back as
// it found it.
import {
  expect,
  test,
  type APIRequestContext,
  type Locator,
  type Page,
  type Route,
} from '@playwright/test';

import { card, meta } from './pages/workflow-health';
import * as authenticatedSession from './shared/authenticated-session';
import * as flashMessages from './shared/flash-messages';
import * as projectHeader from './shared/project-header';
import * as projectScope from './shared/project-scope';
import {
  browserReportsTimezone,
  changeRoleOnNode,
  deleteWorkflowOnNode,
  exec,
  expectAt,
  expectHistoryLists,
  healthPath,
  healthRoot,
  keepAccount,
  mailedLinkTo,
  makeSupportUser,
  manifest,
  open,
  reload,
  removeMemberOnNode,
  removeMfaOf,
  removeWorkflowData,
  returnToTab,
  scheduleDeletionOnNode,
  seedProject,
  seedWorkOrder,
  seedWorkOrders,
  seedWorkflow,
  sendDigestOnNode,
  sendFailureAlertOnNode,
  setPreferences,
  setSupportAccessOnNode,
  signInAs,
  tagFor,
  user,
  type SeededWorkflow,
} from './steps';

const PASSING = { tag: ['@passing-old', '@passing-new'] };
// History opens in this tab on the port; Lightning opens a new one
const NEW_ONLY = { tag: '@passing-new' };
const ME = 'editor@openfn.org';
const OTHER = 'owner@openfn.org';

let cleanups: (() => void)[] = [];
test.beforeEach(() => {
  cleanups = [keepAccount(ME)];
});
test.afterEach(() => {
  for (const cleanup of cleanups.reverse()) cleanup();
});

type Members = Parameters<typeof seedProject>[1];

// Given project "<name>" exists with these members (removed after the test,
// with the work orders seeded for it)
function given(
  name: string,
  members: Members,
  options?: Parameters<typeof seedProject>[2]
) {
  const project = seedProject(name, members, options);
  cleanups.push(() => {
    removeWorkflowData(project.id);
    project.remove();
  });
  return project;
}

// Given I am a viewer on project "Malawi HIV"
// And workflow "Daily sync" has jobs "Fetch" and "Load"
function givenHealth(
  name = 'Malawi HIV',
  members: Members = { [ME]: 'viewer' }
) {
  const project = given(name, members);
  const wf = seedWorkflow(project.id);
  return { project, wf, path: healthPath(project.id, wf.id) };
}
type Health = ReturnType<typeof givenHealth>;

// When I open the health page of "Daily sync" — waits for the first card
async function openHealth(page: Page, h: Pick<Health, 'path'>) {
  await signInAs(page, ME);
  await open(page, h.path);
  await expect(heading(page, 'Outcomes')).toBeVisible();
}

const heading = (page: Page, name: string) =>
  page.getByRole('heading', { name, exact: true });

const triage = (page: Page) =>
  page
    .getByRole('heading', { name: 'Triage - grouped by failure type' })
    .locator('xpath=..');

const triageRows = (page: Page) =>
  triage(page)
    .getByRole('row')
    .filter({ has: page.getByRole('cell') });

// The legend row "<label> <count>" of a donut
const slice = (within: Locator, label: string, count: number) =>
  within.getByRole('link', {
    name: new RegExp(`^${label} ${count.toLocaleString('en-US')}\\b`, 'i'),
  });

const cell = (row: Locator, index: number) => row.getByRole('cell').nth(index);

const dayRange = (page: Page, label: string) =>
  page.getByRole('radio', { name: label });

const utc = (date: Date) => date.toISOString().slice(0, 19).replace('T', ' ');

// Given <n> work orders of the workflow failed at <job> with <error>
function failures(
  wf: SeededWorkflow,
  job: string,
  error: string | null,
  n = 1,
  minutesAgo = 60
) {
  return Array.from({ length: n }, () =>
    seedWorkOrder(wf, {
      state: 'failed',
      minutesAgo,
      runs: [{ state: 'failed', steps: [{ job, error }] }],
    })
  );
}

const noFailures = (days: string) => `No failures in the last ${days}`;

// Drill-down links open History in this tab
async function opensHistory(page: Page, click: () => Promise<void>) {
  await click();
  await page.waitForURL(/\/history/);
  return page;
}

// @S01
// Scenario: A member opens a workflow's health page from the workflow list
//   Given I am on the workflows page of "Malawi HIV"
//   When I click "Health" on the "Daily sync" row
//   Then I am on "/projects/<project_id>/w/<daily_sync_id>/health"
//   And I see the heading "Daily sync"
//   And the breadcrumbs end "Workflows", "Daily sync", "Health"
//   And "Last 7 days" is selected
//   And the "Work orders" tab is selected, showing "Outcomes", "Failure breakdown" and "Steps with failures"
//   And I see "Triage - grouped by failure type"
test('@S01', PASSING, async ({ page }) => {
  const h = givenHealth();
  await signInAs(page, ME);
  await open(page, `/projects/${h.project.id}/w`);

  await page
    .getByRole('row')
    .filter({ hasText: 'Daily sync' })
    .getByRole('link', { name: 'Health' })
    .click();

  await expectAt(page, h.path);
  await expect(
    page.getByRole('heading', { name: 'Daily sync', level: 1 })
  ).toBeVisible();
  const trail = page.getByRole('navigation', { name: 'Breadcrumbs' });
  await expect
    .poll(async () =>
      (await trail.getByRole('listitem').allInnerTexts())
        .map(text => text.trim())
        .slice(-3)
    )
    .toEqual(['Workflows', 'Daily sync', 'Health']);
  await expect(dayRange(page, 'Last 7 days')).toBeChecked();
  await expect(page.getByRole('tab', { name: 'Work orders' })).toHaveAttribute(
    'aria-selected',
    'true'
  );
  for (const title of ['Outcomes', 'Failure breakdown', 'Steps with failures'])
    await expect(heading(page, title)).toBeVisible();
  await expect(heading(page, 'Triage - grouped by failure type')).toBeVisible();
});

// @S02
// Scenario: The workflow crumb leads back to its editor
//   Given I am on the health page of "Daily sync"
//   When I click "Daily sync" in the breadcrumbs
//   Then I am in the editor for "Daily sync"
test('@S02', PASSING, async ({ page }) => {
  const h = givenHealth();
  await openHealth(page, h);

  await page
    .getByRole('navigation', { name: 'Breadcrumbs' })
    .getByRole('link', { name: 'Daily sync', exact: true })
    .click();

  await expectAt(
    page,
    new RegExp(`^/projects/${h.project.id}/w/${h.wf.id}(?!/health)(/|$)`)
  );
});

// @S03
// Scenario Outline: A workflow that is not in this project, or is deleted, is not shown
//   Given <workflow>
//   When I visit its health page under project "Malawi HIV"
//   Then I am on the workflows page of "Malawi HIV"
//   And I see "Workflow not found"
//   Examples:
//     | workflow "Kenya sync" belongs to project "Kenya TB"   |
//     | workflow "Old intake" in "Malawi HIV" has been deleted |
test('@S03', PASSING, async ({ page }) => {
  const h = givenHealth();
  const kenya = given('Kenya TB', { [ME]: 'viewer' });
  const kenyaSync = seedWorkflow(kenya.id, 'Kenya sync');
  const oldIntake = seedWorkflow(h.project.id, 'Old intake');
  exec(`update workflows set deleted_at = now() at time zone 'utc'
        where id = '${oldIntake.id}'`);
  await signInAs(page, ME);

  for (const workflow of [kenyaSync, oldIntake]) {
    await page.goto(`/projects/${h.project.id}/w/${workflow.id}/health`);

    await expectAt(page, `/projects/${h.project.id}/w`);
    await expect(
      page.getByText('Workflow not found'),
      `${workflow.name} is not shown`
    ).toBeVisible();
    await expect(heading(page, 'Outcomes')).toHaveCount(0);
  }
});

// @S04
// Scenario: Outcomes count each finished work order once, with the success rate in the middle
//   Given in the last 7 days "Daily sync" had 9 successful, 1 failed, 1 crashed and 2 cancelled work orders
//   And 1 work order is still running
//   When I open its health page
//   Then the "Outcomes" card meta reads "13 work orders"
//   And the legend reads "Success 9", "Failed 2", "Cancelled 2"
//   And the middle of the ring reads "81.8%" and "success"
test('@S04', PASSING, async ({ page }) => {
  const h = givenHealth();
  seedWorkOrders(h.wf, 'success', 9);
  seedWorkOrders(h.wf, 'failed', 1);
  seedWorkOrders(h.wf, 'crashed', 1);
  seedWorkOrders(h.wf, 'cancelled', 2);
  seedWorkOrders(h.wf, 'running', 1);

  await openHealth(page, h);

  const outcomes = card(page, 'Outcomes');
  await expect(outcomes).toContainText('13 work orders');
  await expect(slice(outcomes, 'Success', 9)).toBeVisible();
  await expect(slice(outcomes, 'Failed', 2)).toBeVisible();
  await expect(slice(outcomes, 'Cancelled', 2)).toBeVisible();
  await expect(outcomes.getByRole('listitem')).toHaveCount(3);
  await expect(outcomes.getByText('81.8%', { exact: true })).toBeVisible();
  await expect(outcomes.getByText('success', { exact: true })).toBeVisible();
});

// @S05
// Scenario: A work order retried to success counts as a success
//   Given a "Daily sync" work order whose first run failed and whose retry succeeded in the last 7 days
//   When I open its health page
//   Then "Outcomes" shows "Success 1" and "Failed 0"
//   And the triage table shows "No failures in the last 7 days"
test('@S05', PASSING, async ({ page }) => {
  const h = givenHealth();
  seedWorkOrder(h.wf, {
    state: 'success',
    runs: [
      { state: 'failed', steps: [{ job: 'Fetch', error: 'RuntimeError' }] },
      {
        state: 'success',
        steps: [{ job: 'Fetch', exit: 'success', error: null }],
      },
    ],
  });

  await openHealth(page, h);

  const outcomes = card(page, 'Outcomes');
  await expect(slice(outcomes, 'Success', 1)).toBeVisible();
  await expect(slice(outcomes, 'Failed', 0)).toBeVisible();
  await expect(triage(page)).toContainText(noFailures('7 days'));
  await expect(triageRows(page)).toHaveCount(0);
});

// @S06
// Scenario: A single failure is never rounded away
//   Given in the last 7 days "Daily sync" had 2,500 successful and 1 failed work order
//   When I open its health page
//   Then the middle of the ring reads "<100%"
test('@S06', PASSING, async ({ page }) => {
  const h = givenHealth();
  seedWorkOrders(h.wf, 'success', 2500);
  seedWorkOrders(h.wf, 'failed', 1);

  await openHealth(page, h);

  const outcomes = card(page, 'Outcomes');
  await expect(slice(outcomes, 'Success', 2500)).toBeVisible();
  await expect(outcomes.getByText('<100%', { exact: true })).toBeVisible();
  await expect(outcomes.getByText('100.0%')).toHaveCount(0);
});

// @S07
// Scenario: Failures are broken down by the state they ended in
//   Given in the last 7 days "Daily sync" had 3 failed, 1 lost and 2 rejected work orders and 4 cancelled ones
//   When I open its health page
//   Then "Failure breakdown" lists "failed 3", "lost 1" and "rejected 2" and no other state
//   And the middle of its ring reads "6" and "failures"
//   And the "Failed" wedge of "Outcomes" also reads 6
test('@S07', PASSING, async ({ page }) => {
  const h = givenHealth();
  seedWorkOrders(h.wf, 'failed', 3);
  seedWorkOrders(h.wf, 'lost', 1);
  seedWorkOrders(h.wf, 'rejected', 2);
  seedWorkOrders(h.wf, 'cancelled', 4);

  await openHealth(page, h);

  const breakdown = card(page, 'Failure breakdown');
  await expect(slice(breakdown, 'failed', 3)).toBeVisible();
  await expect(slice(breakdown, 'lost', 1)).toBeVisible();
  await expect(slice(breakdown, 'rejected', 2)).toBeVisible();
  await expect(breakdown.getByRole('listitem')).toHaveCount(3);
  await expect(breakdown.getByText('6', { exact: true })).toBeVisible();
  await expect(breakdown.getByText('failures', { exact: true })).toBeVisible();
  await expect(slice(card(page, 'Outcomes'), 'Failed', 6)).toBeVisible();
});

// @S08
// Scenario: Steps with failures shows where failures land, heaviest first
//   Given in the last 7 days 5 work orders failed at "Load", 3 with "RuntimeError" and 2 with "AdaptorError"
//   And 2 work orders failed at "Fetch"
//   And 1 work order's run was lost before any step reported
//   When I open its health page
//   Then "Steps with failures" lists "Load 5", then "Fetch 2", then "No failing step 1"
//   And each named step shows its adaptor below it
test('@S08', PASSING, async ({ page }) => {
  const h = givenHealth();
  failures(h.wf, 'Load', 'RuntimeError', 3);
  failures(h.wf, 'Load', 'AdaptorError', 2);
  failures(h.wf, 'Fetch', 'RuntimeError', 2);
  seedWorkOrder(h.wf, { state: 'lost', runs: [{ state: 'lost' }] });

  await openHealth(page, h);

  // Heaviest first; each named step shows its own adaptor
  const rows = card(page, 'Steps with failures').getByRole('listitem');
  await expect(rows).toHaveCount(3);
  // Label, adaptor and count are separate spans, so assert them as parts
  const expectRow = async (
    i: number,
    name: string,
    adaptor: string | null,
    count: string
  ) => {
    const row = rows.nth(i);
    await expect(row.getByText(name, { exact: true })).toBeVisible();
    if (adaptor) await expect(row.getByText(adaptor)).toBeVisible();
    await expect(row.getByText(count, { exact: true })).toBeVisible();
  };
  await expectRow(0, 'Load', 'dhis2 adaptor', '5');
  await expectRow(1, 'Fetch', 'http adaptor', '2');
  await expectRow(2, 'No failing step', null, '1');
});

// @S09
// Scenario: Triage groups failures by error, heaviest first, with a suggestion
//   Given in the last 7 days 4 work orders failed with "RuntimeError" at "Load" and 1 with "CompileError" before any step ran
//   When I open its health page
//   Then the first triage row reads "4", "Failed", "fail:RuntimeError @ Load" and "Job code hit a value it didn't expect, often a missing input field."
//   And the second row reads "1", "crash:CompileError" with no step and "Job code couldn't be compiled, so no step ever ran."
test('@S09', PASSING, async ({ page }) => {
  const h = givenHealth();
  failures(h.wf, 'Load', 'RuntimeError', 4);
  seedWorkOrder(h.wf, {
    state: 'crashed',
    runs: [{ state: 'crashed', error: 'CompileError' }],
  });

  await openHealth(page, h);

  const rows = triageRows(page);
  await expect(rows).toHaveCount(2);
  // Heaviest first
  const [first, second] = [rows.nth(0), rows.nth(1)];
  await expect(first).toContainText('fail:RuntimeError @ Load');
  await expect(
    first.getByRole('cell', { name: '4', exact: true })
  ).toBeVisible();
  await expect(second).toContainText('crash:CompileError');
  await expect(second).not.toContainText('@');
  await expect(
    second.getByRole('cell', { name: '1', exact: true })
  ).toBeVisible();
  // Each row carries a plain-language hint (its longest cell), and they differ
  const hint = async (row: Locator) =>
    (await row.getByRole('cell').allInnerTexts())
      .map(text => text.trim())
      .reduce((a, b) => (b.length > a.length ? b : a), '');
  const [hintOne, hintTwo] = [await hint(first), await hint(second)];
  expect(hintOne.length).toBeGreaterThan(20);
  expect(hintTwo.length).toBeGreaterThan(20);
  expect(hintOne).not.toBe(hintTwo);
});

// @S10
// Scenario: Work orders refused over the run limit get their own triage row
//   Given in the last 7 days 2 webhook requests to "Daily sync" were rejected over the run limit
//   When I open its health page
//   Then a triage row reads "2", "rejected:RunLimitExceeded" and "The project was over its run limit, so no run was created for this request."
test('@S10', PASSING, async ({ page }) => {
  const h = givenHealth();
  seedWorkOrders(h.wf, 'rejected', 2);

  await openHealth(page, h);

  await expect(triageRows(page)).toHaveCount(1);
  const row = triageRows(page).filter({ hasText: 'RunLimitExceeded' });
  await expect(row).toHaveCount(1);
  await expect(row.getByRole('cell', { name: '2', exact: true })).toBeVisible();
});

// @S11
// Scenario: A retried work order is triaged by its latest attempt only
//   Given a "Daily sync" work order failed with "FirstAttempt" at "Fetch", then its retry failed with "Retry" at "Load"
//   When I open its health page
//   Then the triage table has one row, "fail:Retry @ Load", with count 1
test('@S11', PASSING, async ({ page }) => {
  const h = givenHealth();
  seedWorkOrder(h.wf, {
    state: 'failed',
    runs: [
      { state: 'failed', steps: [{ job: 'Fetch', error: 'FirstAttempt' }] },
      { state: 'failed', steps: [{ job: 'Load', error: 'Retry' }] },
    ],
  });

  await openHealth(page, h);

  const rows = triageRows(page);
  await expect(rows).toHaveCount(1);
  await expect(cell(rows, 0)).toHaveText('1');
  await expect(cell(rows, 1)).toContainText('fail:Retry @ Load');
  await expect(triage(page)).not.toContainText('FirstAttempt');
});

// @S12
// Scenario: A work order that broke in two branches is triaged under both
//   Given a "Daily sync" work order whose latest run failed at both "Fetch" and "Load"
//   When I open its health page
//   Then the triage table has a row for "Fetch" and a row for "Load", each with count 1
//   And "Outcomes" counts the work order once
test('@S12', PASSING, async ({ page }) => {
  const h = givenHealth();
  seedWorkOrder(h.wf, {
    state: 'failed',
    runs: [
      {
        state: 'failed',
        steps: [
          { job: 'Fetch', error: 'RuntimeError' },
          { job: 'Load', error: 'RuntimeError' },
        ],
      },
    ],
  });

  await openHealth(page, h);

  const rows = triageRows(page);
  await expect(rows).toHaveCount(2);
  for (const job of ['Fetch', 'Load']) {
    const row = rows.filter({ hasText: `@ ${job}` });
    await expect(row, `a row for ${job}`).toHaveCount(1);
    await expect(cell(row, 0)).toHaveText('1');
  }
  const outcomes = card(page, 'Outcomes');
  await expect(outcomes).toContainText('1 work order');
  await expect(slice(outcomes, 'Failed', 1)).toBeVisible();
});

// @S13
// Scenario: A step is named as it was when it failed
//   Given job "Load" failed in the last 7 days and was then renamed to "Load to DHIS2"
//   When I open its health page
//   Then the triage row names the step "Load"
//   When "Load to DHIS2" then fails with the same error
//   Then the two failures are one row, named "Load to DHIS2"
test('@S13', PASSING, async ({ page }) => {
  const h = givenHealth();
  failures(h.wf, 'Load', 'RuntimeError', 1, 120);
  h.wf.rename('Load', 'Load to DHIS2');

  await openHealth(page, h);

  const rows = triageRows(page);
  await expect(rows).toHaveCount(1);
  await expect(cell(rows, 1)).toContainText('fail:RuntimeError @ Load');
  await expect(cell(rows, 1)).not.toContainText('Load to DHIS2');

  failures(h.wf, 'Load to DHIS2', 'RuntimeError', 1, 10);
  await reload(page);

  await expect(rows).toHaveCount(1);
  await expect(cell(rows, 0)).toHaveText('2');
  await expect(cell(rows, 1)).toContainText(
    'fail:RuntimeError @ Load to DHIS2'
  );
});

// @S14
// Scenario: Triage "View history" starts the drill-down flow
//   Given the triage row "fail:RuntimeError @ Load" shows 2
//   When I click "View history" on that row
//   Then the flow "flow-workflow-health-drilldown" has started (its S01)
//   And History opens in this tab, not a new one (changed on purpose; Lightning opened a new tab)
test('@S14', NEW_ONLY, async ({ page }) => {
  const h = givenHealth();
  const loads = failures(h.wf, 'Load', 'RuntimeError', 2);
  const fetches = failures(h.wf, 'Fetch', 'AdaptorError', 1);
  await openHealth(page, h);
  const row = triageRows(page).filter({ hasText: 'fail:RuntimeError @ Load' });
  await expect(row.getByRole('cell', { name: '2', exact: true })).toBeVisible();

  const tab = await opensHistory(page, () =>
    row.getByRole('link', { name: /View history/ }).click()
  );

  // History lists that error's work orders and not the other error's
  await expectHistoryLists(tab, loads, fetches);
});

// @S15
// Scenario: An outcome or failure state opens the work orders it counts
//   Given "Outcomes" shows "Failed 6"
//   When I click "Failed" in the "Outcomes" legend
//   Then the flow "flow-workflow-health-drilldown" has started
//   And History opens in this tab, not a new one (changed on purpose; Lightning opened a new tab)
test('@S15', NEW_ONLY, async ({ page }) => {
  const h = givenHealth();
  const seed = (state: string, n: number) =>
    Array.from({ length: n }, () =>
      seedWorkOrder(h.wf, { state, runs: [{ state }] })
    );
  const bad = [...seed('failed', 3), ...seed('crashed', 2), ...seed('lost', 1)];
  const good = seed('success', 4);
  await openHealth(page, h);
  const failed = slice(card(page, 'Outcomes'), 'Failed', 6);
  await expect(failed).toBeVisible();

  const tab = await opensHistory(page, () => failed.click());

  // History lists the 6 failed, crashed and lost work orders and no success
  await expectHistoryLists(tab, bad, good);
});

// @S16
// Scenario: Runs over time are drawn on my own clock and say so
//   Given my browser's timezone is "Africa/Nairobi"
//   And a run of "Daily sync" failed at 11:30 UTC today
//   When I open its health page with "Last 24 hours" and choose the "Runs" tab
//   Then I see "Runs over time" with the meta "2-hour buckets · Africa/Nairobi"
//   And the failed run is in the bar starting 14:00
//   And hovering that bar shows "<today>, 14:00 – 16:00"
test('@S16', PASSING, async ({ browser }) => {
  const h = givenHealth();
  // The latest 11:30 UTC that has passed, so it is always inside 24 hours
  const now = new Date();
  const failedAt = new Date(
    Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate(), 11, 30)
  );
  if (failedAt.getTime() > now.getTime() - 5 * 60_000)
    failedAt.setUTCDate(failedAt.getUTCDate() - 1);
  seedWorkOrder(h.wf, {
    state: 'failed',
    at: utc(failedAt),
    runs: [
      { state: 'failed', steps: [{ job: 'Load', error: 'RuntimeError' }] },
    ],
  });
  const { baseURL, locale } = test.info().project.use;
  const context = await browser.newContext({
    baseURL,
    locale,
    timezoneId: 'Africa/Nairobi',
  });
  const page = await context.newPage();
  try {
    await openHealth(page, h);
    await dayRange(page, 'Last 24 hours').click();
    await page.getByRole('tab', { name: 'Runs' }).click();

    await expect(meta(page, 'Runs over time')).toContainText('Africa/Nairobi');
    // 11:30 UTC is 14:30 in Nairobi, so the bar opens at 14:00. The window
    // spans 24 hours, so that hour can label two bars: look at each for the
    // one that holds the run.
    const day = failedAt.toLocaleDateString('en-US', {
      month: 'short',
      day: 'numeric',
      timeZone: 'Africa/Nairobi',
    });
    const label = page.getByText(`${day}, 14:00 – 16:00`, { exact: true });
    const ticks = page.getByText('14:00', { exact: true });
    await expect(ticks.first()).toBeVisible();
    let shown: string | null = null;
    for (let i = 0; i < (await ticks.count()); i++) {
      const box = (await ticks.nth(i).boundingBox())!;
      await page.mouse.move(box.x + box.width / 2, box.y - 60);
      await label.waitFor({ state: 'visible', timeout: 2000 }).catch(() => {});
      if (await label.isVisible())
        shown = await label.locator('xpath=..').innerText();
    }
    expect(shown, `a bar starting 14:00 on ${day}`).not.toBeNull();
    expect(shown).toMatch(/Failed\s*1/);
  } finally {
    await context.close();
  }
});

// @S17
// Scenario: A browser that can't name its timezone gets UTC, and is told
//   Given my browser reports its timezone as "Etc/Unknown"
//   When I open the "Runs" tab of the health page
//   Then the meta ends "Etc/UTC"
test('@S17', PASSING, async ({ page }) => {
  const h = givenHealth();
  await browserReportsTimezone(page, 'Etc/Unknown');
  await openHealth(page, h);

  await page.getByRole('tab', { name: 'Runs' }).click();

  await expect(meta(page, 'Runs over time')).toHaveText(/ · Etc\/UTC$/);
});

// @S18
// Scenario: Changing the range redraws every panel for the new window together
//   Given I am on the health page of "Daily sync" showing "Last 7 days"
//   When I choose "Last 30 days"
//   Then every panel shows a loading placeholder until its new numbers arrive
//   And no panel shows numbers or an empty message for the 7-day window
test('@S18', PASSING, async ({ page }) => {
  const h = givenHealth();
  // 3 successes and a failure in the last 7 days; 2 more successes 20 days ago
  seedWorkOrders(h.wf, 'success', 3);
  failures(h.wf, 'Load', 'RuntimeError', 1);
  seedWorkOrders(h.wf, 'success', 2, 20 * 24 * 60);
  await openHealth(page, h);
  const outcomes = card(page, 'Outcomes');
  await expect(slice(outcomes, 'Success', 3)).toBeVisible();
  await expect(triageRows(page)).toHaveCount(1);

  // Hold every health request made after the click, so the page can be seen
  // in between
  let release!: () => void;
  const gate = new Promise<void>(resolve => (release = resolve));
  let holding = false;
  let held = 0;
  await page.route(/\/health\//, async route => {
    if (!holding) return route.continue();
    held++;
    await gate;
    await route.continue();
  });
  holding = true;
  await dayRange(page, 'Last 30 days').click();
  await expect.poll(() => held).toBeGreaterThan(0);

  // Something says it is loading (text or aria-busy), and nothing is an error
  await expect(
    page
      .getByText(/loading/i)
      .or(page.locator('[aria-busy="true"]'))
      .first()
  ).toBeAttached();
  await expect(page.getByRole('alert')).toHaveCount(0);
  await expect(slice(outcomes, 'Success', 3)).toHaveCount(0);
  await expect(outcomes).not.toContainText('work orders');
  await expect(triageRows(page)).toHaveCount(0);
  await expect(page.getByText(/^No (failures|finished)/)).toHaveCount(0);

  release();

  await expect(slice(outcomes, 'Success', 5)).toBeVisible();
  await expect(page.getByText(/loading/i)).toHaveCount(0);
});

// @S19 @variant:history-retention-14
// Scenario: A range longer than the project keeps history is not offered
//   Given project "Malawi HIV" keeps history for 14 days
//   When I open the health page of "Daily sync"
//   Then "Last 30 days" is disabled
//   And hovering it shows "Only 14 days of history are kept for this project."
//   And "Last 24 hours" and "Last 7 days" are enabled
test('@S19', PASSING, async ({ page }) => {
  const h = givenHealth();
  exec(
    `update projects set history_retention_period = 14 where id = '${h.project.id}'`
  );

  await openHealth(page, h);

  await expect(dayRange(page, 'Last 30 days')).toBeDisabled();
  await dayRange(page, 'Last 30 days').hover({ force: true });
  await expect(page.getByText(/14 days/i).first()).toBeVisible();
  await expect(dayRange(page, 'Last 24 hours')).toBeEnabled();
  await expect(dayRange(page, 'Last 7 days')).toBeEnabled();
});

// @S20
// Scenario: An empty window says so
//   Given "Daily sync" had no finished work orders in the last 24 hours
//   When I open its health page with "Last 24 hours"
//   Then "Outcomes" reads "No finished work orders in the last 24 hours"
//   And "Failure breakdown", "Steps with failures" and the triage table read "No failures in the last 24 hours"
test('@S20', PASSING, async ({ page }) => {
  const h = givenHealth();
  // Work from three days ago, so the 7-day window has numbers and 24 hours has none
  seedWorkOrders(h.wf, 'success', 2, 3 * 24 * 60);
  failures(h.wf, 'Load', 'RuntimeError', 1, 3 * 24 * 60);
  await openHealth(page, h);
  await expect(slice(card(page, 'Outcomes'), 'Success', 2)).toBeVisible();

  await dayRange(page, 'Last 24 hours').click();

  await expect(card(page, 'Outcomes')).toContainText(
    /no finished work orders/i
  );
  for (const where of [
    card(page, 'Failure breakdown'),
    card(page, 'Steps with failures'),
    triage(page),
  ])
    await expect(where).toContainText(/no failures/i);
  // Quiet, not broken: no error and nothing still loading
  await expect(page.getByRole('alert')).toHaveCount(0);
  await expect(page.getByText(/could not load|loading/i)).toHaveCount(0);
});

// @S21
// Scenario: An open page updates on its own
//   Given I have the health page of "Daily sync" open and visible
//   When a work order of "Daily sync" settles as failed
//   Then within a few minutes "Outcomes" counts it without a reload
//   And when I switch to another browser tab and back, the page asks for fresh numbers at once
test('@S21', PASSING, async ({ page }) => {
  test.setTimeout(150_000);
  const h = givenHealth();
  seedWorkOrders(h.wf, 'success', 1);
  await openHealth(page, h);
  const outcomes = card(page, 'Outcomes');
  await expect(slice(outcomes, 'Failed', 0)).toBeVisible();

  failures(h.wf, 'Load', 'RuntimeError', 1, 0);

  await expect(slice(outcomes, 'Failed', 1)).toBeVisible({ timeout: 90_000 });

  // The next poll is half a minute away; coming back to the tab beats it
  failures(h.wf, 'Load', 'RuntimeError', 1, 0);
  await returnToTab(page);

  await expect(slice(outcomes, 'Failed', 2)).toBeVisible({ timeout: 15_000 });
});

// @S22
// Scenario: One failing chart does not take the page with it
//   Given the failures data cannot be loaded
//   When I open the health page of "Daily sync"
//   Then "Steps with failures" and the triage table show "Could not load workflow stats. Refresh to try again."
//   And "Outcomes" and "Failure breakdown" show their numbers
//   And no server error text is shown
test('@S22', PASSING, async ({ page }) => {
  const h = givenHealth();
  seedWorkOrders(h.wf, 'success', 2);
  seedWorkOrders(h.wf, 'failed', 1);
  await page.route(/\/health\/failures/, route =>
    route.fulfill({ status: 500, body: 'Internal Server Error: boom' })
  );

  await openHealth(page, h);

  await expect(card(page, 'Steps with failures')).toContainText(
    /could not load/i
  );
  await expect(triage(page)).toContainText(/could not load/i);
  await expect(slice(card(page, 'Outcomes'), 'Success', 2)).toBeVisible();
  await expect(
    slice(card(page, 'Failure breakdown'), 'failed', 1)
  ).toBeVisible();
  await expect(page.getByText(/boom|Internal Server Error/)).toHaveCount(0);
});

// @S23
// Scenario: A failed refresh keeps the numbers on screen
//   Given I have the health page of "Daily sync" open with its numbers loaded
//   When one automatic refresh fails
//   Then the previous numbers stay and no error is shown
//   And the next successful refresh replaces them
test('@S23', PASSING, async ({ page }) => {
  const h = givenHealth();
  seedWorkOrders(h.wf, 'success', 2);
  await openHealth(page, h);
  const outcomes = card(page, 'Outcomes');
  await expect(slice(outcomes, 'Success', 2)).toBeVisible();

  // Count the refreshes refused; wait for all three panels' to have landed
  let refused = 0;
  const refuse = (route: Route) => {
    refused++;
    return route.fulfill({ status: 500, body: 'Internal Server Error' });
  };
  await page.route(/\/health\/(outcomes|failures|runs)/, refuse);
  await returnToTab(page);
  await expect.poll(() => refused).toBeGreaterThanOrEqual(3);
  await page.evaluate(
    () => new Promise(resolve => requestAnimationFrame(() => resolve(null)))
  );

  await expect(slice(outcomes, 'Success', 2)).toBeVisible();
  await expect(page.getByText('Could not load workflow stats')).toHaveCount(0);
  await expect(page.getByRole('alert')).toHaveCount(0);

  await page.unroute(/\/health\/(outcomes|failures|runs)/, refuse);
  seedWorkOrders(h.wf, 'success', 1, 0);
  await returnToTab(page);

  await expect(slice(outcomes, 'Success', 3)).toBeVisible({ timeout: 15_000 });
});

// @S24
// Scenario Outline: The page's data is served only to people who can open it
//   Given <who>
//   When the browser requests the outcomes, failures or runs data for "Daily sync"
//   Then the response is <status>
//   Examples:
//     | I am a viewer on "Malawi HIV"                                               | 200 |
//     | I am a support user and "Malawi HIV" allows support access                  | 200 |
//     | I am not signed in                                                          | 401 |
//     | I am signed in but not on "Malawi HIV"                                      | 404 |
//     | I am a support user and "Malawi HIV" does not allow support access          | 404 |
//     | "Malawi HIV" requires MFA and I have not enrolled                           | 404 |
//     | "Malawi HIV" is scheduled for deletion                                      | 404 |
//     | "Daily sync" has been deleted                                               | 404 |
//     | the request names "Daily sync" under project "Kenya TB", which I am not on  | 404 |
test(
  '@S24',
  { tag: ['@passing-old', '@passing-new', '@serial'] },
  async ({ page, request }) => {
    removeMfaOf(ME);
    const asked = async (
      api: APIRequestContext,
      projectId: string,
      workflowId: string
    ) => {
      const statuses: Record<string, number> = {};
      for (const slice of ['outcomes', 'failures', 'runs'])
        statuses[slice] = (
          await api.get(
            `/api/projects/${projectId}/workflows/${workflowId}/health/${slice}?days=7`,
            { maxRedirects: 0 }
          )
        ).status();
      return statuses;
    };
    const all = (status: number) => ({
      outcomes: status,
      failures: status,
      runs: status,
    });

    const viewer = givenHealth();
    const others = givenHealth('Kenya TB', { [OTHER]: 'owner' });
    // A project I am a member of, asked for a workflow that belongs to another
    const mine = givenHealth('Kenya TB member', { [ME]: 'viewer' });
    const mfa = givenHealth('Requires MFA');
    exec(
      `update projects set requires_mfa = true where id = '${mfa.project.id}'`
    );
    const wound = givenHealth('Wound down');
    exec(
      `update projects set scheduled_deletion = now() + interval '7 days' where id = '${wound.project.id}'`
    );
    const gone = givenHealth('Gone workflow');
    exec(
      `update workflows set deleted_at = now() at time zone 'utc' where id = '${gone.wf.id}'`
    );
    const supported = givenHealth('Supported', { [OTHER]: 'owner' });
    exec(
      `update projects set allow_support_access = true where id = '${supported.project.id}'`
    );
    const unsupported = givenHealth('Unsupported', { [OTHER]: 'owner' });

    expect(
      await asked(request, viewer.project.id, viewer.wf.id),
      'not signed in'
    ).toEqual(all(401));

    await signInAs(page, ME);
    const api = page.request;
    expect(
      await asked(api, viewer.project.id, viewer.wf.id),
      'a viewer'
    ).toEqual(all(200));
    expect(
      await asked(api, others.project.id, others.wf.id),
      'not on the project'
    ).toEqual(all(404));
    expect(
      await asked(api, mfa.project.id, mfa.wf.id),
      'MFA required, not enrolled'
    ).toEqual(all(404));
    expect(
      await asked(api, wound.project.id, wound.wf.id),
      'project scheduled for deletion'
    ).toEqual(all(404));
    expect(
      await asked(api, gone.project.id, gone.wf.id),
      'workflow deleted'
    ).toEqual(all(404));
    expect(
      await asked(api, others.project.id, viewer.wf.id),
      "the workflow under a project I'm not on"
    ).toEqual(all(404));
    expect(
      await asked(api, mine.project.id, mine.wf.id),
      'a viewer on the other project'
    ).toEqual(all(200));
    expect(
      await asked(api, mine.project.id, viewer.wf.id),
      "the workflow under another project I'm on"
    ).toEqual(all(404));

    cleanups.push(makeSupportUser(ME));
    expect(
      await asked(api, supported.project.id, supported.wf.id),
      'support user, support access on'
    ).toEqual(all(200));
    expect(
      await asked(api, unsupported.project.id, unsupported.wf.id),
      'support user, support access off'
    ).toEqual(all(404));
  }
);

// @S25
// Scenario: A failure alert's health link lands on this page
//   Given I received a failure alert for "Daily sync"
//   When I follow "this workflow's health"
//   Then I am on the health page of "Daily sync"
//   And the flow "flow-failure-alert-email" ends on this page
//   And if I was signed out, the flow "flow-login-return-to" starts for that URL
test(
  '@S25',
  { tag: ['@passing-old', '@passing-new', '@serial'] },
  async ({ page, request }) => {
    const h = givenHealth();
    sendFailureAlertOnNode(h.project.id, h.wf, ME);
    const link = await mailedLinkTo(request, user(ME).email, h.path);

    await signInAs(page, ME);
    await page.goto(link);
    await expectAt(page, h.path);
    await expect(heading(page, 'Outcomes')).toBeVisible();

    await page.context().clearCookies();
    await page.goto(link);
    await expectAt(page, '/users/log_in');
    await signInAs(page, ME);
    await expectAt(page, h.path);
  }
);

// @S26
// Scenario: A digest's health link lands on this page
//   Given my digest lists failures for "Daily sync"
//   When I follow "See this workflow's failures grouped by error"
//   Then I am on the health page of "Daily sync"
//   And the flow "flow-digest-email" ends on this page (its S06)
test(
  '@S26',
  { tag: ['@passing-old', '@passing-new', '@serial'] },
  async ({ page, request }) => {
    const h = givenHealth();
    sendDigestOnNode(h.project.id, h.wf, ME);
    const link = await mailedLinkTo(request, user(ME).email, h.path);

    await signInAs(page, ME);
    await page.goto(link);

    await expectAt(page, h.path);
    await expect(heading(page, 'Outcomes')).toBeVisible();
  }
);

// @S27
// Scenario: Deleting the workflow sends this page to the workflow list
//   Given I have the health page of "Daily sync" open
//   When an editor deletes "Daily sync" in another session
//   Then shared-project-scope S12 applies to this page
//   And the flow "flow-delete-open-workflow" ends here (its S01, "the health page" row)
test('@S27', PASSING, async ({ page }) => {
  const h = givenHealth();

  await projectScope.S12(
    page,
    h.path,
    ME,
    () => deleteWorkflowOnNode(h.wf.id, OTHER),
    `/projects/${h.project.id}/w`
  );
});

// @S28
// Scenario: A band of a runs-chart bar opens the runs it counts
//   Given the "Runs" tab shows a bar with a "Failed" band of 2
//   And an earlier bar has a failure too
//   When I click the "Failed" band of the bar with 2
//   Then History opens in this tab with the 2 work orders whose runs failed in that bar's slot
//   And not the earlier failure, nor the successes in the same bar
test('@S28', NEW_ONLY, async ({ page }) => {
  const h = givenHealth();
  const seed = (state: string, minutesAgo: number) =>
    seedWorkOrder(h.wf, { state, minutesAgo, runs: [{ state }] });
  const recent = [seed('failed', 30), seed('crashed', 30)];
  const others = [seed('success', 30), seed('failed', 3 * 24 * 60)];
  await openHealth(page, h);
  await page.getByRole('tab', { name: 'Runs' }).click();

  // The chart is mouse-only and hidden from assistive tech, so its bands have
  // no role or name: the red ones are the failures, oldest bar first.
  const failedBands = card(page, 'Runs over time').locator(
    'path[fill="#d03b3b"]'
  );
  await expect(failedBands).toHaveCount(2);

  const tab = await opensHistory(page, () => failedBands.last().click());

  await expectHistoryLists(tab, recent, others);
});

// Inherited from shared-authenticated-session, on the health page.
test.describe('shared-authenticated-session', () => {
  test(
    'shared-authenticated-session@S01 on workflow-health',
    { tag: tagFor('S01', ['S01', 'S02', 'S03', 'S07'], true) },
    async ({ page }) => {
      await authenticatedSession.S01(page, givenHealth().path, ME);
    }
  );

  test(
    'shared-authenticated-session@S02 on workflow-health',
    { tag: tagFor('S02', ['S01', 'S02', 'S03', 'S07'], true) },
    async ({ page, browser }) => {
      await authenticatedSession.S02(page, browser, givenHealth().path, ME);
    }
  );

  test(
    'shared-authenticated-session@S03 on workflow-health',
    { tag: tagFor('S03', ['S01', 'S02', 'S03', 'S07'], true) },
    async ({ page }) => {
      await authenticatedSession.S03(page, givenHealth().path, ME);
    }
  );

  test(
    'shared-authenticated-session@S07 on workflow-health',
    { tag: tagFor('S07', ['S01', 'S02', 'S03', 'S07'], true) },
    async ({ page, browser }) => {
      const h = givenHealth();
      await authenticatedSession.S07(
        page,
        browser,
        h.path,
        `/projects/${h.project.id}/w`,
        ME,
        'History'
      );
    }
  );

  for (const [id, variant] of [
    ['S04', 'require-email-verification'],
    ['S05', 'require-email-verification'],
    ['S06', 'require-email-verification'],
    ['S08', 'book-demo-banner'],
    ['S09', 'book-demo-banner'],
    ['S10', 'gdpr-banner'],
    ['S11', 'first-setup-open'],
  ])
    test(
      `shared-authenticated-session@${id} on workflow-health`,
      { tag: tagFor(id, ['S01', 'S02', 'S03', 'S07'], true) },
      () => {
        test.skip(
          true,
          `variant ${variant} is not configured on this instance`
        );
      }
    );
});

// Inherited from shared-project-scope, on the health page.
test.describe('shared-project-scope', () => {
  test(
    'shared-project-scope@S01 on workflow-health',
    {
      tag: tagFor(
        'S01',
        [
          'S01',
          'S02',
          'S03',
          'S04',
          'S05',
          'S06',
          'S07',
          'S08',
          'S09',
          'S10',
          'S11',
          'S12',
        ],
        true
      ),
    },
    async ({ page }) => {
      await projectScope.S01(page, givenHealth().path);
    }
  );

  test(
    'shared-project-scope@S02 on workflow-health',
    {
      tag: tagFor(
        'S02',
        [
          'S01',
          'S02',
          'S03',
          'S04',
          'S05',
          'S06',
          'S07',
          'S08',
          'S09',
          'S10',
          'S11',
          'S12',
        ],
        true
      ),
    },
    async ({ page }) => {
      const h = givenHealth();
      await projectScope.S02(
        page,
        h.path,
        ME,
        page.getByRole('heading', { name: 'Daily sync', level: 1 })
      );
    }
  );

  test(
    'shared-project-scope@S03 on workflow-health',
    {
      tag: tagFor(
        'S03',
        [
          'S01',
          'S02',
          'S03',
          'S04',
          'S05',
          'S06',
          'S07',
          'S08',
          'S09',
          'S10',
          'S11',
          'S12',
        ],
        true
      ),
    },
    async ({ page }) => {
      const h = givenHealth('Malawi HIV', { [OTHER]: 'owner' });
      await projectScope.S03(page, h.path, ME);
    }
  );

  test(
    'shared-project-scope@S04 on workflow-health',
    {
      tag: tagFor(
        'S04',
        [
          'S01',
          'S02',
          'S03',
          'S04',
          'S05',
          'S06',
          'S07',
          'S08',
          'S09',
          'S10',
          'S11',
          'S12',
        ],
        true
      ),
    },
    async ({ page }) => {
      const h = givenHealth('Malawi HIV', { [OTHER]: 'owner' });
      exec(
        `update projects set scheduled_deletion = now() + interval '7 days' where id = '${h.project.id}'`
      );
      await projectScope.S04(page, h.path, OTHER);
    }
  );

  test(
    'shared-project-scope@S05 on workflow-health',
    {
      tag: tagFor(
        'S05',
        [
          'S01',
          'S02',
          'S03',
          'S04',
          'S05',
          'S06',
          'S07',
          'S08',
          'S09',
          'S10',
          'S11',
          'S12',
        ],
        true
      ),
    },
    async ({ page }) => {
      const h = givenHealth();
      exec(
        `update projects set requires_mfa = true where id = '${h.project.id}'`
      );
      removeMfaOf(ME);
      await projectScope.S05(page, h.path, ME);
    }
  );

  test(
    'shared-project-scope@S06 on workflow-health',
    {
      tag: [
        tagFor(
          'S06',
          [
            'S01',
            'S02',
            'S03',
            'S04',
            'S05',
            'S06',
            'S07',
            'S08',
            'S09',
            'S10',
            'S11',
            'S12',
          ],
          true
        ),
        '@serial',
      ].flat(),
    },
    async ({ page }) => {
      const h = givenHealth('Malawi HIV', { [OTHER]: 'owner' });
      exec(
        `update projects set allow_support_access = true where id = '${h.project.id}'`
      );
      cleanups.push(makeSupportUser(ME));
      await projectScope.S06(
        page,
        h.path,
        ME,
        page.getByRole('heading', { name: 'Daily sync', level: 1 })
      );
    }
  );

  test(
    'shared-project-scope@S07 on workflow-health',
    {
      tag: tagFor(
        'S07',
        [
          'S01',
          'S02',
          'S03',
          'S04',
          'S05',
          'S06',
          'S07',
          'S08',
          'S09',
          'S10',
          'S11',
          'S12',
        ],
        true
      ),
    },
    async ({ page }) => {
      const h = givenHealth('Malawi HIV', { [ME]: 'editor', [OTHER]: 'owner' });
      await projectScope.S07(page, h.path, ME, () =>
        removeMemberOnNode(h.project.id, ME, OTHER)
      );
    }
  );

  test(
    'shared-project-scope@S08 on workflow-health',
    {
      tag: tagFor(
        'S08',
        [
          'S01',
          'S02',
          'S03',
          'S04',
          'S05',
          'S06',
          'S07',
          'S08',
          'S09',
          'S10',
          'S11',
          'S12',
        ],
        true
      ),
    },
    async ({ page }) => {
      const h = givenHealth('Malawi HIV', { [ME]: 'admin', [OTHER]: 'owner' });
      await projectScope.S08(
        page,
        `${h.path}?x=1`,
        ME,
        () => changeRoleOnNode(h.project.id, ME, 'viewer'),
        healthRoot(page)
      );
    }
  );

  test(
    'shared-project-scope@S09 on workflow-health',
    {
      tag: [
        tagFor(
          'S09',
          [
            'S01',
            'S02',
            'S03',
            'S04',
            'S05',
            'S06',
            'S07',
            'S08',
            'S09',
            'S10',
            'S11',
            'S12',
          ],
          true
        ),
        '@serial',
      ].flat(),
    },
    async ({ page }) => {
      const h = givenHealth('Malawi HIV', { [OTHER]: 'owner' });
      exec(
        `update projects set allow_support_access = true where id = '${h.project.id}'`
      );
      cleanups.push(makeSupportUser(ME));
      await projectScope.S09(page, h.path, ME, () =>
        setSupportAccessOnNode(h.project.id, false)
      );
    }
  );

  test(
    'shared-project-scope@S10 on workflow-health',
    {
      tag: tagFor(
        'S10',
        [
          'S01',
          'S02',
          'S03',
          'S04',
          'S05',
          'S06',
          'S07',
          'S08',
          'S09',
          'S10',
          'S11',
          'S12',
        ],
        true
      ),
    },
    async ({ page }) => {
      const h = givenHealth('Malawi HIV', { [ME]: 'editor', [OTHER]: 'owner' });
      await projectScope.S10(page, h.path, ME, () =>
        scheduleDeletionOnNode(h.project.id)
      );
    }
  );

  // The preference is data, so the variant is seeded rather than skipped
  test(
    'shared-project-scope@S11 on workflow-health',
    {
      tag: tagFor(
        'S11',
        [
          'S01',
          'S02',
          'S03',
          'S04',
          'S05',
          'S06',
          'S07',
          'S08',
          'S09',
          'S10',
          'S11',
          'S12',
        ],
        true
      ),
    },
    async ({ page }) => {
      const parent = given('Malawi HIV', { [ME]: 'editor' });
      const parentWorkflow = seedWorkflow(parent.id);
      const sandbox = given('dev', { [ME]: 'editor' });
      exec(
        `update projects set parent_id = '${parent.id}' where id = '${sandbox.id}'`
      );
      const sandboxWorkflow = seedWorkflow(sandbox.id);
      setPreferences(ME, { experimental_features: true });

      await projectScope.S11(
        page,
        healthPath(sandbox.id, sandboxWorkflow.id),
        ME,
        () => scheduleDeletionOnNode(sandbox.id),
        `/projects/${parent.id}/w/${parentWorkflow.id}`
      );
    }
  );

  test(
    'shared-project-scope@S12 on workflow-health',
    {
      tag: tagFor(
        'S12',
        [
          'S01',
          'S02',
          'S03',
          'S04',
          'S05',
          'S06',
          'S07',
          'S08',
          'S09',
          'S10',
          'S11',
          'S12',
        ],
        true
      ),
    },
    async ({ page }) => {
      const h = givenHealth();
      await projectScope.S12(
        page,
        h.path,
        ME,
        () => deleteWorkflowOnNode(h.wf.id, OTHER),
        `/projects/${h.project.id}/w`
      );
    }
  );
});

// Inherited from shared-project-header: the breadcrumbs, picker and side menu
// on the health page. The picker scenarios seed their own "Malawi HIV", so the
// project this page belongs to has another name.
test.describe('shared-project-header', () => {
  const HOST = 'Health host';

  // shared-project-header S01 opens a run's page; the same breadcrumb
  // contract on this page ends in "Health", which is no link
  test(
    'shared-project-header@S01 on workflow-health',
    {
      tag: tagFor(
        'S01',
        [
          'S01',
          'S02',
          'S03',
          'S04',
          'S05',
          'S06',
          'S07',
          'S08',
          'S09',
          'S10',
          'S11',
          'S12',
          'S13',
          'S15',
          'S16',
          'S17',
          'S18',
        ],
        true
      ),
    },
    async ({ page }) => {
      const h = givenHealth(HOST);
      await projectHeader.S01(page, h.path, ME, HOST, [
        { name: 'Workflows', href: `/projects/${h.project.id}/w` },
        {
          name: 'Daily sync',
          href: `/projects/${h.project.id}/w/${h.wf.id}`,
        },
        { name: 'Health' },
      ]);
    }
  );

  test(
    'shared-project-header@S02 on workflow-health',
    {
      tag: tagFor(
        'S02',
        [
          'S01',
          'S02',
          'S03',
          'S04',
          'S05',
          'S06',
          'S07',
          'S08',
          'S09',
          'S10',
          'S11',
          'S12',
          'S13',
          'S15',
          'S16',
          'S17',
          'S18',
        ],
        true
      ),
    },
    async ({ page }) => {
      const h = givenHealth(HOST);
      await projectHeader.S02(page, ME, { path: h.path, project: HOST });
    }
  );

  test(
    'shared-project-header@S03 on workflow-health',
    {
      tag: tagFor(
        'S03',
        [
          'S01',
          'S02',
          'S03',
          'S04',
          'S05',
          'S06',
          'S07',
          'S08',
          'S09',
          'S10',
          'S11',
          'S12',
          'S13',
          'S15',
          'S16',
          'S17',
          'S18',
        ],
        true
      ),
    },
    async ({ page }) => {
      const parent = given(HOST, { [ME]: 'editor' });
      const sandbox = given('dev', { [ME]: 'editor' });
      exec(`update projects set parent_id = '${parent.id}', color = '#E33D63'
            where id = '${sandbox.id}'`);
      const wf = seedWorkflow(sandbox.id);
      await projectHeader.S03(page, ME, {
        path: healthPath(sandbox.id, wf.id),
        label: `${HOST}:dev`,
      });
    }
  );

  for (const id of ['S04', 'S05', 'S06', 'S08'] as const)
    test(
      `shared-project-header@${id} on workflow-health`,
      {
        tag: tagFor(
          id,
          [
            'S01',
            'S02',
            'S03',
            'S04',
            'S05',
            'S06',
            'S07',
            'S08',
            'S09',
            'S10',
            'S11',
            'S12',
            'S13',
            'S15',
            'S16',
            'S17',
            'S18',
          ],
          true
        ),
      },
      async ({ page }) => {
        const h = givenHealth(HOST);
        await projectHeader[id](page, h.path, ME);
      }
    );

  // A support user sees every project that allows support access
  test(
    'shared-project-header@S07 on workflow-health',
    {
      tag: [
        tagFor(
          'S07',
          [
            'S01',
            'S02',
            'S03',
            'S04',
            'S05',
            'S06',
            'S07',
            'S08',
            'S09',
            'S10',
            'S11',
            'S12',
            'S13',
            'S15',
            'S16',
            'S17',
            'S18',
          ],
          true
        ),
        '@serial',
      ].flat(),
    },
    async ({ page }) => {
      const h = givenHealth(HOST);
      await projectHeader.S07(page, h.path, ME);
    }
  );

  // shared-project-header S09 starts on a project settings page, whatever
  // page hosts the header (see the shared step)
  test(
    'shared-project-header@S09 on workflow-health',
    {
      tag: tagFor(
        'S09',
        [
          'S01',
          'S02',
          'S03',
          'S04',
          'S05',
          'S06',
          'S07',
          'S08',
          'S09',
          'S10',
          'S11',
          'S12',
          'S13',
          'S15',
          'S16',
          'S17',
          'S18',
        ],
        true
      ),
    },
    async ({ page }) => {
      await projectHeader.S09(page, ME);
    }
  );

  // The Examples row "a workflow's editor | the workflows page": like the
  // editor, this page belongs to one workflow of the project
  test(
    'shared-project-header@S10 on workflow-health',
    {
      tag: tagFor(
        'S10',
        [
          'S01',
          'S02',
          'S03',
          'S04',
          'S05',
          'S06',
          'S07',
          'S08',
          'S09',
          'S10',
          'S11',
          'S12',
          'S13',
          'S15',
          'S16',
          'S17',
          'S18',
        ],
        true
      ),
    },
    async ({ page }) => {
      const h = givenHealth(HOST);
      await projectHeader.S10(page, h.path, ME, '/w');
    }
  );

  for (const id of ['S11', 'S12', 'S13', 'S18'] as const)
    test(
      `shared-project-header@${id} on workflow-health`,
      {
        tag: tagFor(
          id,
          [
            'S01',
            'S02',
            'S03',
            'S04',
            'S05',
            'S06',
            'S07',
            'S08',
            'S09',
            'S10',
            'S11',
            'S12',
            'S13',
            'S15',
            'S16',
            'S17',
            'S18',
          ],
          true
        ),
      },
      async ({ page }) => {
        const h = givenHealth(HOST);
        await projectHeader[id](page, h.path, ME);
      }
    );

  test(
    'shared-project-header@S14 on workflow-health',
    {
      tag: tagFor(
        'S14',
        [
          'S01',
          'S02',
          'S03',
          'S04',
          'S05',
          'S06',
          'S07',
          'S08',
          'S09',
          'S10',
          'S11',
          'S12',
          'S13',
          'S15',
          'S16',
          'S17',
          'S18',
        ],
        true
      ),
    },
    () => {
      test.skip(
        true,
        'variant require-email-verification is not configured on this instance'
      );
    }
  );

  // This page highlights "Workflows" in the side menu
  test(
    'shared-project-header@S15 on workflow-health',
    {
      tag: tagFor(
        'S15',
        [
          'S01',
          'S02',
          'S03',
          'S04',
          'S05',
          'S06',
          'S07',
          'S08',
          'S09',
          'S10',
          'S11',
          'S12',
          'S13',
          'S15',
          'S16',
          'S17',
          'S18',
        ],
        true
      ),
    },
    async ({ page }) => {
      const h = givenHealth(HOST);
      await projectHeader.S15(page, h.path, ME, h.project.id, 'Workflows');
    }
  );

  // The preference is data, so the variant is seeded rather than skipped
  test(
    'shared-project-header@S16 on workflow-health',
    {
      tag: tagFor(
        'S16',
        [
          'S01',
          'S02',
          'S03',
          'S04',
          'S05',
          'S06',
          'S07',
          'S08',
          'S09',
          'S10',
          'S11',
          'S12',
          'S13',
          'S15',
          'S16',
          'S17',
          'S18',
        ],
        true
      ),
    },
    async ({ page }) => {
      const h = givenHealth(HOST);
      await projectHeader.S16(page, h.path, ME, { channels: true });
    }
  );

  // A superuser needs a role on the project to open this page at all
  test(
    'shared-project-header@S17 on workflow-health',
    {
      tag: tagFor(
        'S17',
        [
          'S01',
          'S02',
          'S03',
          'S04',
          'S05',
          'S06',
          'S07',
          'S08',
          'S09',
          'S10',
          'S11',
          'S12',
          'S13',
          'S15',
          'S16',
          'S17',
          'S18',
        ],
        true
      ),
    },
    async ({ page }) => {
      const h = givenHealth(HOST, {
        [ME]: 'viewer',
        'super@openfn.org': 'viewer',
      });
      await projectHeader.S17(page, h.path);
    }
  );
});

// Inherited from shared-flash-messages. The page puts no flash of its own;
// the ones it can end up showing arrive on the page it sends people to.
test.describe('shared-flash-messages', () => {
  // Given I have the health page open and another user deletes the workflow:
  // the workflow list I land on shows the info flash "Workflow deleted."
  const FLASH = 'Workflow deleted.';
  async function withDeletion(page: Page) {
    const h = givenHealth();
    // A second workflow keeps the list's table (and its Name header) on screen
    seedWorkflow(h.project.id, 'Other sync');
    await openHealth(page, h);
    const deleteIt = () =>
      Promise.resolve(deleteWorkflowOnNode(h.wf.id, OTHER));
    return { h, deleteIt };
  }

  test(
    'shared-flash-messages@S01 on workflow-health',
    { tag: tagFor('S01', ['S01', 'S02', 'S03', 'S04', 'S05', 'S06'], true) },
    async ({ page }) => {
      const { deleteIt } = await withDeletion(page);
      await flashMessages.S01(page, FLASH, deleteIt);
    }
  );

  // The error flash this page can end up showing: "Workflow not found"
  test(
    'shared-flash-messages@S02 on workflow-health',
    { tag: tagFor('S02', ['S01', 'S02', 'S03', 'S04', 'S05', 'S06'], true) },
    async ({ page }) => {
      const h = givenHealth();
      const other = givenHealth('Kenya TB', { [ME]: 'viewer' });
      await signInAs(page, ME);
      await flashMessages.S02(page, 'Workflow not found', async () => {
        await page.goto(`/projects/${h.project.id}/w/${other.wf.id}/health`);
      });
    }
  );

  test(
    'shared-flash-messages@S03 on workflow-health',
    { tag: tagFor('S03', ['S01', 'S02', 'S03', 'S04', 'S05', 'S06'], true) },
    async ({ page }) => {
      const { deleteIt } = await withDeletion(page);
      await flashMessages.S03(page, FLASH, deleteIt);
    }
  );

  test(
    'shared-flash-messages@S04 on workflow-health',
    { tag: tagFor('S04', ['S01', 'S02', 'S03', 'S04', 'S05', 'S06'], true) },
    async ({ page }) => {
      const { deleteIt } = await withDeletion(page);
      await flashMessages.S04(page, FLASH, deleteIt, async () => {
        // Sorting makes the workflow list render again
        await page.getByRole('columnheader', { name: 'Name' }).click();
        await expect(
          page.getByRole('columnheader', { name: 'Name' })
        ).toBeVisible();
      });
    }
  );

  test(
    'shared-flash-messages@S05 on workflow-health',
    { tag: tagFor('S05', ['S01', 'S02', 'S03', 'S04', 'S05', 'S06'], true) },
    async ({ page }) => {
      const { h, deleteIt } = await withDeletion(page);
      await flashMessages.S05(
        page,
        FLASH,
        deleteIt,
        `/projects/${h.project.id}/w`
      );
    }
  );

  test(
    'shared-flash-messages@S06 on workflow-health',
    { tag: tagFor('S06', ['S01', 'S02', 'S03', 'S04', 'S05', 'S06'], true) },
    async ({ page }) => {
      const h = givenHealth();
      const notMine = givenHealth('Kenya TB', { [OTHER]: 'owner' });
      await openHealth(page, h);

      await flashMessages.S06(
        page,
        () => open(page, notMine.path),
        '/projects',
        // the list of my projects
        page.getByRole('cell', {
          name: manifest().projects[0].name,
          exact: true,
        })
      );
    }
  );

  // shared-flash-messages S07 and S08 are on admin pages and the sign-in form;
  // not_reachable_here does not exclude them, but this page never shows
  // either (see the list below)
});

// Not run on this page, and why (reported as unreachable):
//   shared-flash-messages S07: admin pages only (settings layout).
//   shared-flash-messages S08: sign-in and account forms only.
