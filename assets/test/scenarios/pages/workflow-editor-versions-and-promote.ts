// The workflow editor's versions, run history, restore and sandbox controls
// (annotations/views/workflow-editor-versions-and-promote.md): the version
// chip in the breadcrumbs and its two lists, the restore and unsaved-changes
// dialogs, the history panel on the canvas, the "Edit in sandbox" picker, and
// the header's hand-offs to GitHub sync and promote. Everything here knows
// how today's React editor is built: the chip's place in the breadcrumbs, the
// history rows' test ids and classes, the picker's radios, the collaboration
// channel's event names. Specs find things through these helpers, so a
// rebuild only changes this file. Editor-wide helpers are in
// ./workflow-editor; seeders this view needs are at the bottom.
import { expect, type Locator, type Page } from '@playwright/test';

import { exec, lastLine, onNode, sql, user } from '../steps';

import {
  breadcrumbs,
  editorQuery,
  headerButton,
  type EditorSocket,
} from './workflow-editor';

// ---------------------------------------------------------------------------
// The version chip and its lists. The chip is the breadcrumb button that
// reads "latest", "v<n>", "unpublished" or "•" while loading. The open list
// is a menu: the saves list (no experimental features, drafts, sandboxes)
// and the publishes list (live workflows with experimental features).
// ---------------------------------------------------------------------------

export const versionChip = (page: Page) =>
  breadcrumbs(page).getByRole('button', {
    name: /^(latest|v\S+|unpublished|•)$/i,
  });

export const versionMenu = (page: Page) => page.getByRole('menu');

// When I open the version chip (if it isn't open already)
export async function openVersions(page: Page) {
  if (!(await versionMenu(page).isVisible())) await versionChip(page).click();
  await expect(versionMenu(page)).toBeVisible();
}

// When I close the version list
export async function closeVersions(page: Page) {
  await page.keyboard.press('Escape');
  await expect(versionMenu(page)).toHaveCount(0);
}

const startsWith = (label: string) =>
  new RegExp(
    `^\\s*${label.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}(\\s|$)`,
    'i'
  );

// A row of the open list, by the label it starts with ("latest", "v3")
export const versionItem = (page: Page, label: string) =>
  versionMenu(page).getByRole('menuitem', { name: startsWith(label) });

// When I pick <label> from the version chip
export async function pickVersion(page: Page, label: string) {
  await openVersions(page);
  await versionItem(page, label).click();
}

// The labels of the open list, in order: "latest" (or "Latest") and v-numbers
export async function listedVersions(page: Page) {
  await expect(versionMenu(page).getByRole('menuitem').first()).toBeVisible();
  const texts = await versionMenu(page).getByRole('menuitem').allInnerTexts();
  return texts.map(t => t.trim().split(/\s+/)[0]);
}

// Just the version numbers of the open list, newest first
export async function listedNumbers(page: Page) {
  return (await listedVersions(page))
    .filter(l => /^v\d+$/.test(l))
    .map(l => Number(l.slice(1)));
}

// The whole text of row <label>: its number, how it was published, who by
// and when
export const versionRowText = async (page: Page, label: string) =>
  (await versionItem(page, label).innerText()).replace(/\s+/g, ' ').trim();

// The "Restore" link on row <label>. Today it sits beside the row's own
// button and only shows on hover, so the row is pointed at first.
export const restoreLink = (page: Page, label: string) =>
  versionItem(page, label)
    .locator('xpath=..')
    .getByRole('button', { name: 'Restore', exact: true });

export const restoreLinks = (page: Page) =>
  versionMenu(page).getByRole('button', { name: 'Restore', exact: true });

// When I choose "Restore" on row <label>
export async function chooseRestore(page: Page, label: string) {
  await openVersions(page);
  await versionItem(page, label).hover();
  await restoreLink(page, label).click();
}

