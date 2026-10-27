// Scenarios from annotations/shared/shared-log-viewer.md, as the run page
// shows them (the editor's run viewer is its own page, with its own log
// panel). The host page owns the Given: it seeds the run with the `given`
// lines below and opens it. The functions hold the When and Then. The viewer
// is one component in each version, so what knows how it is built (Monaco's
// drawn lines and gutter marks, the level control) lives at the top of this
// file rather than in each host's page helper.
import { expect, type Page } from '@playwright/test';

// The log's editor. Both versions draw the log in a read-only Monaco, on
// screen while the Log tab is open.
export const logEditor = (page: Page) =>
  page.locator('.monaco-editor').filter({ visible: true });

// The drawn lines, top to bottom, each with whether its gutter is marked.
// Monaco draws only the lines in view, and spaces as no-break spaces, so keep
// logs short. A gutter mark is a line decoration on the line's margin row.
async function drawn(page: Page) {
  if ((await logEditor(page).count()) === 0) return [];
  return logEditor(page).evaluate(el => {
    const top = (n: Element) => parseFloat((n as HTMLElement).style.top);
    const marked = new Set(
      Array.from(
        el.querySelectorAll('.margin-view-overlays > div, .view-overlays > div')
      )
        .filter(row => row.querySelector('.cldr, .cdr, .cgmr'))
        .map(top)
    );
    return Array.from(el.querySelectorAll('.view-line'))
      .sort((a, b) => top(a) - top(b))
      .map(line => ({
        text: (line.textContent ?? '').replace(/\u00a0/g, ' '),
        marked: marked.has(top(line)),
      }));
  });
}

// The log as shown, one entry per drawn line; an empty log has none
export async function logLines(page: Page) {
  const lines = (await drawn(page)).map(l => l.text);
  return lines.length === 1 && !lines[0] ? [] : lines;
}

// The drawn lines marked in the gutter
export const markedLines = async (page: Page) =>
  (await drawn(page)).filter(l => l.marked).map(l => l.text);

// The level control: today a button that opens a list of levels, the
// design system's a menu button named "Log level". Both show the level.
export const levelFilter = (page: Page) =>
  page
    .getByRole('button', { name: 'Log level' })
    .or(page.locator('button[aria-haspopup="listbox"]'))
    .first();

// When I choose <level> in the log filter
export async function chooseLevel(page: Page, level: string) {
  await levelFilter(page).click();
  await page
    .getByRole('option', { name: level, exact: true })
    .or(page.getByRole('menuitem', { name: level, exact: true }))
    .first()
    .click();
}

// Then the filter reads <level>
export const expectLevel = (page: Page, level: string) =>
  expect(levelFilter(page)).toHaveText(new RegExp(`^\\s*${level}\\s*$`));

export const given = {
  S01: {
    source: 'JOB',
    // logged in this order, the second one a second earlier
    lines: [
      { message: 'Posted batch 1', at: 2 },
      { message: 'Fetched 12 patients', at: 1 },
    ],
    shown: ['JOB Fetched 12 patients', 'JOB Posted batch 1'],
  },
  S02: {
    json: '{"patients":12,"status":"ok"}',
    notJson: '{patients: 12}',
  },
  S03: { debug: 'Checked the cache', info: 'Fetched 12 patients' },
};

// @S01 Every logged line is shown once, in time order, with its source
//   Given a finished run whose job logged "Posted batch 1" at 10:00:02 and "Fetched 12 patients" at 10:00:01 from source "JOB"
//   And the line "Fetched 12 patients" is delivered to the viewer twice
//   When I open its log on the run page or in the workflow editor run viewer
//   Then I see "JOB Fetched 12 patients" followed by "JOB Posted batch 1"
//   And "Fetched 12 patients" appears once
// `redeliver` sends the line again once the log has loaded.
export async function S01(page: Page, redeliver?: () => void) {
  await expect.poll(() => logLines(page)).toEqual(given.S01.shown);
  if (!redeliver) return;

  redeliver();
  await page.waitForTimeout(1500);

  expect(await logLines(page)).toEqual(given.S01.shown);
}

// @S02 JSON a job logged is shown indented
//   Given a finished run whose job logged '{"patients":12,"status":"ok"}'
//   When I open its log
//   Then the line is shown across several lines with two-space indentation
//   And a message that only looks like JSON but does not parse is shown as logged
// The host logs the JSON, then the message that does not parse, from "R/T".
export async function S02(page: Page) {
  await expect
    .poll(() => logLines(page))
    .toEqual([
      'R/T {',
      '  "patients": 12,',
      '  "status": "ok"',
      '}',
      `R/T ${given.S02.notJson}`,
    ]);
}

// @S03 The level filter hides lower-level lines
//   Given a finished run that logged a "debug" line and an "info" line
//   And I have never chosen a log level
//   When I open its log
//   Then the filter reads "info" and only the "info" line is shown
//   When I choose "debug"
//   Then both lines are shown
//   When I choose "warn"
//   Then neither line is shown
// The host logs the debug line first, both from "R/T".
export async function S03(page: Page) {
  const { debug, info } = given.S03;
  await expectLevel(page, 'info');
  await expect.poll(() => logLines(page)).toEqual([`R/T ${info}`]);

  await chooseLevel(page, 'debug');
  await expect
    .poll(() => logLines(page))
    .toEqual([`R/T ${debug}`, `R/T ${info}`]);

  await chooseLevel(page, 'warn');
  await expect
    .poll(async () => (await logLines(page)).join(''))
    .not.toMatch(new RegExp(`${debug}|${info}`));
}

// @S04 On the run page the chosen level is remembered
//   Given I am on the run page for run "R1"
//   When I choose "debug" in the log filter
//   Then my preference "desired_log_level" is "debug"
//   And when I open the run page for run "R2", the filter reads "debug" and debug lines are shown
// R2 logged given.S03.debug. `preference` reads my saved level.
export async function S04(
  page: Page,
  preference: () => unknown,
  openR2: () => Promise<void>
) {
  await chooseLevel(page, 'debug');

  await expect.poll(preference).toBe('debug');
  await openR2();
  await expectLevel(page, 'debug');
  await expect.poll(() => logLines(page)).toContain(`R/T ${given.S03.debug}`);
}

// @S05 Selecting a step marks its lines and brings them into view
//   Given a finished run whose steps "Fetch" and "Transform" each logged several lines, "Fetch" first
//   And the log has finished loading
//   When I select "Transform"
//   Then "Transform"'s lines are marked in the gutter
//   And the log scrolls so that "Transform"'s first line is near the top
//   When I clear the step selection
//   Then no lines are marked
// `transform` is every line Transform logged, as shown. Monaco draws only the
// lines in view, so a marked line that is drawn has been brought into view.
export async function S05(
  page: Page,
  transform: string[],
  select: () => Promise<void>,
  clear: () => Promise<void>
) {
  await expect
    .poll(async () => (await logLines(page)).length)
    .toBeGreaterThan(transform.length);

  await select();
  await expect.poll(() => markedLines(page)).toEqual(transform);

  await clear();
  await expect.poll(() => markedLines(page)).toEqual([]);
}

// @S06 A finished run that logged nothing says so
//   Given a run in state "lost" with no log lines
//   When I open its log on the run page or in the workflow editor run viewer
//   Then I see "No logs were received for this run."
//   And no level filter is shown on the run page
export async function S06(page: Page) {
  await expect(
    page.getByText('No logs were received for this run.')
  ).toBeVisible();
  await expect(levelFilter(page)).toHaveCount(0);
}
