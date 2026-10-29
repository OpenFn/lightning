// The workflow editor's manual run panel
// (annotations/views/workflow-editor-manual-run.md): pick or write an input and
// run the workflow from a step or trigger. Everything here knows how today's
// panel is built: the URL params that open it, its pill tabs, the Monaco input
// editor, the uploader, the earlier-inputs list and its unlabelled filter and
// header buttons, and the JSON endpoints behind it. Specs find things through
// these helpers, so a rebuild only changes this file. Editor-wide helpers are
// in ./workflow-editor, the run controls in ../shared/run-retry-controls.
import { expect, type Locator, type Page } from '@playwright/test';

import { postAsPage } from '../shared/run-retry-controls';
import {
  exec,
  onNode,
  seedDataclip,
  seedRun,
  sql,
  type DataclipSeed,
  type EditorWorkflow,
  type RunSeed,
} from '../steps';

import { pathBetween } from './workflow-editor';
import { panelQuery } from './workflow-editor-inspectors';

// ---------------------------------------------------------------------------
// Opening the panel
// ---------------------------------------------------------------------------

export type RunPanelParams = {
  job?: string;
  trigger?: string;
  /** the run being followed */
  run?: string;
  /** an input to preselect */
  dataclip?: string;
  /** a version pin */
  v?: number;
  runMode?: 'custom-input';
};

// The query that opens the run panel with <params>
export const runPanelQuery = (params: RunPanelParams) =>
  panelQuery({
    panel: 'run',
    ...Object.fromEntries(
      Object.entries(params).filter(([, v]) => v !== undefined)
    ),
  } as Record<string, string | number>);

// The panel's titles: "Run from <step>", "Run from Trigger (<type>)", "Pick a
// custom input", or "Run Workflow"
const TITLE = /^(Run from .+|Pick a custom input|Run Workflow)$/;

// The panel's heading
export const runPanelTitle = (page: Page) =>
  page.getByRole('heading', { level: 2, name: TITLE });

// The open run panel. Today it is an unnamed card, found as the card around
// its heading.
export const runPanel = (page: Page) =>
  page
    .getByRole('complementary', { name: TITLE })
    .or(
      runPanelTitle(page).locator(
        'xpath=ancestor::div[contains(concat(" ", normalize-space(@class), " "), " rounded-lg ")][1]'
      )
    )
    .first();

// When I choose "Run with custom input" from the header's run menu
export async function runWithCustomInput(page: Page, header: Locator) {
  await header.getByRole('button', { name: /^Open (run )?options$/ }).click();
  await page
    .getByRole('menuitem', { name: 'Run with custom input' })
    .or(page.getByRole('button', { name: 'Run with custom input' }))
    .first()
    .click();
}

// When I open the run control's chevron and choose "Run (New Work Order)"
export async function chooseNewWorkOrder(page: Page, surface: Locator) {
  await surface.getByRole('button', { name: /^Open (run )?options$/ }).click();
  await page
    .getByRole('menuitem', { name: 'Run (New Work Order)' })
    .or(page.getByRole('button', { name: 'Run (New Work Order)' }))
    .first()
    .click();
}

// When I select the path from <from> to <to> on the canvas
export async function selectPath(page: Page, from: string, to: string) {
  await (await pathBetween(page, from, to)).click({ force: true });
}

// ---------------------------------------------------------------------------
// The input tabs: Empty, New, Existing
// ---------------------------------------------------------------------------

export type InputTab = 'Empty' | 'New' | 'Existing';

export const inputTab = (page: Page, name: InputTab) =>
  runPanel(page)
    .getByRole('tab', { name })
    .or(
      runPanel(page)
        .getByRole('navigation', { name: 'Tabs' })
        .getByRole('button', { name })
    )
    .first();

// The input tabs, whichever is open; hidden while an input is selected
export const inputTabs = (page: Page) =>
  runPanel(page)
    .getByRole('tablist')
    .or(runPanel(page).getByRole('navigation', { name: 'Tabs' }))
    .first();

// The name of the open tab. Today the pills mark it aria-current.
export async function currentTab(page: Page) {
  const open = runPanel(page)
    .locator('[aria-current="page"], [role="tab"][aria-selected="true"]')
    .first();
  return (await open.innerText()).trim();
}

// ---------------------------------------------------------------------------
// The "New" tab: a JSON editor (Monaco today) and a file uploader
// ---------------------------------------------------------------------------