// Whether <dialog> is on screen. Headless UI's dialog root has no size, so
// this looks for a box inside it that has one.
export const shown = (dialog: Locator) =>
  dialog.locator('div').filter({ visible: true }).first();

// The "Restore v<n>?" dialog
export const restoreDialog = (page: Page, n: number) =>
  page.getByRole('dialog', { name: `Restore v${n}?` });

export const restoreConfirm = (page: Page, n: number) =>
  restoreDialog(page, n).getByRole('button', { name: `Restore v${n}` });

// The "You have unsaved changes" dialog, asked before a switch that would
// throw edits away
export const discardDialog = (page: Page) =>
  page.getByRole('dialog', { name: 'You have unsaved changes' });

export const discardChoice = (
  page: Page,
  name: 'Cancel' | 'Switch' | 'Save and switch'
) => discardDialog(page).getByRole('button', { name, exact: true });

// Which version the URL pins: the save (v), the publish (release) or the run
// shown as executed (as_run)
export const pinOf = (page: Page) => {
  const q = editorQuery(page);
  return { v: q.v, release: q.release, as_run: q.as_run, run: q.run };
};

// The number of entries in the tab's history
export const historyLength = (page: Page) =>
  page.evaluate(() => window.history.length);

// ---------------------------------------------------------------------------
// The history panel on the canvas. Its header reads "View History" when
// collapsed and "Recent History" when expanded.
// ---------------------------------------------------------------------------

const historyHeading = (page: Page) =>
  page.getByRole('heading', { name: /^(View History|Recent History)$/ });

// The panel itself: the floating box that holds the heading
export const historyPanel = (page: Page) =>
  historyHeading(page).locator(
    'xpath=ancestor::div[contains(@class,"absolute")][1]'
  );

export const historyExpanded = (page: Page) =>
  page.getByRole('heading', { name: 'Recent History', exact: true });

// When I expand the history panel by clicking its header
export async function expandHistory(page: Page) {
  if (await historyExpanded(page).isVisible()) return;
  await historyHeading(page).click();
  await expect(historyExpanded(page)).toBeVisible();
}

// When I press Ctrl+H (Cmd+H on a Mac)
export const pressHistoryShortcut = (page: Page) =>
  page.keyboard.press(process.platform === 'darwin' ? 'Meta+h' : 'Control+h');

const short = (id: string) => id.slice(0, 8);

// Work order <id>'s row. Every row's expand button has the same name, so the
// row is found by the id both its markup and the work order share.
export const workOrderRow = (page: Page, id: string) =>
  page.getByTestId(`work-order-${id}`);

// The work order ids the panel lists, top to bottom
export async function listedWorkOrders(page: Page) {
  const rows = page.locator('[data-testid^="work-order-"]');
  return (
    await rows.evaluateAll(els => els.map(el => el.getAttribute('data-testid')))
  ).map(t => (t ?? '').replace('work-order-', ''));
}

// When I expand work order <id>
export const expandWorkOrder = (page: Page, id: string) =>
  workOrderRow(page, id)
    .getByRole('button', { name: 'Expand work order details' })
    .click();

// The work order's id, a link to the history page filtered to it
export const workOrderLink = (page: Page, id: string) =>
  page.getByRole('button', {
    name: `View full details for work order ${short(id)}`,
  });

// The run's id, a link to the run's page
export const runLink = (page: Page, runId: string) =>
  page.getByRole('button', {
    name: `View full details for run ${short(runId)}`,
  });

// Run <runId>'s row: the strip around its id link. The row takes a mouse
// click only (no role), so it is clicked where nothing else is.
export const runRow = (page: Page, runId: string) =>
  runLink(page, runId).locator(
    'xpath=ancestor::div[contains(@class,"border-l-2")][1]'
  );

// When I pick run <runId> in the panel
export async function pickRun(page: Page, runId: string) {
  await expect(runRow(page, runId)).toBeVisible();
  await runRow(page, runId).dispatchEvent('click');
}

