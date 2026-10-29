// The workflow editor (/projects/<id>/w/<id>), shared by every editor spec.
// Everything here knows how today's React editor is built: React Flow's
// classes, the editor's data-testids, the collaboration channel and its
// frames. Specs and the shared editor-session steps find things through these
// helpers, so a rebuild only changes this file. Helpers for one panel (the
// inspectors, the IDE, the run viewer) go in their own files and import this.
import { expect, type Locator, type Page } from '@playwright/test';
import * as decoding from 'lib0/decoding';
import * as encoding from 'lib0/encoding';
import * as Y from 'yjs';

import { field, open } from '../steps';

// A canvas that waits on the shared document gets this long
const READY = { timeout: 20000 };

export const editorPath = (projectId: string, workflowId: string, query = '') =>
  `/projects/${projectId}/w/${workflowId}${query}`;

export const workflowsListPath = (projectId: string) =>
  `/projects/${projectId}/w`;

// "Loading workflow", shown until the shared document has synced
export const loadingWorkflow = (page: Page) =>
  page.getByText('Loading workflow', { exact: true });

// The canvas. React Flow's root; it is drawn once the document has synced.
export const canvas = (page: Page) => page.locator('.react-flow').first();

// Waits until the editor shows the workflow: the loading message has gone and
// the canvas is drawn
export async function editorReady(page: Page) {
  await expect(canvas(page)).toBeVisible(READY);
  await expect(loadingWorkflow(page)).toHaveCount(0, READY);
}

// When I open the editor for workflow <workflowId> of <projectId> (signed in
// already) — waits for the LiveView and the shared document
export async function openEditor(
  page: Page,
  projectId: string,
  workflowId: string,
  query = ''
) {
  await open(page, editorPath(projectId, workflowId, query));
  await editorReady(page);
}

// ---------------------------------------------------------------------------
// Canvas: steps, triggers and paths
// ---------------------------------------------------------------------------

const NODE = '.react-flow__node';

// A step or trigger on the canvas, by the name drawn under it ("Webhook
// trigger" or "Cron trigger" for triggers)
export const node = (page: Page, name: string) =>
  page
    .locator(NODE)
    .filter({ has: page.getByText(name, { exact: true }) })
    .first();

// Every step and trigger on the canvas
export const nodes = (page: Page) => page.locator(NODE);

// The steps only (no triggers)
export const steps = (page: Page) => page.locator(`${NODE}-job`);

// The id the canvas knows step <name> by (the job's id)
export const nodeIdOf = async (page: Page, name: string) =>
  (await node(page, name).getAttribute('data-id')) ?? '';

// The paths on the canvas
export const paths = (page: Page) => page.locator('.react-flow__edge');

// The path from <from> to <to> (names). React Flow labels each edge with the
// ids of its ends.
export async function pathBetween(page: Page, from: string, to: string) {
  const [source, target] = [
    await nodeIdOf(page, from),
    await nodeIdOf(page, to),
  ];
  return page.locator(
    `.react-flow__edge[aria-label="Edge from ${source} to ${target}"]`
  );
}

// The path's condition as its label icon shows it: "on success" is a tick.
// Labels are drawn in a layer of their own, not inside the edge, so the label
// is the one nearest the middle of the edge.
export async function pathCondition(path: Locator) {
  const text = await path.evaluate(edge => {
    const b = edge.getBoundingClientRect();
    const [cx, cy] = [b.x + b.width / 2, b.y + b.height / 2];
    const labels = Array.from(
      document.querySelectorAll('.react-flow__edgelabel-renderer > div')
    );
    const dist = (l: Element) => {
      const r = l.getBoundingClientRect();
      return Math.hypot(r.x + r.width / 2 - cx, r.y + r.height / 2 - cy);
    };
    const nearest = labels.sort((a, c) => dist(a) - dist(c))[0];
    return (nearest ?? edge).textContent?.trim() ?? '';
  });
  if (text.startsWith('✓')) return 'on success';
  if (text.startsWith('X')) return 'on failure';
  if (text.startsWith('∞')) return 'always';
  return text;
}

// The plus button on step <name>, shown while the step is hovered and the
// workflow can be changed. It is React Flow's source handle.
export const plusButton = (page: Page, name: string) =>
  node(page, name).locator('[data-handleid="node-connector"]');