const inputEditor = (page: Page) =>
  runPanel(page).locator('.monaco-editor').first();

// When the input editor holds <text>: pasted over whatever it held, as a user
// would. Typing would have Monaco close brackets and quotes for me.
export async function setCustomInput(page: Page, text: string) {
  await page.context().grantPermissions(['clipboard-read', 'clipboard-write']);
  await inputEditor(page).click();
  // A key pressed before Monaco takes focus is lost
  await expect(inputEditor(page)).toHaveClass(/\bfocused\b/);
  await expect(async () => {
    await page.keyboard.press('ControlOrMeta+A');
    await page.keyboard.press('Backspace');
    expect((await customInputText(page)).trim()).toBe('');
  }).toPass();
  if (!text) return;
  await page.evaluate(t => navigator.clipboard.writeText(t), text);
  await page.keyboard.press('ControlOrMeta+V');
}

// Puts my cursor in the input editor
export const focusCustomInput = (page: Page) => inputEditor(page).click();

// The text the input editor shows, one line per drawn line (Monaco draws
// spaces as no-break spaces)
export async function customInputText(page: Page) {
  const lines = inputEditor(page).locator('.view-line');
  return (await lines.allInnerTexts()).join('\n').replace(/\u00a0/g, ' ');
}

type FileSeed = { name: string; content: string; mimeType: string };

// When I upload <file> through "Upload a file"
export async function uploadInputFile(page: Page, file: FileSeed) {
  await runPanel(page)
    .locator('input[type="file"]')
    .setInputFiles({
      name: file.name,
      mimeType: file.mimeType,
      buffer: Buffer.from(file.content),
    });
}

// When I drop <file> onto the upload area
export async function dropInputFile(page: Page, file: FileSeed) {
  const area = runPanel(page)
    .getByText('or drag and drop')
    .locator('xpath=ancestor::div[contains(@class, "border-dashed")][1]');
  const dataTransfer = await page.evaluateHandle(
    ({ name, content, type }) => {
      const dt = new DataTransfer();
      dt.items.add(new File([content], name, { type }));
      return dt;
    },
    { name: file.name, content: file.content, type: file.mimeType }
  );
  await area.dispatchEvent('dragover', { dataTransfer });
  await area.dispatchEvent('drop', { dataTransfer });
}

// ---------------------------------------------------------------------------
// The "Existing" tab: earlier inputs, search and filters
// ---------------------------------------------------------------------------

// The earlier inputs listed, top to bottom. Today each is a clickable card.
export const inputRows = (page: Page) =>
  runPanel(page)
    .getByRole('option')
    .or(runPanel(page).locator('div.border.rounded-md.cursor-pointer'));

// The listed input that shows <label> (its name or short id)
export const inputRow = (page: Page, label: string) =>
  inputRows(page).filter({ hasText: label }).first();

// What each listed input is called (its name, or the first 8 characters of
// its id), top to bottom
export const listedInputNames = (page: Page) =>
  inputRows(page).locator('span.font-mono').allInnerTexts();

// The mark on a listed input that says <title> ("Current dataclip for this
// step", "Next state that will be used for cron execution")
export const markOn = (row: Locator, title: string) => row.getByTitle(title);

const searchBox = (page: Page) =>
  runPanel(page).getByPlaceholder('Search names or UUID prefixes');

// When I type <term> in the search box and press Enter
export async function searchInputs(page: Page, term: string) {
  await searchBox(page).fill(term);
  await searchBox(page).press('Enter');
}

// Puts my cursor in the search box
export const focusSearch = (page: Page) => searchBox(page).click();

// The date, type and named-only filter buttons. Today they are icon buttons
// with no name, in that order after "Search".
const filterButton = (page: Page, i: 0 | 1 | 2, name: RegExp) =>
  runPanel(page)
    .getByRole('button', { name })
    .or(
      runPanel(page)
        .getByRole('button', { name: 'Search', exact: true })
        .locator('xpath=../following-sibling::div[1]//button')
        .nth(i)
    )
    .first();

// When I choose <type> ("http request", "global", ...) in the type filter
export async function filterByType(page: Page, type: string) {
  await filterButton(page, 1, /type/i).click();
  await runPanel(page)
    .getByRole('option', { name: type })
    .or(runPanel(page).locator('li').filter({ hasText: type }))
    .first()
    .click();
}