// The version tag shown before run <runId>'s id ("v2", "unpublished"), or
// null when there is none
export async function versionTagOf(page: Page, runId: string) {
  const text = (await runRow(page, runId).innerText()).replace(/\s+/g, ' ');
  const at = text.indexOf(short(runId));
  const before = text
    .slice(0, at)
    .trim()
    .replace(/[·•]\s*$/, '')
    .trim();
  const tag = before.split(' ').pop() ?? '';
  return /^(v\d+|unpublished)$/.test(tag) ? tag : null;
}

// The stack icon that opens the full history
export const fullHistoryButton = (page: Page) =>
  page
    .getByRole('button', { name: 'View full history for this workflow' })
    .first();

export const historyRetry = (page: Page) =>
  historyPanel(page).getByRole('button', { name: 'Retry', exact: true });

// The banner that says the selected run took place on another version
export const mismatchBanner = (page: Page) =>
  page.getByRole('alert').filter({
    has: page.getByRole('button', { name: /View as executed/ }),
  });

export const viewAsExecutedButton = (page: Page) =>
  page.getByRole('button', { name: /View as executed/ });

// ---------------------------------------------------------------------------
// "Edit in sandbox"
// ---------------------------------------------------------------------------

export const editInSandboxButton = (page: Page) =>
  headerButton(page, 'Edit in sandbox');

export const sandboxPicker = (page: Page) =>
  page.getByRole('dialog', { name: 'Edit in sandbox' });

// When I open the picker from the header
export async function openSandboxPicker(page: Page) {
  await editInSandboxButton(page).click();
  await expect(shown(sandboxPicker(page))).toBeVisible();
}

export const sandboxNameBox = (page: Page) =>
  sandboxPicker(page).getByRole('textbox', { name: 'Sandbox name' });

// A "Start with" choice: "Nothing", "This run's input", "A saved input"
export const startWith = (page: Page, label: string) =>
  sandboxPicker(page)
    .getByRole('radio', { name: startsWith(label) })
    .first();

// A saved input offered under "A saved input", by its name
export const savedInputChoice = (page: Page, name: string) =>
  sandboxPicker(page).getByRole('radio', { name, exact: true });

// The names of the saved inputs offered. Their radios share one group, apart
// from the "Start with" ones.
export const savedInputNames = (page: Page) =>
  sandboxPicker(page)
    .getByRole('radio')
    .evaluateAll(els =>
      els
        .filter(el => (el as HTMLInputElement).name === 'saved-input')
        .map(el => (el.closest('label')?.textContent ?? '').trim())
    );

// The picker's submit: "Create sandbox", "Continue", "Creating..."
export const createButton = (page: Page) =>
  sandboxPicker(page).getByRole('button', {
    name: /^(Create sandbox|Continue|Creating\.\.\.|Loading\.\.\.)$/,
  });

// Under "Continue in a sandbox": the join button for <name>
export const joinSandbox = (page: Page, name: string) =>
  page.getByRole('button', { name: `Join ${name}`, exact: true });

// The sandboxes offered to continue in, top to bottom
export const listedSandboxes = (page: Page) =>
  sandboxPicker(page)
    .getByRole('button', { name: /^Join / })
    .evaluateAll(els =>
      els.map(el => (el.getAttribute('aria-label') ?? '').replace(/^Join /, ''))
    );

// The "Continue in a sandbox" section heading
export const continueSection = (page: Page) =>
  sandboxPicker(page).getByText('Continue in a sandbox', { exact: true });

export const reviewDialog = (page: Page) =>
  page.getByRole('dialog', {
    name: 'Check the data before it leaves production',
  });

const reviewEditor = (page: Page) =>
  reviewDialog(page).locator('.monaco-editor').first();

