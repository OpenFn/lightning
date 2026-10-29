// The workflow editor's full-screen code editor (the IDE,
// annotations/views/workflow-editor-ide.md): the job selector, the adaptor
// box, the code editor, the docs and metadata panel, and the right-hand panel
// (history, run panel, run viewer). Everything here knows how today's IDE is
// built: Monaco's drawn lines and remote cursors, the resizable panels, the
// headless listbox, the channel event the metadata explorer waits on. Specs
// find things through these helpers, so a rebuild only changes this file.
// Editor-wide helpers are in ./workflow-editor.
import { expect, type Locator, type Page } from '@playwright/test';
import type * as Y from 'yjs';

import { exec, lastLine, onNode, sql, user } from '../steps';

import { chooseAdaptor, openEditor } from './workflow-editor';

// The IDE waits on the shared document and the job's code
const READY = { timeout: 20000 };

// ---------------------------------------------------------------------------
// Opening and closing
// ---------------------------------------------------------------------------

// The query that opens the IDE on job <job>, with anything else the URL
// carries (run, step, v, as_run)
export const ideQuery = (
  job: string,
  extra: Record<string, string | number> = {}
) =>
  `?${new URLSearchParams(
    Object.entries({ panel: 'editor', job, ...extra }).map(([k, v]) => [
      k,
      String(v),
    ])
  ).toString()}`;

export const closeIdeButton = (page: Page) =>
  page.getByRole('button', { name: 'Close IDE', exact: true });

// The IDE. Today it is an unnamed full-size layer over the canvas, found as
// the innermost layer holding "Close IDE".
export const ide = (page: Page) =>
  page
    .getByRole('region', { name: /code editor|IDE/ })
    .or(
      page
        .locator('div.absolute.inset-0')
        .filter({ has: closeIdeButton(page) })
        .last()
    )
    .first();

// The IDE's own header bar: job selector, adaptor box, Docs, Metadata,
// History, the run control and "Close IDE"
export const ideHeader = (page: Page) =>
  closeIdeButton(page).locator(
    'xpath=ancestor::div[contains(concat(" ", normalize-space(@class), " "), " border-b ")][1]'
  );

// Waits until the IDE shows its job: past "Loading IDE"
export async function ideReady(page: Page) {
  await expect(closeIdeButton(page)).toBeVisible(READY);
  await expect(page.getByText('Loading IDE', { exact: true })).toHaveCount(
    0,
    READY
  );
}

// When I open the IDE on job <job> of workflow <workflowId> (signed in
// already)
export async function openIde(
  page: Page,
  projectId: string,
  workflowId: string,
  job: string,
  extra: Record<string, string | number> = {}
) {
  await openEditor(page, projectId, workflowId, ideQuery(job, extra));
  await ideReady(page);
}

// ---------------------------------------------------------------------------
// The job selector
// ---------------------------------------------------------------------------

// The job selector: today a headless listbox button showing the job's name
export const jobSelector = (page: Page) =>
  ideHeader(page)
    .getByRole('combobox', { name: /job/i })
    .or(ideHeader(page).locator('button[aria-haspopup="listbox"]'))
    .first();

const jobOptions = (page: Page) =>
  page.getByRole('listbox').getByRole('option');

// When I open the job selector — resolves to its choices in order, each with
// whether it is marked as the current job
export async function openJobSelector(page: Page) {
  await jobSelector(page).click();
  await expect(jobOptions(page).first()).toBeVisible();
  return jobOptions(page).evaluateAll(options =>
    options.map(o => ({
      name: (o.textContent ?? '').trim(),
      marked: o.getAttribute('aria-selected') === 'true',
    }))
  );
}

// When I pick job <name> in the job selector
export async function pickJob(page: Page, name: string) {
  if (!(await jobOptions(page).first().isVisible()))
    await jobSelector(page).click();
  await jobOptions(page).filter({ hasText: name }).first().click();
  await expect(jobSelector(page)).toHaveText(new RegExp(name));
}

// ---------------------------------------------------------------------------
// The code editor. Today Monaco: it draws only the lines in view, with
// no-break spaces, so keep seeded code short.
// ---------------------------------------------------------------------------

// The job's code editor (the first Monaco in the IDE; the run viewer's logs
// and inputs come after it)
export const codeEditor = (page: Page) =>
  ide(page).locator('.monaco-editor').first();