// When I click the plus button on step <name>
export async function clickPlus(page: Page, name: string) {
  await node(page, name).hover();
  await expect(plusButton(page, name)).toBeVisible();
  await plusButton(page, name).click();
}

const centre = async (target: Locator) => {
  const box = await target.boundingBox();
  if (!box) throw new Error('not on screen');
  return { x: box.x + box.width / 2, y: box.y + box.height / 2 };
};

// When I press on the plus button of <from> and start dragging a path. React
// Flow needs the pointer to move past its drag threshold, in steps.
export async function startPath(page: Page, from: string) {
  await node(page, from).hover();
  await expect(plusButton(page, from)).toBeVisible();
  const { x, y } = await centre(plusButton(page, from));
  await page.mouse.move(x, y);
  await page.mouse.down();
  await page.mouse.move(x + 2, y + 2);
  await page.mouse.move(x + 60, y + 80, { steps: 10 });
}

// While dragging a path, move over step <name>
export async function dragOver(page: Page, name: string) {
  const { x, y } = await centre(node(page, name).locator('[data-a-node]'));
  await page.mouse.move(x, y, { steps: 8 });
}

// Release the path being dragged where the pointer is
export async function releasePath(page: Page) {
  await page.mouse.up();
}

// When I drag a path from <from> and drop it on <to>
export async function dragPath(page: Page, from: string, to: string) {
  await startPath(page, from);
  await dragOver(page, to);
  await releasePath(page);
}

// A spot on the canvas with nothing on it
export async function emptySpot(page: Page) {
  // The first point on a grid where the bare pane is on top: panels, the
  // minimap and controls float over parts of the canvas
  const spot = await canvas(page).evaluate(el => {
    const box = el.getBoundingClientRect();
    for (let fy = 0.1; fy < 1; fy += 0.1)
      for (let fx = 0.1; fx < 1; fx += 0.1) {
        const [x, y] = [box.x + box.width * fx, box.y + box.height * fy];
        if (document.elementFromPoint(x, y)?.matches('.react-flow__pane'))
          return { x, y };
      }
    return null;
  });
  if (!spot) throw new Error('no empty canvas on screen');
  return spot;
}

// When I drag a path from <from> and release it over empty canvas
export async function dragPathToEmpty(page: Page, from: string) {
  await startPath(page, from);
  const { x, y } = await emptySpot(page);
  await page.mouse.move(x, y, { steps: 8 });
  await releasePath(page);
}

// When I click an empty part of the canvas
export async function clickEmptyCanvas(page: Page) {
  const { x, y } = await emptySpot(page);
  await page.mouse.click(x, y);
}

// Then, while a path is being dragged, step <name> is marked as a target
// it can't be dropped on, saying <reason> when there is one
export async function expectInvalidTarget(
  page: Page,
  name: string,
  reason: string
) {
  // Soft, so an outline's other examples are still checked
  const marked = node(page, name).locator('[data-valid-drop-target="false"]');
  await expect.soft(marked, `${name} marked invalid`).toHaveCount(1);
  if (reason)
    await expect
      .soft(node(page, name).getByText(reason, { exact: true }))
      .toBeVisible();
}

// When I drag step <name> by <dx>, <dy> pixels
export async function dragStep(
  page: Page,
  name: string,
  dx: number,
  dy: number
) {
  const { x, y } = await centre(node(page, name).locator('[data-a-node]'));
  await page.mouse.move(x, y);
  await page.mouse.down();
  await page.mouse.move(x + dx, y + dy, { steps: 12 });
  await page.mouse.up();
}

// Where step <name> is drawn on screen (its centre)
export const whereIs = (page: Page, name: string) =>
  centre(node(page, name).locator('[data-a-node]'));

// Whether step <name> is entirely inside the visible canvas
export async function inView(page: Page, name: string) {
  const [n, c] = [
    await node(page, name).boundingBox(),
    await canvas(page).boundingBox(),
  ];
  if (!n || !c) return false;
  return (
    n.x >= c.x &&
    n.y >= c.y &&
    n.x + n.width <= c.x + c.width &&
    n.y + n.height <= c.y + c.height
  );
}

// When I pan the canvas by <dx>, <dy> pixels, dragging the empty pane
export async function panCanvas(page: Page, dx: number, dy: number) {
  const { x, y } = await emptySpot(page);
  await page.mouse.move(x, y);
  await page.mouse.down();
  await page.mouse.move(x + dx, y + dy, { steps: 10 });
  await page.mouse.up();
}

