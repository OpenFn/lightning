// The workflow editor's run viewer (annotations/views/workflow-editor-run-viewer.md):
// the run's details, its steps, the "Logs", "Input" and "Output" tabs in the
// IDE's right-hand panel, and the run painted onto the canvas. Everything
// here knows how today's viewer is built: the description list, the step
// buttons, Monaco's drawn lines, the waiting overlay, React Flow's nodes and
// edges, the page's preloaded run data. Specs find things through these
// helpers, so a rebuild only changes this file. The IDE around the viewer is
// ./workflow-editor-ide, the canvas ./workflow-editor.
//
// The log and body viewers are shared components (shared/log-viewer.ts,
// shared/dataclip-body-viewer.ts), but their helpers read every Monaco on
// screen, and the IDE always shows the job's code beside the run viewer. The
// readers below do the same, inside the run viewer only.
import type { Locator, Page } from '@playwright/test';

import { exec, sql } from '../steps';

import { node, pathBetween } from './workflow-editor';
import { runChip, runViewer } from './workflow-editor-ide';

// ---------------------------------------------------------------------------
// The run's details and steps
// ---------------------------------------------------------------------------

// The value labelled <label> in the run's details ("Work Order", "Run",
// "Status", "Duration", "Started", "Started by"). Today a description list:
// the value is the element after its label.
export const runDetail = (page: Page, label: string) =>
  runViewer(page)
    .getByText(label, { exact: true })
    .first()
    .locator('xpath=following-sibling::*[1]');

export const statusPill = (page: Page) => runDetail(page, 'Status');
export const runDuration = (page: Page) => runDetail(page, 'Duration');

// The list under "Run Steps"
const stepList = (page: Page) =>
  runViewer(page).getByRole('list', { name: 'Execution steps' });

// Every step in the list, in the order shown. Today each is a button.
export const stepRows = (page: Page) => stepList(page).getByRole('button');

// The step whose job is <name>. Names in a test are distinct, so the first
// that mentions it.
export const stepRow = (page: Page, name: string) =>
  stepRows(page).filter({ hasText: name }).first();

const DURATION = /^\s*(\d+ (ms|s|m)|Not started)\s*$/;

// A step's duration ("532 ms", "3 s", "1 m", "Not started")
export const stepDuration = (page: Page, name: string) =>
  stepRow(page, name).getByText(DURATION).first();

// The mark on a step carried over from an earlier run (a paperclip)
export const carriedMarker = (row: Locator) =>
  row.getByRole('img', {
    name: /Cloned from previous run|originally executed/,
  });

// The step shown as selected, by name; null when none stands out. Today
// nothing tells assistive tech: the selected step is drawn bolder, so a
// rebuild that says so with aria-current or aria-selected is read that way
// first.
export async function selectedStep(page: Page) {
  const rows = await stepRows(page).evaluateAll((buttons, pattern) => {
    const duration = new RegExp(pattern);
    return buttons.map(b => {
      const flagged = ['aria-current', 'aria-selected', 'aria-pressed'].some(
        a => !['', 'false'].includes(b.getAttribute(a) ?? '')
      );
      const walk = document.createTreeWalker(b, NodeFilter.SHOW_TEXT);
      for (let n = walk.nextNode(); n; n = walk.nextNode()) {
        const text = n.textContent?.trim() ?? '';
        if (text && !duration.test(text))
          return {
            name: text,
            flagged,
            weight: Number(getComputedStyle(n.parentElement!).fontWeight),
          };
      }
      return { name: '', flagged, weight: 0 };
    });
  }, DURATION.source);
  const flagged = rows.find(r => r.flagged);
  if (flagged) return flagged.name;
  const boldest = Math.max(...rows.map(r => r.weight));
  const top = rows.filter(r => r.weight === boldest);
  return top.length === 1 ? top[0].name : null;
}

// ---------------------------------------------------------------------------
// The run chip and the panel's look
// ---------------------------------------------------------------------------

// How faded <target> is drawn: the lowest opacity any visible text or shape
// in it is drawn at, counting every ancestor's (1 = not faded). Things drawn
// at 0 (hidden until hovered) do not count.
export const fadeOf = (target: Locator) =>
  target.evaluate(root => {
    const drawn = [root, ...Array.from(root.querySelectorAll('*'))].filter(
      el =>
        el instanceof SVGGeometryElement ||
        Array.from(el.childNodes).some(
          n => n.nodeType === Node.TEXT_NODE && n.textContent!.trim()
        )
    );
    const opacities = drawn
      .map(el => {
        let opacity = 1;
        for (let n: Element | null = el; n; n = n.parentElement)
          opacity *= Number(getComputedStyle(n).opacity);
        return opacity;
      })
      .filter(o => o > 0);
    return opacities.length ? Math.min(...opacities) : 1;
  });

// How faded the run's steps are drawn
export const panelFade = (page: Page) => fadeOf(stepList(page));

// The chip's background colour, the first one behind its text
export const chipLook = (page: Page, runId: string) =>
  runChip(page, runId).evaluate(el => {
    for (let n: Element | null = el; n; n = n.parentElement) {
      const bg = getComputedStyle(n).backgroundColor;
      if (!/^(transparent|rgba\(0, 0, 0, 0\))$/.test(bg)) return bg;
    }
    return '';
  });

// When I point at the run chip
export async function pointAtChip(page: Page, runId: string) {
  await page.mouse.move(0, 0);
  await runChip(page, runId).hover();
}

// ---------------------------------------------------------------------------
// The Logs tab
// ---------------------------------------------------------------------------

// The editor inside the run viewer: the log, or the Input or Output body,
// whichever tab is open (only one is drawn at a time)
const viewerEditor = (page: Page) =>
  runViewer(page).locator('.monaco-editor').first();