// When I set "Created After" and "Created Before" (local datetimes,
// "YYYY-MM-DDTHH:MM")
export async function filterByDates(
  page: Page,
  { after, before }: { after: string; before: string }
) {
  await filterButton(page, 0, /date/i).click();
  await runPanel(page).locator('#created-after').fill(after);
  await runPanel(page).locator('#created-before').fill(before);
}

// When I turn on the named-only filter
export const filterNamedOnly = (page: Page) =>
  filterButton(page, 2, /named/i).click();

// The removable pill an active filter shows, by its text
export const filterPill = (page: Page, text: string) =>
  runPanel(page)
    .locator('div')
    .filter({
      hasText: text,
      has: page.getByRole('button', { name: 'Remove' }),
    })
    .last();

// ---------------------------------------------------------------------------
// The selected input: its name, type and date over a preview of its body
// ---------------------------------------------------------------------------

// The selected input's name ("Unnamed" when it has none)
export const selectedInputName = (page: Page) =>
  runPanel(page).getByRole('heading', { level: 3 });

// The selected input's header: its name, type and date
export const selectedInputHeader = (page: Page) =>
  selectedInputName(page).locator(
    'xpath=ancestor::div[contains(@class, "justify-between")][1]'
  );

// The button that unselects the input. Today it is an unlabelled icon
// button, the last in the selected input's header.
export const unselectButton = (page: Page) =>
  runPanel(page)
    .getByRole('button', { name: /unselect|clear (the )?input|deselect/i })
    .or(selectedInputHeader(page).locator('xpath=./button'))
    .first();

// The pencil that renames the input. Today it is an unlabelled icon button
// right after the name.
export const renameButton = (page: Page) =>
  runPanel(page)
    .getByRole('button', { name: /rename|edit (the )?name/i })
    .or(selectedInputName(page).locator('xpath=following-sibling::button[1]'));

// When I rename the selected input to <name> ('' clears it) and press Enter
export async function renameInput(page: Page, name: string) {
  await renameButton(page).click();
  const box = runPanel(page).getByPlaceholder('Dataclip name');
  await box.fill(name);
  await box.press('Enter');
}

// ---------------------------------------------------------------------------
// Errors
// ---------------------------------------------------------------------------

// What the panel shows in place of itself when it fails to draw
export const panelError = (page: Page) =>
  page.getByText('Something went wrong', { exact: true });

// Given the earlier inputs the server sends come back with no type, which
// the selected input's header can't draw
export const breakInputPreview = (page: Page) =>
  page.route(/\/projects\/[^/]+\/jobs\/[^/]+\/dataclips(\?|$)/, async route => {
    const response = await route.fetch();
    const json = (await response.json()) as { data: object[] };
    json.data = json.data.map(d => ({ ...d, type: null }));
    await route.fulfill({ response, json });
  });

// ---------------------------------------------------------------------------
// The endpoints, through the page's own session
// ---------------------------------------------------------------------------

// What the earlier-inputs endpoint answers for step <jobId> through project
// <projectId>
export const listInputsAsPage = (
  page: Page,
  projectId: string,
  jobId: string
) => page.request.get(`/projects/${projectId}/jobs/${jobId}/dataclips`);

export type ManualRunBody = {
  job_id?: string;
  trigger_id?: string;
  dataclip_id?: string;
  custom_body?: string;
};

// What the run endpoint answers when a run of <workflowId> is posted through
// project <projectId>, as the panel would post it
export const postRunAsPage = (
  page: Page,
  projectId: string,
  workflowId: string,
  body: ManualRunBody
) =>
  postAsPage(page, `/projects/${projectId}/workflows/${workflowId}/runs`, body);

// ---------------------------------------------------------------------------
// Reading
// ---------------------------------------------------------------------------

export type StoredDataclip = {
  id: string;
  type: string;
  project_id: string;
  name: string | null;
  body: unknown;
};

export const dataclipOf = (id: string) =>
  sql<StoredDataclip>(
    `select id, type::text as type, project_id, name, body from dataclips where id = '${id}'`
  )[0];

// How many dataclips project <projectId> holds
export const dataclipsIn = (projectId: string) =>
  sql<{ n: number }>(
    `select count(*)::int as n from dataclips where project_id = '${projectId}'`
  )[0].n;