// The minimap
export const minimap = (page: Page) =>
  page
    .getByRole('img', { name: /mini ?map/i })
    .or(page.locator('.react-flow__minimap'))
    .first();

// ---------------------------------------------------------------------------
// Canvas controls. Today they are React Flow control buttons with no
// accessible name; each carries its tooltip in data-tooltip (shown by tippy).
// A rebuild that names them by their tooltip is found by role.
// ---------------------------------------------------------------------------

const controls = (page: Page) => page.locator('.react-flow__controls-button');

const controlNamed = (page: Page, name: string) =>
  page
    .getByRole('button', { name, exact: true })
    .or(page.locator(`.react-flow__controls-button[data-tooltip="${name}"]`))
    .first();

export const fitViewButton = (page: Page) => controlNamed(page, 'Fit view');

export const autoLayoutButton = (page: Page) =>
  controlNamed(page, 'Run auto layout (override manual positions)');

// The layout mode switch, whatever its tooltip says (it names the mode it
// switches to, or why the workflow is read-only): the second control with a
// tooltip, after "Fit view" (the zoom buttons before it have none)
export const layoutModeSwitch = (page: Page) =>
  page
    .getByRole('button', { name: /layout mode/ })
    .or(controls(page).and(page.locator('[data-tooltip]')).nth(1))
    .first();

export const undoButton = (page: Page) =>
  page
    .getByRole('button', { name: /^(Undo|Nothing to undo)$/ })
    .or(page.getByTestId('undo-button'))
    .first();

export const redoButton = (page: Page) =>
  page
    .getByRole('button', { name: /^(Redo|Nothing to redo)$/ })
    .or(page.getByTestId('redo-button'))
    .first();

// The tooltip a control shows when pointed at, or null when none shows
export async function controlTooltip(page: Page, control: Locator) {
  await page.mouse.move(0, 0);
  await control.hover({ force: true });
  const tip = page.getByRole('tooltip').or(page.locator('.tippy-box')).first();
  try {
    await expect(tip).toBeVisible();
  } catch {
    return null;
  }
  return (await tip.innerText()).trim();
}

// ---------------------------------------------------------------------------
// Adding a step: the adaptor picker
// ---------------------------------------------------------------------------

// The adaptor picker dialog. The dialog element itself has no size today,
// so it is the innermost box holding the search box and the list.
export const adaptorPicker = (page: Page) =>
  page
    .getByRole('dialog')
    .locator('div')
    .filter({ has: page.getByRole('combobox') })
    .filter({ has: page.getByRole('listbox', { name: 'Adaptor options' }) })
    .last();

// When I choose adaptor <search> in the picker (the first match)
export async function chooseAdaptor(page: Page, search: string) {
  const picker = adaptorPicker(page);
  await expect(picker).toBeVisible();
  await picker.getByRole('combobox').fill(search);
  await picker
    .getByRole('listbox', { name: 'Adaptor options' })
    .getByRole('option', { name: new RegExp(search, 'i') })
    .first()
    .click();
  await expect(picker).toHaveCount(0);
}

// ---------------------------------------------------------------------------
// Header
// ---------------------------------------------------------------------------

// The editor's own header bar (the React one, below any banner)
export const header = (page: Page) =>
  page
    .locator('div')
    .filter({ has: page.getByRole('navigation', { name: 'Breadcrumb' }) })
    .filter({ has: page.getByTestId('save-workflow-button') })
    .last()
    .or(
      page
        .locator('div.flex-none.border-b')
        .filter({ has: page.getByRole('navigation', { name: 'Breadcrumb' }) })
    )
    .first();

export const breadcrumbs = (page: Page) =>
  page.getByRole('navigation', { name: 'Breadcrumb' });

// The workflow's name in the breadcrumbs; clicking it returns to the bare
// canvas
export const workflowTitle = (page: Page, name: string) =>
  breadcrumbs(page)
    .getByRole('button', { name, exact: true })
    .or(breadcrumbs(page).getByRole('link', { name, exact: true }))
    .or(breadcrumbs(page).getByText(name, { exact: true }))
    .first();

// The project's environment badge, titled with what it means
export const environmentBadge = (page: Page, env: string) =>
  page.getByTitle(`Project environment is ${env}`);

