// Scenarios from annotations/shared/shared-run-components.md that a LiveView
// page showing runs can reach. The host owns the Given (the runs and steps,
// and who is signed in) and hands each function the elements to look at.
// S15 to S18 are the editor run viewer's React ports and not reachable from
// a LiveView page.
import { expect, type Locator, type Page } from '@playwright/test';

import { carriedMarker, expectAt, runStateOf } from '../steps';

const flash = (page: Page, text: string | RegExp) =>
  page
    .getByRole('alert')
    .or(page.getByRole('status'))
    .filter({ hasText: text });

// What an outcome icon looks like: its colour, and its markup, which differs
// from one icon to the next. The icon is the leftmost element in the row that
// holds no text.
async function iconOf(row: Locator) {
  return row.evaluate(el => {
    const empty = Array.from(el.querySelectorAll('*')).filter(
      n => !(n.textContent ?? '').trim() && n.getBoundingClientRect().width > 0
    );
    const left = Math.min(...empty.map(n => n.getBoundingClientRect().left));
    const icon = empty.find(n => n.getBoundingClientRect().left === left)!;
    // Painted on a canvas to read it as RGB: Tailwind v4 colours are oklch
    const ctx = document.createElement('canvas').getContext('2d')!;
    ctx.fillStyle = getComputedStyle(icon).color;
    ctx.fillRect(0, 0, 1, 1);
    const [r, g, b] = [...ctx.getImageData(0, 0, 1, 1).data];
    return { rgb: [r, g, b], markup: icon.outerHTML };
  });
}

const hueOf = ([r, g, b]: number[]) => {
  const max = Math.max(r, g, b);
  const d = max - Math.min(r, g, b);
  if (d === 0) return NaN;
  const h =
    max === r
      ? (((g - b) / d) % 6) * 60
      : max === g
        ? ((b - r) / d + 2) * 60
        : ((r - g) / d + 4) * 60;
  return (h + 360) % 360;
};

// @S01 States show as labelled pills
//   Given a run in state "available" and another in state "claimed"
//   When I see their status pills
//   Then the first reads "Enqueued" and the second reads "Starting"
//   And a run in state "started" reads "Running" and a failed run reads "Failed"
// `pills` pairs each pill with the label it reads.
export async function S01(_page: Page, pills: [Locator, string][]) {
  for (const [pill, label] of pills) await expect(pill).toHaveText(label);
}

// @S02 Step icons distinguish success, failure, crash and pending
//   Given a run with a pending step, a successful step and a failed step
//   When I look at the step list
//   Then the pending step shows a grey icon, the successful one a green check and the failed one a red cross
export async function S02(
  _page: Page,
  rows: { pending: Locator; success: Locator; failed: Locator }
) {
  const pending = await iconOf(rows.pending);
  const success = await iconOf(rows.success);
  const failed = await iconOf(rows.failed);

  expect(Math.max(...pending.rgb) - Math.min(...pending.rgb)).toBeLessThan(40);
  const green = hueOf(success.rgb);
  expect(green >= 90 && green <= 170, 'success should be green').toBe(true);
  const red = hueOf(failed.rgb);
  expect(red <= 15 || red >= 345, 'failure should be red').toBe(true);
  expect(new Set([pending.markup, success.markup, failed.markup]).size).toBe(3);
}

// @S03 A killed step says why it was killed
//   Given a step with exit reason "kill" and error type "TimeoutError"
//   And another with exit reason "kill" and error type "SecurityError"
//   When I look at the step list
//   Then the first shows a clock icon and the second a shield icon
//   And a step killed with "OOMError" or "StateTooLargeError" shows an exclamation icon
// The shapes cannot be named without their markup, so they are told apart by
// it: each reason has its own icon, and the two memory reasons share one.
export async function S03(
  _page: Page,
  rows: { timeout: Locator; security: Locator; oom: Locator; tooLarge: Locator }
) {
  const timeout = (await iconOf(rows.timeout)).markup;
  const security = (await iconOf(rows.security)).markup;
  const oom = (await iconOf(rows.oom)).markup;
  const tooLarge = (await iconOf(rows.tooLarge)).markup;

  expect(new Set([timeout, security, oom]).size).toBe(3);
  expect(oom).toBe(tooLarge);
}