// ---------------------------------------------------------------------------
// Seeding
// ---------------------------------------------------------------------------

const NOW = `(now() at time zone 'utc')`;

export type InputSeed = DataclipSeed & { name?: string };

// Given input <dataclipId> is named <name> ('' unnames it)
export function nameInput(dataclipId: string, name: string) {
  exec(
    `update dataclips set name = ${name ? `$n$${name}$n$` : 'null'} where id = '${dataclipId}'`
  );
}

// Given step <step> of <wf> received these inputs in earlier runs: each a
// dataclip in the project and a finished step of that job that took it.
// Returns their ids. Removing the project's workflow data removes them.
export function seedEarlierInputs(
  wf: EditorWorkflow,
  step: string,
  seeds: InputSeed[]
) {
  return seeds.map(({ name, ...seed }) => {
    const id = seedDataclip(wf.projectId, seed);
    if (name) nameInput(id, name);
    onNode(`
      wf = Lightning.Repo.get!(Lightning.Workflows.Workflow, ${JSON.stringify(wf.id)})
      snap = Lightning.Workflows.Snapshot.get_current_for(wf)
      now = DateTime.utc_now()
      Lightning.Repo.insert!(%Lightning.Invocation.Step{job_id: ${JSON.stringify(wf.steps[step])}, snapshot_id: snap.id,
        input_dataclip_id: ${JSON.stringify(id)}, exit_reason: "success", started_at: now, finished_at: now})
      :ok`);
    return id;
  });
}

// The workflow seedRun built, with paths from its trigger through the jobs
// <order>, so the editor draws it connected and a retry knows what ran
// upstream. Written straight to the database, before anyone opens it: the
// saved version stays the one the run used.
export function connectRunWorkflow(
  workflowId: string,
  projectId: string,
  order: string[]
): EditorWorkflow {
  const jobs = Object.fromEntries(
    sql<{ id: string; name: string }>(
      `select id, name from jobs where workflow_id = '${workflowId}'`
    ).map(j => [j.name, j.id])
  );
  const [trigger] = sql<{ id: string }>(
    `select id from triggers where workflow_id = '${workflowId}'`
  );
  const [{ name }] = sql<{ name: string }>(
    `select name from workflows where id = '${workflowId}'`
  );
  const edge = (
    sourceColumn: string,
    source: string,
    target: string,
    condition: string
  ) =>
    `insert into workflow_edges (id, workflow_id, ${sourceColumn}, target_job_id, condition_type, enabled, inserted_at, updated_at)
       values (gen_random_uuid(), '${workflowId}', '${source}', '${target}', '${condition}', true, ${NOW}, ${NOW});`;
  exec(
    [
      edge('source_trigger_id', trigger.id, jobs[order[0]], 'always'),
      ...order
        .slice(1)
        .map((job, i) =>
          edge('source_job_id', jobs[order[i]], jobs[job], 'on_job_success')
        ),
    ].join('\n')
  );
  return {
    id: workflowId,
    projectId,
    name,
    steps: jobs,
    triggerId: trigger.id,
  };
}

// Given run "R" of workflow "Intake" (or <seed>'s; a trigger, then "Receive", then
// "Fetch"), seeded through Lightning by "<by>": "Receive" took the webhook
// input and its output was "Fetch"'s input. Returns the run, the workflow as
// the editor sees it and "Fetch"'s input. <seed> overrides the run's seed.
export function seedFollowedRun(
  projectId: string,
  by: string,
  seed: RunSeed = {}
) {
  const run = seedRun(
    projectId,
    {
      workflow: 'Intake',
      steps: [
        { name: 'Receive', output: { patient: '123' } },
        { name: 'Fetch', output: { fetched: true } },
      ],
      ...seed,
    },
    by
  );
  const order = (seed.steps ?? [{ name: 'Receive' }, { name: 'Fetch' }]).map(
    s => s.name
  );
  const wf = connectRunWorkflow(run.workflowId, projectId, order);
  return { run, wf, fetchInput: run.outputs.Receive };
}

// Given workflow <workflowId> was deleted where no open editor heard of it
export const deleteQuietly = (workflowId: string) =>
  exec(`update workflows set deleted_at = ${NOW} where id = '${workflowId}'`);

// Given project <projectId> requires its members to use MFA
export const requireMfa = (projectId: string) =>
  exec(`update projects set requires_mfa = true where id = '${projectId}'`);