// "Save" (or "Create" for a new workflow)
export const saveButton = (page: Page) =>
  page.getByRole('button', { name: /^(Save|Create)$/ });

// The red dot on Save that says there are unsaved changes. Decorative today,
// so it is found by the attribute the editor marks it with.
export const unsavedMarker = (page: Page) =>
  page
    .locator('[data-is-dirty]')
    .or(page.getByRole('status', { name: /unsaved changes/i }));

// The "Read-only" pill
export const readOnlyPill = (page: Page) =>
  page.getByText('Read-only', { exact: true });

// The on/off switch for the workflow's triggers (without experimental
// features)
export const workflowSwitch = (page: Page) => header(page).getByRole('switch');

// The Live or Draft badge (with experimental features)
export const lifecycleBadge = (page: Page) =>
  page.getByTestId('workflow-lifecycle-badge');

export const headerButton = (page: Page, name: string) =>
  page.getByRole('button', { name, exact: true });

// The workflow settings button. Today it is an unlabelled icon button with no
// tooltip, found by its place: the only icon-only button in the header's
// right-hand group. A rebuild that names it is found by role.
export const settingsButton = (page: Page) =>
  page
    .getByRole('button', { name: /workflow settings/i })
    .or(page.locator('button:has(> .hero-adjustments-vertical)'))
    .first();

// Whether the settings button is drawn in red (the editor's danger colour),
// which is how it says the workflow settings have an error
export async function settingsFlagged(page: Page) {
  return settingsButton(page).evaluate(el => {
    const ctx = document.createElement('canvas').getContext('2d')!;
    ctx.fillStyle = getComputedStyle(el).color;
    ctx.fillRect(0, 0, 1, 1);
    const [r, g, b] = ctx.getImageData(0, 0, 1, 1).data;
    return r > 150 && r > g * 1.5 && r > b * 1.5;
  });
}

// A confirmation dialog the header opens ("Go live", "Switch to draft"),
// confirmed with the button of the same name
// The confirmation titled <title>. The dialog element itself has no size
// today, so it is the innermost box holding the title and its button.
export const confirmDialog = (page: Page, title: string) =>
  page.getByRole('alertdialog', { name: title }).or(
    page
      .getByRole('dialog')
      .locator('div')
      .filter({ has: page.getByRole('heading', { name: title }) })
      .filter({ has: page.getByRole('button', { name: title, exact: true }) })
      .last()
  );

export async function confirm(page: Page, title: string) {
  const d = confirmDialog(page, title);
  await expect(d).toBeVisible();
  await d.getByRole('button', { name: title, exact: true }).click();
  await expect(d).toHaveCount(0);
}

// The tooltip shown when pointing at <target>, for Radix tooltips in the
// header: they open on hover of the element they wrap
export async function headerTooltip(page: Page, target: Locator) {
  await page.mouse.move(0, 0);
  await target.hover({ force: true });
  const tip = page.getByRole('tooltip').first();
  await expect(tip).toBeVisible();
  return (await tip.innerText()).trim();
}

// A toast from the editor (sonner), by its text
export const editorToast = (page: Page, text: string | RegExp) =>
  page
    .locator('[data-sonner-toast]')
    .filter({ hasText: text })
    .or(page.getByRole('status').filter({ hasText: text }))
    .or(page.getByRole('alert').filter({ hasText: text }))
    .first();

// The button inside a toast
export const toastButton = (page: Page, text: string | RegExp, name: string) =>
  page
    .locator('[data-sonner-toast]')
    .filter({ hasText: text })
    .getByRole('button', { name, exact: true });

// ---------------------------------------------------------------------------
// Side panels
// ---------------------------------------------------------------------------

// The open inspector or panel, by its heading (a step's name, "Path",
// "Workflow settings")
export const panelHeading = (page: Page, title: string) =>
  page.getByRole('heading', { name: title, level: 2, exact: true });

// Which panel and selection the URL says is open
export const editorQuery = (page: Page) =>
  Object.fromEntries(new URL(page.url()).searchParams);

// ---------------------------------------------------------------------------
// Presence
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Everyday edits, through the panels that make them
// ---------------------------------------------------------------------------

// When I open workflow settings from the header (it stays open)
export async function openSettings(page: Page) {
  if (await panelHeading(page, 'Workflow settings').isVisible()) return;
  await settingsButton(page).click();
  await expect(panelHeading(page, 'Workflow settings')).toBeVisible();
}