// @S04 A running item's duration counts up
//   Given a step that started 5 seconds ago and has not finished
//   When I look at its duration
//   Then it reads "5 s"
//   And a second later it reads "6 s"
// The page takes a moment to load, so the starting number is whatever the
// duration reads when first seen.
export async function S04(_page: Page, duration: Locator) {
  const seconds = async () =>
    Number((await duration.innerText()).match(/^(\d+) s$/)?.[1] ?? NaN);
  await expect.poll(seconds).toBeGreaterThan(0);
  const first = await seconds();

  await expect.poll(seconds, { timeout: 5000 }).toBeGreaterThan(first);
}

// @S05 A finished item shows its final duration and an unstarted one says so
//   Given a step that ran for 90 seconds
//   And a run that has not started
//   Then the step's duration reads "1 m"
//   And the run's duration reads "Not started"
export async function S05(_page: Page, step: Locator, run: Locator) {
  await expect(step).toHaveText('1 m');
  await expect(run).toHaveText('Not started');
}

// @S06 Steps carried over from an earlier run are marked
//   Given run "R2" was rerun from the last step of run "R1"
//   When I look at "R2"'s steps
//   Then the steps reused from "R1" are faded with a paperclip whose tooltip says it "was originally executed in a previous run"
//   And the step that ran in "R2" has no paperclip
export async function S06(page: Page, carried: Locator, ran: Locator) {
  // Faded means less opaque than the step that ran, not a particular value
  await expect(ran).toHaveCSS('opacity', '1');
  const opacityOf = (row: Locator) =>
    row.evaluate(el => Number(getComputedStyle(el).opacity));
  expect(await opacityOf(carried)).toBeLessThan(1);
  await expect(carriedMarker(carried)).toHaveCount(1);
  await carriedMarker(carried).hover();
  await expect(page.getByRole('tooltip')).toContainText(
    'was originally executed in a previous run'
  );

  await expect(carriedMarker(ran)).toHaveCount(0);
}

const paramsOf = async (link: Locator) =>
  new URL((await link.getAttribute('href'))!, 'http://lightning.test')
    .searchParams;

// @S07 Links to the workflow open the version the run executed
//   Given a run executed on workflow version 1 and the workflow is now on version 2
//   When I look at the run's workflow link or a step's inspect link
//   Then the link carries "run=<run id>" and "v=1"
//   And when the run executed on the current version the link carries no version
export async function S07(
  _page: Page,
  links: {
    older: Locator;
    olderRun: string;
    version: number;
    current: Locator;
    currentRun: string;
  }
) {
  const older = await paramsOf(links.older);
  expect(older.get('run')).toBe(links.olderRun);
  expect(older.get('v')).toBe(String(links.version));

  const current = await paramsOf(links.current);
  expect(current.get('run')).toBe(links.currentRun);
  expect(current.has('v')).toBe(false);
  expect(current.has('as_run')).toBe(false);
}

// @S08 With experimental features the link pins the run itself
//   Given I have experimental features enabled
//   And a run executed on an older workflow version
//   When I look at its workflow or step inspect link
//   Then the link carries "as_run=<run id>" and no "v"
//   And the flow "flow-open-run-in-editor" starts when I follow it
export async function S08(
  page: Page,
  link: Locator,
  runId: string,
  editorPath: string
) {
  const params = await paramsOf(link);
  expect(params.get('as_run')).toBe(runId);
  expect(params.has('v')).toBe(false);

  await link.click();

  await expectAt(page, editorPath);
}