// The drawn lines, top to bottom, each with whether its gutter is marked.
// Monaco draws only the lines in view, and spaces as no-break spaces.
async function drawn(page: Page) {
  if ((await viewerEditor(page).count()) === 0) return [];
  return viewerEditor(page).evaluate(el => {
    const top = (n: Element) => parseFloat((n as HTMLElement).style.top);
    const marked = new Set(
      Array.from(
        el.querySelectorAll('.margin-view-overlays > div, .view-overlays > div')
      )
        .filter(row => row.querySelector('.cldr, .cdr, .cgmr'))
        .map(top)
    );
    return Array.from(el.querySelectorAll('.view-lines .view-line'))
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

// The level control. Today a button that opens a list of levels.
export const levelFilter = (page: Page) =>
  runViewer(page)
    .getByRole('button', { name: 'Log level' })
    .or(runViewer(page).locator('button[aria-haspopup="listbox"]'))
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

// The first waiting message ("Waiting for a worker ..."), once typed out
export const waitingMessage = (page: Page, text: string) =>
  runViewer(page).getByText(text, { exact: true });

// The hint typed below the waiting message so far; "" while there is none.
// Today the overlay draws each on its own line, with a blinking cursor.
export const waitingHint = (page: Page, text: string) =>
  waitingMessage(page, text)
    .locator('xpath=ancestor::div[1]/following-sibling::div[1]')
    .textContent({ timeout: 1000 })
    .then(t => (t ?? '').replace(/▌/g, '').trim())
    .catch(() => '');

// ---------------------------------------------------------------------------
// The Input and Output tabs
// ---------------------------------------------------------------------------

// The body shown, as drawn
export const bodyText = async (page: Page) =>
  (await drawn(page)).map(l => l.text).join('\n');

// When I click into the body and type <text>
export async function typeIntoBody(page: Page, text: string) {
  await viewerEditor(page).locator('.view-line').first().click();
  await page.keyboard.type(text);
  await page.keyboard.press('Enter');
}

export const copyButton = (page: Page) =>
  runViewer(page).getByRole('button', { name: 'Copy to clipboard' });

// What says the copy worked: today the button is renamed "Copied to
// clipboard"; the design system's tooltip reads "Copied!"
export const copiedSignal = (page: Page) =>
  runViewer(page)
    .getByRole('button', { name: 'Copied to clipboard' })
    .or(page.getByRole('tooltip').filter({ hasText: 'Copied!' }))
    .first();

// ---------------------------------------------------------------------------
// The run on the canvas
// ---------------------------------------------------------------------------

// The tooltips of the marks drawn on step <name>'s node (its outcome badge,
// its start badge), hovered one at a time. Today the marks are absolutely
// placed beside the node's shape.
export async function nodeTips(page: Page, name: string) {
  const marks = node(page, name).locator('div.absolute');
  const tips: string[] = [];
  for (const mark of await marks.all()) {
    await page.mouse.move(0, 0);
    await mark.hover({ force: true, timeout: 2000 }).catch(() => undefined);
    const tip = page.getByRole('tooltip').first();
    const shown = await tip
      .waitFor({ state: 'visible', timeout: 1000 })
      .then(() => true)
      .catch(() => false);
    if (shown) tips.push(((await tip.textContent()) ?? '').trim());
  }
  await page.mouse.move(0, 0);
  return tips;
}

// The number drawn on a node whose step ran more than once
export const timesRun = (page: Page, name: string) =>
  node(page, name).getByText(/^\s*\d+\s*$/);

export const nodeFade = (page: Page, name: string) => fadeOf(node(page, name));

// How faded the path from <from> to <to> is drawn
export const pathFade = async (page: Page, from: string, to: string) =>
  fadeOf(await pathBetween(page, from, to));

// The run the server put into the page for the canvas to paint before the
// channel connects, or null. Nothing on screen shows it, so it is read from
// the editor's root element (an id both the page and its markup name).
export const preloadedRun = (page: Page) =>
  page
    .locator('#collaborative-editor-react')
    .getAttribute('data-initial-run-data');

// ---------------------------------------------------------------------------
// Seeding
// ---------------------------------------------------------------------------

// The jobs of workflow <workflowId>, name -> id
export const jobsOf = (workflowId: string) =>
  Object.fromEntries(
    sql<{ id: string; name: string }>(
      `select id, name from jobs where workflow_id = '${workflowId}'`
    ).map(j => [j.name, j.id])
  );

// Given step <stepId> kept no input (none could be saved)
export const dropStepInput = (stepId: string) =>
  exec(`update steps set input_dataclip_id = null where id = '${stepId}'`);

// Given step <stepId>'s job ran <times> times in run <runId>: copies of the
// step are added to the run
export function repeatStep(runId: string, stepId: string, times: number) {
  const copy = `with s as (
      insert into steps (id, job_id, snapshot_id, credential_id, input_dataclip_id, output_dataclip_id,
                         exit_reason, error_type, started_at, finished_at, inserted_at, updated_at)
      select gen_random_uuid(), job_id, snapshot_id, credential_id, input_dataclip_id, output_dataclip_id,
             exit_reason, error_type, started_at, finished_at, inserted_at, updated_at
      from steps where id = '${stepId}' returning id)
    insert into run_steps (id, run_id, step_id, inserted_at)
    select gen_random_uuid(), '${runId}', s.id, (now() at time zone 'utc') from s`;
  exec(Array.from({ length: times - 1 }, () => copy).join(';\n'));
}

// Given run <runId> is in state <state> again and has not finished
export const reopenRun = (runId: string, state: string) =>
  exec(
    `update runs set state = '${state}', finished_at = null where id = '${runId}'`
  );