// When I rename the workflow to <name> in workflow settings, without saving.
// The cursor stays in the field.
export async function renameWorkflow(page: Page, name: string) {
  await openSettings(page);
  const box = field(page, 'Workflow Name');
  await box.fill(name);
}

// When I rename step <step> to <to> in its inspector, without saving
export async function renameStep(page: Page, step: string, to: string) {
  await node(page, step).click();
  await expect(panelHeading(page, step)).toBeVisible();
  await field(page, 'Job Name').fill(to);
  await expect(node(page, to)).toBeVisible();
}

// The avatar of a collaborator in the header, by the initials it shows
export const collaboratorAvatar = (page: Page, initials: string) =>
  header(page).getByText(initials, { exact: true });

// The cursor drawn for a collaborator on the canvas, labelled with their name
// (drawn over the canvas, in a layer of its own)
export const remoteCursor = (page: Page, name: string) =>
  page.getByText(name, { exact: true });

// ---------------------------------------------------------------------------
// The collaboration channel. watchEditorSocket(page), called before the
// editor opens, sits between the page and the server on /socket/websocket.
// It forwards everything, keeps a copy of the shared document as the server
// sends it, and can send what the page would send on the workflow's room,
// drop the connection, or keep it down.
// ---------------------------------------------------------------------------

type Frame = [string | null, string | null, string, string, unknown];
type Reply = { status: string; response: Record<string, unknown> };

// Phoenix's binary frames: push (client to server) is kind 0 with join ref,
// ref, topic and event; from the server kind 0 is a push (join ref, topic,
// event), 1 a reply (join ref, ref, topic, status), 2 a broadcast (topic,
// event).
function decodeBinary(buf: Buffer) {
  const kind = buf[0];
  const sizes =
    kind === 0
      ? [buf[1], 0, buf[2], buf[3]]
      : kind === 1
        ? [buf[1], buf[2], buf[3], buf[4]]
        : [0, 0, buf[1], buf[2]];
  let at = kind === 0 ? 4 : kind === 1 ? 5 : 3;
  const take = (n: number) => buf.subarray(at, (at += n)).toString('utf8');
  const [, , topic, event] = sizes.map(take);
  return { topic, event, data: new Uint8Array(buf.subarray(at)) };
}

function encodePush(
  joinRef: string,
  ref: string,
  topic: string,
  event: string,
  data: Uint8Array
) {
  const parts = [joinRef, ref, topic, event].map(s => Buffer.from(s));
  return Buffer.concat([
    Buffer.from([0, ...parts.map(p => p.length)]),
    ...parts,
    Buffer.from(data),
  ]);
}

// Applies a y-protocols sync message (step 2 or update) to <doc>
function applySync(doc: Y.Doc, data: Uint8Array) {
  try {
    const d = decoding.createDecoder(data);
    if (decoding.readVarUint(d) !== 0) return; // not a sync message
    const step = decoding.readVarUint(d);
    if (step === 1 || step === 2)
      Y.applyUpdate(doc, decoding.readVarUint8Array(d));
  } catch {
    // awareness or something else: not part of the document
  }
}

export type EditorSocket = Awaited<ReturnType<typeof watchEditorSocket>>;