// The code as drawn, one entry per line, top to bottom
export const codeLines = (page: Page) =>
  codeEditor(page).evaluate(el => {
    const top = (n: Element) => parseFloat((n as HTMLElement).style.top);
    return Array.from(el.querySelectorAll('.view-lines .view-line'))
      .sort((a, b) => top(a) - top(b))
      .map(l => (l.textContent ?? '').replace(/\u00a0/g, ' '));
  });

export const codeText = async (page: Page) =>
  (await codeLines(page)).join('\n').trimEnd();

// When I put my cursor in the code
export async function focusCode(page: Page) {
  await codeEditor(page).locator('.view-lines').click();
}

// Whether the code editor has the keyboard
export const codeFocused = (page: Page) =>
  codeEditor(page).evaluate(
    el =>
      el.classList.contains('focused') || el.contains(document.activeElement)
  );

// When I put my cursor at the end of line <n>
export async function cursorToEndOfLine(page: Page, n: number) {
  await focusCode(page);
  await page.keyboard.press('ControlOrMeta+Home');
  for (let i = 1; i < n; i++) await page.keyboard.press('ArrowDown');
  await page.keyboard.press('End');
}

// When I put my cursor at the end of the code
export async function cursorToEnd(page: Page) {
  await focusCode(page);
  await page.keyboard.press('ControlOrMeta+End');
}

// When I type <text> where my cursor is. Inserted as one piece, so the
// editor does not add closing brackets or quotes of its own.
export const typeCode = (page: Page, text: string) =>
  page.keyboard.insertText(text);

// When I replace all the code with <text>
export async function replaceCode(page: Page, text: string) {
  await focusCode(page);
  await page.keyboard.press('ControlOrMeta+A');
  await page.keyboard.insertText(text);
}

// The line my cursor is on
export const cursorLine = (page: Page) =>
  codeEditor(page).evaluate(el => {
    const cursor = el.querySelector('.cursors-layer .cursor');
    if (!cursor) return 0;
    const y = cursor.getBoundingClientRect().top + 2;
    const top = (n: Element) => parseFloat((n as HTMLElement).style.top);
    const lines = Array.from(
      el.querySelectorAll('.view-lines .view-line')
    ).sort((a, b) => top(a) - top(b));
    const i = lines.findIndex(l => {
      const r = l.getBoundingClientRect();
      return y >= r.top && y < r.bottom;
    });
    return i + 1;
  });

// The collaborators' cursors drawn in the code: each one's label and the
// line it is on. Today the label is drawn by CSS after the cursor's mark, so
// it is read from the mark's style.
export const remoteCodeCursors = (page: Page) =>
  codeEditor(page).evaluate(el => {
    const top = (n: Element) => parseFloat((n as HTMLElement).style.top);
    const lines = Array.from(
      el.querySelectorAll('.view-lines .view-line')
    ).sort((a, b) => top(a) - top(b));
    return Array.from(el.querySelectorAll('[class*="yRemoteSelectionHead"]'))
      .map(head => {
        const line = head.closest('.view-line');
        return {
          name: getComputedStyle(head, '::after')
            .content.replace(/^"|"$/g, '')
            .trim(),
          line: line ? lines.indexOf(line) + 1 : 0,
        };
      })
      .filter(c => c.name && c.name !== 'none');
  });

// "Loading types", shown while the adaptor's type definitions load
export const loadingTypes = (page: Page) =>
  ide(page).getByText('Loading types', { exact: true });

// The suggestions the editor offers, by label. Today Monaco draws its widgets
// outside the editor.
export const suggestions = (page: Page) =>
  page.locator('.suggest-widget').filter({ visible: true }).getByRole('option');

// The signature help the editor shows inside a call's brackets
export const signatureHelp = (page: Page) =>
  page.locator('.parameter-hints-widget').filter({ visible: true });

// ---------------------------------------------------------------------------
// The adaptor box in the header
// ---------------------------------------------------------------------------

// The adaptor, its version and credential, with "Change adaptor" and "Edit"
// or "Connect". Today an unnamed bordered box in the header.
export const adaptorBox = (page: Page) =>
  ideHeader(page)
    .getByRole('group', { name: 'Adaptor' })
    .or(ideHeader(page).locator('div.rounded-lg.border').first())
    .first();

export const changeAdaptorButton = (box: Locator) =>
  box.getByRole('button', { name: /^Change( adaptor)?$/ });

// When I change the job's adaptor to <search> from the header. "Configure
// connection" opens after; it is closed again.
export async function changeAdaptorTo(page: Page, search: string) {
  await changeAdaptorButton(adaptorBox(page)).click();
  await chooseAdaptor(page, search);
  const configure = page
    .getByRole('dialog')
    .filter({ hasText: 'Configure connection' });
  if (await configure.isVisible({ timeout: 2000 }).catch(() => false))
    await configure.getByRole('button', { name: 'Close', exact: true }).click();
}