// The text the review editor shows (Monaco draws spaces as no-break spaces)
export async function reviewText(page: Page) {
  const lines = reviewEditor(page).locator('.view-line');
  return (await lines.allInnerTexts()).join('\n').replace(/\u00a0/g, ' ');
}

// When the review editor holds <text>, pasted over what it held
export async function setReviewText(page: Page, text: string) {
  await page.context().grantPermissions(['clipboard-read', 'clipboard-write']);
  await reviewEditor(page).click();
  // A key pressed before Monaco takes focus is lost
  await expect(reviewEditor(page)).toHaveClass(/\bfocused\b/);
  await expect(async () => {
    await page.keyboard.press('ControlOrMeta+A');
    await page.keyboard.press('Backspace');
    expect((await reviewText(page)).trim()).toBe('');
  }).toPass();
  await page.evaluate(t => navigator.clipboard.writeText(t), text);
  await page.keyboard.press('ControlOrMeta+V');
}

export const reviewCreate = (page: Page) =>
  reviewDialog(page).getByRole('button', { name: 'Create sandbox' });

// ---------------------------------------------------------------------------
// Hand-offs in the header
// ---------------------------------------------------------------------------

// When I choose "Save & Sync" from the save button's menu
export async function chooseSaveAndSync(page: Page) {
  await page.getByRole('button', { name: 'Open sync options' }).click();
  await page.getByRole('button', { name: 'Save & Sync', exact: true }).click();
}

export const syncDialog = (page: Page) =>
  page.getByRole('dialog', { name: 'Save and sync changes to GitHub' });

export const promoteButton = (page: Page) => headerButton(page, 'Promote');

export const promoteDialog = (page: Page) =>
  page.getByRole('dialog', { name: 'Save and promote to parent project' });

// ---------------------------------------------------------------------------
// Requests the page would send on the workflow's room, past its own guards
// (through watchEditorSocket). Each resolves to the server's reply.
// ---------------------------------------------------------------------------

export const sendRestore = (sock: EditorSocket, n: number) =>
  sock.push('restore_version', { version_number: n });

export const sendListSandboxes = (sock: EditorSocket) =>
  sock.push('list_sandboxes', {});

export const sendCreateSandbox = (sock: EditorSocket, name: string) =>
  sock.push('edit_in_sandbox', { name });

// ---------------------------------------------------------------------------
// Answers the server never gives on its own: a stand-in between the page and
// the server on /socket/websocket that can refuse a request in the server's
// place, or hold its answer back. Don't combine with watchEditorSocket on the
// same page. Events: "versions" (both version lists), "history", "restore",
// "restore check".
// ---------------------------------------------------------------------------

const EVENTS = {
  versions: ['request_versions', 'request_releases'],
  history: ['request_history'],
  restore: ['restore_version'],
  'restore check': ['request_restore_check'],
} as const;

export type RoomRequest = keyof typeof EVENTS;

type Frame = [string | null, string | null, string, string, unknown];