export async function watchEditorSocket(page: Page) {
  const room = { topic: '', joinRef: '' };
  const doc = new Y.Doc();
  const replies = new Map<string, Reply>();
  const pushes: { event: string; payload: unknown }[] = [];
  let send: ((m: string | Buffer) => void) | null = null;
  let closePage: (() => void) | null = null;
  let offline = false;
  let refs = 0;
  let closed = 0;
  // Frames from the server held back while hold() is on
  let held: (() => void)[] | null = null;

  const isRoom = (topic: string) => topic.startsWith('workflow:collaborate:');

  await page.routeWebSocket(/\/socket\/websocket/, ws => {
    if (offline) return void ws.close();
    const server = ws.connectToServer();
    send = m => server.send(m);
    closePage = () => void ws.close();
    ws.onClose(() => void closed++);
    ws.onMessage(m => {
      if (typeof m === 'string') {
        const [joinRef, , topic, event] = JSON.parse(m) as Frame;
        if (event === 'phx_join' && isRoom(topic) && joinRef)
          Object.assign(room, { topic, joinRef });
      }
      server.send(m);
    });
    server.onMessage(m => {
      if (typeof m === 'string') {
        const [, ref, topic, event, payload] = JSON.parse(m) as Frame;
        if (isRoom(topic)) {
          if (event === 'phx_reply' && ref) replies.set(ref, payload as Reply);
          else pushes.push({ event, payload });
        }
      } else {
        const { topic, data } = decodeBinary(m);
        if (isRoom(topic)) applySync(doc, data);
      }
      if (held) held.push(() => ws.send(m));
      else ws.send(m);
    });
  });

  const joined = () =>
    expect.poll(() => room.joinRef, 'joined the workflow room').not.toBe('');

  return {
    // The room the page joined ("workflow:collaborate:<id>[:v<n>]")
    room: () => room.topic,
    // What the server pushed on the room, by event name
    pushed: (event: string) =>
      pushes.filter(p => p.event === event).map(p => p.payload),
    // How many times a connection was closed
    closed: () => closed,
    // The shared document as the server has sent it to this page
    doc,

    // When the page sends <event> with <payload> on the workflow's room, as
    // its own code would — resolves to the server's reply
    async push(event: string, payload: Record<string, unknown> = {}) {
      await joined();
      const ref = `scenario-${++refs}`;
      send!(JSON.stringify([room.joinRef, ref, room.topic, event, payload]));
      await expect
        .poll(() => replies.has(ref), `server answered ${event}`)
        .toBe(true);
      return replies.get(ref)!;
    },

    // When the page sends a change to the shared document, made by <change>
    // on the copy the server sent it. Waits a moment for the server to take
    // it in (it does not answer document frames).
    async sendDocChange(change: (doc: Y.Doc) => void) {
      await joined();
      await expect
        .poll(() => doc.getArray('jobs').length, 'document synced')
        .toBeGreaterThan(0);
      const before = Y.encodeStateVector(doc);
      doc.transact(() => change(doc));
      const update = Y.encodeStateAsUpdate(doc, before);
      const e = encoding.createEncoder();
      encoding.writeVarUint(e, 0); // sync
      encoding.writeVarUint(e, 2); // update
      encoding.writeVarUint8Array(e, update);
      send!(
        encodePush(
          room.joinRef,
          `scenario-${++refs}`,
          room.topic,
          'yjs',
          encoding.toUint8Array(e)
        )
      );
      await page.waitForTimeout(1000);
    },

    // Holds back everything the server sends (the page waits on it) until
    // release()
    hold() {
      held = [];
    },
    release() {
      const queued = held ?? [];
      held = null;
      for (const s of queued) s();
    },

    // When my connection drops and stays down until reconnect()
    drop() {
      offline = true;
      closePage?.();
    },
    // When my connection returns
    reconnect() {
      offline = false;
    },
  };
}

// Renames the workflow in a copy of the shared document
export const renameWorkflowIn = (name: string) => (doc: Y.Doc) =>
  doc.getMap('workflow').set('name', name);

// When the page joins the room <topic> with <params> on a socket of its own,
// as the editor would — resolves to the server's reply. The page must be on a
// signed-in Lightning page (the root layout carries the socket token).
export async function joinRoom(
  page: Page,
  topic: string,
  params: Record<string, unknown>
) {
  return page.evaluate(
    ({ topic, params }) =>
      new Promise<Reply>((resolve, reject) => {
        const token = (window as unknown as { userToken?: string }).userToken;
        const url = `${location.origin.replace(/^http/, 'ws')}/socket/websocket?token=${token}&vsn=2.0.0`;
        const ws = new WebSocket(url);
        ws.onopen = () =>
          ws.send(JSON.stringify(['1', '1', topic, 'phx_join', params]));
        ws.onmessage = e => {
          const [, ref, , event, payload] = JSON.parse(
            e.data as string
          ) as unknown[];
          if (ref === '1' && event === 'phx_reply') {
            ws.close();
            resolve(payload as Reply);
          }
        };
        ws.onerror = () => reject(new Error('socket error'));
      }),
    { topic, params }
  );
}

// The room for workflow <id>, or for its version <v>
export const roomFor = (workflowId: string, v?: number) =>
  `workflow:collaborate:${workflowId}${v === undefined ? '' : `:v${v}`}`;

// Tells the editor's page what version pin a URL carries
export const versionQuery = (v: number) => `?v=${v}`;
export const asRunQuery = (runId: string) => `?as_run=${runId}`;