// ---------------------------------------------------------------------------
// Docs and metadata
// ---------------------------------------------------------------------------

// The header's "Docs" or "Metadata" button
export const headerToggle = (page: Page, name: 'Docs' | 'Metadata') =>
  ideHeader(page).getByRole('button', { name, exact: true });

// Whether a header toggle is shown as on. Today that is only its
// background colour; a rebuild may say it with aria-pressed.
export async function toggledOn(page: Page, button: Locator) {
  await page.mouse.move(0, 0);
  return button.evaluate(el => {
    const pressed = el.getAttribute('aria-pressed');
    if (pressed) return pressed === 'true';
    const bg = getComputedStyle(el).backgroundColor;
    return !/^(transparent|rgba\(0, 0, 0, 0\))$/.test(bg);
  });
}

// The docs panel's tabs ("Docs", "Metadata"); hidden while it is closed
const docsTabs = (page: Page) =>
  ide(page)
    .getByRole('tablist', { name: /docs/i })
    .or(
      ide(page)
        .getByRole('navigation', { name: 'Tabs' })
        .filter({
          has: page.getByRole('button', { name: 'Docs', exact: true }),
        })
    )
    .first();

// The docs panel, while it is open
export const docsPanel = (page: Page) =>
  docsTabs(page).locator(
    'xpath=ancestor::div[contains(concat(" ", normalize-space(@class), " "), " flex-col ")][1]'
  );

// One of the docs panel's tabs
export const docsTab = (page: Page, name: 'Docs' | 'Metadata') =>
  docsTabs(page)
    .getByRole('tab', { name, exact: true })
    .or(docsTabs(page).getByRole('button', { name, exact: true }))
    .first();

// Whether a tab (docs panel or run viewer) is the one showing
export const tabShowing = (tab: Locator) =>
  tab.evaluate(
    el =>
      el.getAttribute('aria-selected') === 'true' ||
      el.getAttribute('aria-current') === 'page'
  );

export const closeDocsButton = (page: Page) =>
  ide(page).getByRole('button', { name: 'Close docs panel', exact: true });

export const orientationButton = (page: Page) =>
  ide(page).getByRole('button', {
    name: 'Toggle panel orientation',
    exact: true,
  });

// Whether the docs panel sits below the code rather than beside it
export async function docsBelowCode(page: Page) {
  const [code, docs] = [
    await codeEditor(page).boundingBox(),
    await docsPanel(page).boundingBox(),
  ];
  if (!code || !docs) return false;
  return docs.y >= code.y + code.height - 4;
}

// The docs' title: "<adaptor> (<version>)"
export const docsTitle = (page: Page) =>
  docsPanel(page)
    .getByRole('heading', { level: 1 })
    .filter({ hasText: /\(.+\)/ });