export async function standInRoom(page: Page) {
  const refused = new Map<RoomRequest, Record<string, unknown>>();
  const held = new Set<RoomRequest>();
  const heldRefs = new Set<string>();
  const queued: (() => void)[] = [];
  const asked: Record<string, number> = {};
  const kindOf = (event: string) =>
    (Object.keys(EVENTS) as RoomRequest[]).find(k =>
      (EVENTS[k] as readonly string[]).includes(event)
    );

  await page.routeWebSocket(/\/socket\/websocket/, ws => {
    const server = ws.connectToServer();
    ws.onMessage(m => {
      if (typeof m === 'string') {
        const [joinRef, ref, topic, event] = JSON.parse(m) as Frame;
        const kind = kindOf(event);
        if (kind && topic.startsWith('workflow:collaborate:')) {
          asked[kind] = (asked[kind] ?? 0) + 1;
          const refusal = refused.get(kind);
          if (refusal) {
            ws.send(
              JSON.stringify([
                joinRef,
                ref,
                topic,
                'phx_reply',
                { status: 'error', response: refusal },
              ])
            );
            return;
          }
          if (held.has(kind) && ref) heldRefs.add(ref);
        }
      }
      server.send(m);
    });
    server.onMessage(m => {
      if (typeof m === 'string') {
        const [, ref, , event] = JSON.parse(m) as Frame;
        if (event === 'phx_reply' && ref && heldRefs.has(ref)) {
          queued.push(() => ws.send(m));
          return;
        }
      }
      ws.send(m);
    });
  });

  return {
    // The server's place: <kind> is refused with <response> until allowed
    refuse(kind: RoomRequest, response: Record<string, unknown> = {}) {
      refused.set(kind, { reason: 'failed', ...response });
    },
    allow(kind: RoomRequest) {
      refused.delete(kind);
    },
    // <kind> reaches the server, but its answer waits for release()
    hold(kind: RoomRequest) {
      held.add(kind);
    },
    release() {
      held.clear();
      heldRefs.clear();
      for (const send of queued.splice(0)) send();
    },
    // How many times the page asked for <kind>
    asked: (kind: RoomRequest) => asked[kind] ?? 0,
  };
}

// The read-only rooms a pinned view joins: publish <n>, or run <runId> shown
// as it executed
export const releaseRoom = (workflowId: string, n: number) =>
  `workflow:collaborate:${workflowId}:release${n}`;
export const runRoom = (workflowId: string, runId: string) =>
  `workflow:collaborate:${workflowId}:run:${runId}`;

// The requests "Edit in sandbox" makes for the open run's input, sent as the
// page would send them
export const runInputAsPage = (
  page: Page,
  projectId: string,
  runId: string,
  jobId: string
) =>
  page.request.get(
    `/projects/${projectId}/runs/${runId}/dataclip?job_id=${jobId}`
  );
export const bodyAsPage = (page: Page, dataclipId: string) =>
  page.request.get(`/dataclip/body/${dataclipId}`);

// A refusal as the server words it, for standInRoom's refuse
export const serverRefusal = (message: string, type: string) => ({
  errors: { base: [message] },
  type,
});

// ---------------------------------------------------------------------------
// Seeders. Through Lightning's own functions on the node where the page reads
// derived state (snapshots, publishes, sandboxes), plain rows otherwise.
// ---------------------------------------------------------------------------

const q = (v: unknown) => (v == null ? 'nil' : JSON.stringify(v));
const exUser = (email: string) =>
  `Lightning.Repo.get!(Lightning.Accounts.User, ${q(user(email).id)})`;
const result = <T>(out: string) =>
  JSON.parse(JSON.parse(lastLine(out)) as string) as T;

// When "<by>" renames step <step> of workflow <id> to <to> and saves it
// through Lightning, keeping its other steps — returns the new save number
export function saveRenameOnNode(
  id: string,
  step: string,
  to: string,
  by: string
) {
  const out = onNode(`
    wf = Lightning.Repo.get!(Lightning.Workflows.Workflow, ${q(id)}) |> Lightning.Repo.preload([:jobs, :triggers, :edges])
    jobs = Enum.map(wf.jobs, fn j -> if j.name == ${q(step)}, do: %{id: j.id, name: ${q(to)}}, else: %{id: j.id} end)
    {:ok, wf} = wf |> Lightning.Workflows.Workflow.changeset(%{jobs: jobs}) |> Lightning.Workflows.save_workflow(${exUser(by)})
    Jason.encode!(wf.lock_version)`);
  return result<number>(out);
}

export type PublishKind = 'go_live' | 'promote';