// @S09 Editor cancels a run no worker has claimed
//   Given I am an editor and run "R" is in state "available"
//   When I click "Cancel" for "R"
//   Then I see "Run cancelled."
//   And "R" is in state "cancelled"
//   And a run updated event is broadcast for "R"
// The event shows in the open page: the run reads "cancelled" in its block.
export async function S09(
  page: Page,
  cancel: Locator,
  runId: string,
  runBlock: Locator
) {
  await cancel.click();

  await expect(flash(page, 'Run cancelled.')).toBeVisible();
  expect(runStateOf(runId)).toBe('cancelled');
  await expect(runBlock).toContainText('cancelled');
  await expect(cancel).toHaveCount(0);
}

// @S10 Cancelling never stops a run a worker has already claimed
//   Given I am an editor with run "R" open while it is "available"
//   And a worker claims "R"
//   When I click "Cancel" for "R"
//   Then I see that the run could not be cancelled
//   And "R" stays in state "claimed"
export async function S10(
  page: Page,
  cancel: Locator,
  runId: string,
  claim: () => void
) {
  claim();

  await cancel.click();

  await expect(flash(page, /could not be cancelled/)).toBeVisible();
  expect(runStateOf(runId)).toBe('claimed');
}

// @S11 A run from another project cannot be cancelled
//   Given I am an editor on project "Malawi HIV"
//   And run "R" is "available" in project "Kenya TB"
//   When I send "cancel-run" for "R" from a "Malawi HIV" page
//   Then I see "Run not found."
//   And "R" stays "available"
export async function S11(
  page: Page,
  send: () => Promise<void>,
  runId: string
) {
  await send();

  await expect(flash(page, 'Run not found.')).toBeVisible();
  expect(runStateOf(runId)).toBe('available');
}

// @S12 Cancel is only offered on available runs to people who can run workflows
//   Given run "R" is "available"
//   When a viewer opens the run page
//   Then there is no cancel button
//   And when "R" is "claimed", "started" or finished, no one sees a cancel button
// The host opens the page as the person and with the runs named; this is the
// Then.
export async function S12(_page: Page, cancelButtons: Locator) {
  await expect(cancelButtons).toHaveCount(0);
}

// @S13 Retention tooltips point admins to the setting and others to an admin
//   Given a finished step whose input was not stored because of the project's retention policy
//   When an admin hovers its disabled rerun icon
//   Then the tooltip says "This work order cannot be rerun since no input data has been stored"
//   And it has a "Go to data storage settings" link to "/projects/<project_id>/settings#data-storage"
//   When an editor hovers it
//   Then the tooltip says "For more information, contact one of your project admins."
export async function S13(
  admin: { page: Page; icon: Locator },
  editor: { page: Page; icon: Locator },
  projectId: string
) {
  await admin.icon.hover();
  const adminTip = admin.page.getByRole('tooltip');
  await expect(adminTip).toContainText(
    'This work order cannot be rerun since no input data has been stored'
  );
  await expect(
    adminTip.getByRole('link', { name: 'Go to data storage settings' })
  ).toHaveAttribute('href', `/projects/${projectId}/settings#data-storage`);

  await editor.icon.hover();
  const editorTip = editor.page.getByRole('tooltip');
  await expect(editorTip).toContainText(
    'For more information, contact one of your project admins.'
  );
  await expect(editorTip.getByRole('link')).toHaveCount(0);
}

// @S14 A step whose job was deleted cannot be rerun
//   Given a finished step whose job has since been deleted
//   And its input is still stored
//   When an editor hovers its rerun icon
//   Then the icon is greyed out and not clickable
//   And the tooltip says "This step has been deleted and cannot be retried"
// `runCount` reads how many runs the work order has; a working icon would add
// one within a moment of the click.
export async function S14(page: Page, icon: Locator, runCount: () => number) {
  await icon.hover();
  await expect(page.getByRole('tooltip')).toContainText(
    'This step has been deleted and cannot be retried'
  );

  const before = runCount();
  await icon.click();
  await page.waitForTimeout(1500);

  expect(runCount()).toBe(before);
  // An info toast is role=status, but so is the tooltip's own span
  await expect(
    page.getByRole('alert').or(page.locator('[data-ui="toast"]'))
  ).toHaveCount(0);
}