// The operations the docs list, in order, by name
export const docsOperations = (page: Page) =>
  docsPanel(page)
    .locator('details > summary')
    .evaluateAll(summaries =>
      summaries
        .map(s => (s.textContent ?? '').replace('✨', '').trim())
        .filter(t => /^\w+\(/.test(t))
        .map(t => t.split('(')[0])
    );

export const docsLink = (page: Page, name: string) =>
  docsPanel(page).getByRole('link', { name, exact: true });

// The first example the docs offer to add: opened, with its code and its
// "ADD" button
export async function firstExample(page: Page) {
  const add = (within: Page | Locator) =>
    within.getByRole('button', { name: 'ADD', exact: true });
  // Closed operations hide their buttons, so match the button by its text
  const operation = docsPanel(page)
    .locator('details')
    .filter({ has: page.locator('button', { hasText: /^ADD$/ }) })
    .first();
  await expect(operation).toBeAttached(READY);
  if (!(await operation.evaluate(d => (d as HTMLDetailsElement).open)))
    await operation.locator('summary').first().click();
  const example = operation
    .locator('section')
    .filter({ has: page.locator('button', { hasText: /^ADD$/ }) })
    .first();
  return {
    add: add(example),
    code: (await example.locator('pre').innerText()).trim(),
  };
}

// The metadata explorer's top-level entity <name>, which opens to show its
// children
export const metadataEntity = (page: Page, name: string | RegExp) =>
  docsPanel(page).locator('summary').filter({ hasText: name }).first();

// The time the metadata was generated. Today it is a date with its meaning in
// a title.
export const metadataGeneratedAt = (page: Page) =>
  docsPanel(page)
    .getByTitle(/^This metadata was generated at /)
    .or(docsPanel(page).getByText(/generated at/i))
    .first();

// ---------------------------------------------------------------------------
// The right-hand panel: history, the run panel and the run viewer
// ---------------------------------------------------------------------------

export const historyButton = (page: Page) =>
  ideHeader(page).getByRole('button', { name: 'History', exact: true });

const short8 = (id: string) => id.slice(0, 8);

// A work order in the history list, by its short id
export const historyWorkOrder = (page: Page, workOrderId: string) =>
  ide(page).getByRole('button', {
    name: `View full details for work order ${short8(workOrderId)}`,
  });

// When I pick run <runId> of work order <workOrderId> in the history list.
// Today a run is picked by clicking its row (its short id is a link to the
// run's own page).
export async function pickHistoryRun(
  page: Page,
  workOrderId: string,
  runId: string
) {
  const runLink = ide(page).getByRole('button', {
    name: `View full details for run ${short8(runId)}`,
  });
  await expect(historyWorkOrder(page, workOrderId)).toBeVisible(READY);
  if (!(await runLink.isVisible())) {
    await historyWorkOrder(page, workOrderId)
      .locator('xpath=..')
      .getByRole('button', { name: /work order details$/ })
      .click();
    // A work order with one run picks that run as it opens
    await expect(runLink.or(runChip(page, runId)).first()).toBeVisible();
    if (await runChip(page, runId).isVisible()) return;
  }
  await runLink
    .locator(
      'xpath=ancestor::div[contains(concat(" ", normalize-space(@class), " "), " cursor-pointer ")][1]'
    )
    .click();
}

// The run viewer's tabs ("Logs", "Input", "Output")
const runTabs = (page: Page) =>
  ide(page)
    .getByRole('tablist', { name: /run/i })
    .or(
      ide(page)
        .getByRole('navigation', { name: 'Tabs' })
        .filter({
          has: page.getByRole('button', { name: 'Logs', exact: true }),
        })
    )
    .first();

export const runTab = (page: Page, name: 'Logs' | 'Input' | 'Output') =>
  runTabs(page)
    .getByRole('tab', { name, exact: true })
    .or(runTabs(page).getByRole('button', { name, exact: true }))
    .first();

// The run viewer, while it shows a run
export const runViewer = (page: Page) =>
  runTabs(page).locator(
    'xpath=ancestor::div[contains(concat(" ", normalize-space(@class), " "), " flex-col ")][1]'
  );

// The chip naming the run the IDE follows ("Run <short id>")
export const runChip = (page: Page, runId: string) =>
  ide(page).getByText(`Run ${runId.slice(0, 7)}`, { exact: true });

// When I close the run chip
export const closeRunChip = (page: Page) =>
  runViewer(page).getByRole('button', { name: 'Remove' }).first().click();

// The log lines the run viewer marks as the selected step's
export const markedLogLines = (page: Page) =>
  runViewer(page)
    .locator('.monaco-editor')
    .first()
    .evaluate(el => {
      const top = (n: Element) => parseFloat((n as HTMLElement).style.top);
      const marked = new Set(
        Array.from(
          el.querySelectorAll(
            '.margin-view-overlays > div, .view-overlays > div'
          )
        )
          .filter(row => row.querySelector('.cldr, .cdr, .cgmr'))
          .map(top)
      );
      return Array.from(el.querySelectorAll('.view-line'))
        .filter(line => marked.has(top(line)))
        .map(line => (line.textContent ?? '').replace(/\u00a0/g, ' '));
    });

// An input choice in the run panel ("Empty", "Existing", ...)
export const inputChoice = (page: Page, name: string) =>
  ide(page)
    .getByRole('tab', { name, exact: true })
    .or(ide(page).getByRole('button', { name, exact: true }))
    .first();

// When I open the run panel from the header's "Run"
export async function openRunPanel(page: Page) {
  await ideHeader(page)
    .getByRole('button', { name: /^\s*Run\s*$/ })
    .click();
  await expect(inputChoice(page, 'Empty')).toBeVisible();
}

// The warning that the run executed another version
export const versionWarning = (page: Page) =>
  ide(page).getByText(/^This run took place on version \d+\.$/);

// The banner saying I am in a sandbox
export const sandboxBanner = (page: Page) =>
  ide(page).getByText(/You are currently working in the sandbox/);

// ---------------------------------------------------------------------------
// Seeding
// ---------------------------------------------------------------------------

// Given job <jobId> is saved with code <body>. Before anyone opens the
// workflow: the shared draft is built from what is saved.
export const setJobBody = (jobId: string, body: string) =>
  exec(`update jobs set body = $b$${body}$b$ where id = '${jobId}'`);

// Job <jobId>'s code as saved
export const savedBodyOf = (jobId: string) =>
  sql<{ body: string }>(`select body from jobs where id = '${jobId}'`)[0]?.body;

// When "<by>" adds step <name> to workflow <workflowId> through Lightning,
// outside the editor, so it gets a new version — resolves to its id
export function addStepOnNode(workflowId: string, name: string, by: string) {
  const out = onNode(`
    wf = Lightning.Repo.get!(Lightning.Workflows.Workflow, ${JSON.stringify(workflowId)}) |> Lightning.Repo.preload([:jobs, :triggers, :edges])
    actor = Lightning.Repo.get!(Lightning.Accounts.User, ${JSON.stringify(user(by).id)})
    jobs = Enum.map(wf.jobs, &%{id: &1.id}) ++ [%{id: Ecto.UUID.generate(), name: ${JSON.stringify(name)}, body: "fn(s => s)", adaptor: "@openfn/language-common@latest"}]
    {:ok, _} = wf |> Lightning.Workflows.Workflow.changeset(%{jobs: jobs}) |> Lightning.Workflows.save_workflow(actor)
    Lightning.Repo.get_by!(Lightning.Workflows.Job, workflow_id: wf.id, name: ${JSON.stringify(name)}).id`);
  return JSON.parse(lastLine(out)) as string;
}

// A change to the shared document that the server will refuse to save: step
// <jobId> loses its name. Pass to watchEditorSocket's sendDocChange.
export const blankStepName = (jobId: string) => (doc: Y.Doc) => {
  for (const job of doc.getArray<Y.Map<unknown>>('jobs').toArray())
    if (job.get('id') === jobId) job.set('name', '');
};

// Given the adaptor type definitions and docs the browser fetches are held
// back until the returned function is called. Today they come from jsDelivr.
export async function holdAdaptorDownloads(page: Page) {
  let release!: () => void;
  const released = new Promise<void>(resolve => (release = resolve));
  await page.route(/cdn\.jsdelivr\.net/, async route => {
    await released;
    await route.continue();
  });
  return release;
}

// Metadata a DHIS2 instance could describe: an org unit and a resource type
export const STAND_IN_METADATA = {
  name: 'play.dhis2.example.org',
  created: '2026-01-02T03:04:05.000Z',
  children: {
    orgUnits: [{ name: 'DiszpKrYNg8', label: 'Ngelehun CHC', type: 'orgUnit' }],
    resourceTypes: [
      { name: 'trackedEntityInstances', label: 'Tracked entity instances' },
    ],
  },
};

// What a suggestion drawn from STAND_IN_METADATA reads
export const FROM_STAND_IN =
  /Ngelehun CHC|DiszpKrYNg8|Tracked entity instances|trackedEntityInstances/;

// Given the server's metadata service is stood in for: the page's metadata
// requests never reach the server, and are answered with <metadata> once
// answer() is called (and at once after that). Call before the editor
// opens. Not to be combined with watchEditorSocket on the same page.
export async function standInMetadata(page: Page) {
  let metadata: object | null = null;
  const waiting: (() => void)[] = [];
  let asked = 0;

  await page.routeWebSocket(/\/socket\/websocket/, ws => {
    const server = ws.connectToServer();
    ws.onMessage(m => {
      if (typeof m === 'string') {
        const [joinRef, ref, topic, event, payload] = JSON.parse(m) as [
          string,
          string,
          string,
          string,
          { job_id: string },
        ];
        if (event === 'request_metadata') {
          asked++;
          const reply = () =>
            ws.send(
              JSON.stringify([
                joinRef,
                ref,
                topic,
                'phx_reply',
                {
                  status: 'ok',
                  response: { job_id: payload.job_id, metadata },
                },
              ])
            );
          if (metadata) reply();
          else waiting.push(reply);
          return;
        }
      }
      server.send(m);
    });
    server.onMessage(m => ws.send(m));
  });

  return {
    // How many times the page asked for metadata
    asked: () => asked,
    answer(with_: object = STAND_IN_METADATA) {
      metadata = with_;
      for (const reply of waiting.splice(0)) reply();
    },
  };
}