// Given "<by>" published workflow <id>'s current content as its next
// version: kind go_live reads "Published from draft" (or "Initial go-live"
// as v1), promote reads "Promoted sandbox <source>" — returns its number.
// The workflow is set live.
export function publishOnNode(
  id: string,
  by: string,
  { kind = 'go_live', source }: { kind?: PublishKind; source?: string } = {}
) {
  const out = onNode(`
    by = ${exUser(by)}
    wf = Lightning.Repo.get!(Lightning.Workflows.Workflow, ${q(id)})
    wf = wf |> Ecto.Changeset.change(%{state: :live}) |> Lightning.Repo.update!()
    snap = Lightning.Workflows.Snapshot.get_current_for(wf)
    {:ok, r} = Lightning.Workflows.WorkflowReleases.insert_release(Lightning.Repo, %{workflow_id: wf.id, kind: :${kind}, snapshot_id: snap.id, published_by_id: by.id, source_project_id: ${q(source)}})
    Jason.encode!(r.version_number)`);
  return result<number>(out);
}

// When "<by>" restores publish <n> of workflow <id> through Lightning
export function restoreOnNode(id: string, n: number, by: string) {
  onNode(`
    wf = Lightning.Repo.get!(Lightning.Workflows.Workflow, ${q(id)})
    rel = Lightning.Workflows.WorkflowReleases.get_by_version_number(wf.id, ${n})
    {:ok, _} = Lightning.Workflows.restore_version(wf, rel, ${exUser(by)})
    :ok`);
}

// When "<by>" swaps workflow <id>'s triggers for one webhook at /<path>,
// switched on, and saves it through Lightning
export function swapToWebhookOnNode(id: string, path: string, by: string) {
  onNode(`
    wf = Lightning.Repo.get!(Lightning.Workflows.Workflow, ${q(id)}) |> Lightning.Repo.preload([:jobs, :triggers, :edges])
    tid = Ecto.UUID.generate()
    edges = Enum.map(wf.edges, fn e -> if e.source_trigger_id, do: %{id: Ecto.UUID.generate(), source_trigger_id: tid, target_job_id: e.target_job_id, condition_type: :always, enabled: true}, else: %{id: e.id} end)
    {:ok, _} = wf |> Lightning.Workflows.change_workflow(%{triggers: [%{id: tid, type: :webhook, custom_path: ${q(path)}, enabled: true}], edges: edges}) |> Lightning.Workflows.save_workflow(${exUser(by)})
    :ok`);
}

// Given workflow <id> is a draft again, as "Switch to draft" leaves it
export function switchToDraftOnNode(id: string, by: string) {
  onNode(`
    wf = Lightning.Repo.get!(Lightning.Workflows.Workflow, ${q(id)})
    {:ok, _} = Lightning.Workflows.switch_to_draft(wf, ${exUser(by)})
    :ok`);
}

// Publish <n> of workflow <id> is gone
export const deletePublish = (id: string, n: number) =>
  exec(
    `delete from workflow_releases where workflow_id = '${id}' and version_number = ${n}`
  );

// Workflow <id>'s publishes, newest first, with how each reads
export const publishesOf = (id: string) =>
  sql<{ n: number; kind: string; restored_from: number | null }>(
    `select version_number as n, kind::text as kind, restored_from_version_number as restored_from
     from workflow_releases where workflow_id = '${id}' order by version_number desc`
  );

// Workflow <id>'s save numbers, newest first
export const savesOf = (id: string) =>
  sql<{ n: number }>(
    `select lock_version as n from workflow_snapshots where workflow_id = '${id}'
     order by lock_version desc`
  ).map(r => r.n);

export type RunOnSeed = {
  /** the input the run started with (a dataclip id in the project) */
  inputId: string;
  /** the step that took the input; the workflow's first step if not said */
  step?: string;
  /** "success" unless said */
  state?: 'success' | 'failed' | 'crashed';
  /** when it ran, this many minutes ago; work orders list newest first */
  minutesAgo?: number;
};

export type RunOn = { runId: string; workOrderId: string; version: number };

// Given a run of workflow <wf> on the content it holds now (its current
// save), as a webhook would start it: a work order, its run and one finished
// step that took <inputId>. Removing the project's workflow data removes it.
export function seedRunOn(
  wf: { id: string; steps: Record<string, string> },
  { inputId, step, state = 'success', minutesAgo = 1 }: RunOnSeed
): RunOn {
  const job = step ? wf.steps[step] : Object.values(wf.steps)[0];
  const out = onNode(`
    wf = Lightning.Repo.get!(Lightning.Workflows.Workflow, ${q(wf.id)}) |> Lightning.Repo.preload([:triggers])
    snap = Lightning.Workflows.Snapshot.get_current_for(wf)
    t = hd(wf.triggers)
    t0 = DateTime.add(DateTime.utc_now(), -${minutesAgo * 60}, :second)
    t1 = DateTime.add(t0, 2, :second)
    wo = Lightning.Repo.insert!(%Lightning.WorkOrder{workflow_id: wf.id, trigger_id: t.id, dataclip_id: ${q(inputId)}, snapshot_id: snap.id, state: :${state}, last_activity: t1})
    run = Lightning.Repo.insert!(%Lightning.Run{work_order_id: wo.id, starting_trigger_id: t.id, dataclip_id: ${q(inputId)}, snapshot_id: snap.id,
      state: :${state}, claimed_at: t0, started_at: t0, finished_at: t1, options: Lightning.Runs.get_run_options(wf.id, wf.project_id)})
    s = Lightning.Repo.insert!(%Lightning.Invocation.Step{job_id: ${q(job)}, snapshot_id: snap.id, input_dataclip_id: ${q(inputId)},
      exit_reason: ${q(state === 'success' ? 'success' : 'fail')}, started_at: t0, finished_at: t1})
    Lightning.Repo.insert!(%Lightning.RunStep{run_id: run.id, step_id: s.id})
    Jason.encode!(%{runId: run.id, workOrderId: wo.id, version: snap.lock_version})`);
  return result<RunOn>(out);
}

// Given "<by>" made sandbox <name> of project <parentId> through Lightning,
// <hoursAgo> hours ago: it copies the parent's members and workflows as they
// are now. Goes with the parent's workspace. Returns its id.
export function provisionSandboxOnNode(
  parentId: string,
  name: string,
  by: string,
  { hoursAgo = 0 }: { hoursAgo?: number } = {}
) {
  const out = onNode(`
    parent = Lightning.Repo.get!(Lightning.Projects.Project, ${q(parentId)})
    {:ok, sb} = Lightning.Projects.Sandboxes.provision(parent, ${exUser(by)}, %{name: ${q(name)}, color: "#5AA1F0", env: "dev"})
    Jason.encode!(sb.id)`);
  const id = result<string>(out);
  if (hoursAgo)
    exec(
      `update projects set inserted_at = inserted_at - interval '${hoursAgo} hours' where id = '${id}'`
    );
  return id;
}

// The sandboxes of project <parentId>
export const sandboxesOf = (parentId: string) =>
  sql<{ id: string; name: string }>(
    `select id, name from projects where parent_id = '${parentId}' order by name`
  );

// Workflow <name> in project <projectId>: its id, state and whether its
// triggers are on
export const workflowNamed = (projectId: string, name: string) =>
  sql<{ id: string; state: string; triggers_enabled: boolean[] }>(
    `select w.id, w.state::text as state,
            coalesce((select array_agg(t.enabled) from triggers t where t.workflow_id = w.id), '{}') as triggers_enabled
     from workflows w where w.project_id = '${projectId}' and w.name = $n$${name}$n$ and w.deleted_at is null`
  )[0];

// The named dataclips of project <projectId>, with their bodies
export const namedDataclipsOf = (projectId: string) =>
  sql<{ id: string; name: string; body: Record<string, unknown> }>(
    `select id, name, body from dataclips where project_id = '${projectId}' and name is not null`
  );
