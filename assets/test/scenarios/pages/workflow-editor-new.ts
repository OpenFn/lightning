// The new workflow page (/projects/<id>/w/new,
// annotations/views/workflow-editor-new.md): the landing screen, the template
// browser and the YAML import dialog. Everything here knows how today's page
// is built: the landing screen drawn over a canvas that is already mounted,
// Headless UI dialogs named by aria-label, Radix tooltips on wrappers round
// disabled buttons, the collaboration channel's events. Specs find things
// through these helpers, so a rebuild only changes this file. Editor-wide
// helpers are in ./workflow-editor.
import { randomUUID } from 'node:crypto';

import { expect, type Locator, type Page } from '@playwright/test';

import {
  clickable,
  exec,
  lastLine,
  modal,
  modalTitle,
  onNode,
  open,
  seedEditorWorkflow,
} from '../steps';

import { joinRoom, loadingWorkflow, roomFor } from './workflow-editor';

// The page waits on the channel join and the session context
const READY = { timeout: 20000 };

const escape = (s: string) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

// ---------------------------------------------------------------------------
// Opening the page
// ---------------------------------------------------------------------------

export const newWorkflowPath = (projectId: string, query = '') =>
  `/projects/${projectId}/w/new${query}`;

// The landing screen's heading. Today a modal over it marks the rest of the
// page inert, so it is found by text as well as by role.
export const landingHeading = (page: Page) =>
  page
    .getByRole('heading', { name: 'Where would you like to start today?' })
    .or(page.getByText('Where would you like to start today?', { exact: true }))
    .first();

// Waits until the landing screen is up and the editor has joined its room.
// The canvas under the landing screen shows "Loading workflow" until then;
// before that every way to start says "Still connecting".
export async function newWorkflowReady(page: Page) {
  await expect(landingHeading(page)).toBeVisible(READY);
  await expect(loadingWorkflow(page)).toHaveCount(0, READY);
}

// When I open the new workflow page of project <projectId> (signed in
// already) — waits until creating would work
export async function openNew(page: Page, projectId: string, query = '') {
  await open(page, newWorkflowPath(projectId, query));
  await newWorkflowReady(page);
}

// A starting-point card ("Build from scratch", "Browse templates"). Today a
// button named by its title and description together.
export const startCard = (page: Page, title: string) =>
  page.getByRole('button', { name: new RegExp(`^${escape(title)}`) });

export const importLink = (page: Page) =>
  clickable(page, 'import a YAML file manually');

// Whether the canvas can be seen. Today it is mounted under the landing
// screen from the start, so this asks what is drawn on top at its centre.
export const canvasShown = (page: Page) =>
  page.evaluate(() => {
    const c = Array.from(document.querySelectorAll('.react-flow')).find(
      el => !el.closest('[role="dialog"]')
    );
    if (!c) return false;
    const r = c.getBoundingClientRect();
    if (r.width === 0 || r.height === 0) return false;
    const hit = document.elementFromPoint(
      r.x + r.width / 2,
      r.y + r.height / 2
    );
    return !!hit && c.contains(hit);
  });

// The id of the workflow just created, once the address has moved to it
export async function createdWorkflowId(page: Page, projectId: string) {
  const at = new RegExp(`^/projects/${projectId}/w/[0-9a-f-]{36}$`);
  await expect.poll(() => new URL(page.url()).pathname, READY).toMatch(at);
  return new URL(page.url()).pathname.split('/').pop()!;
}

// The tooltip on a disabled control. Today a disabled button sends no
// pointer events, so the tooltip hangs off the wrapper round it.
export async function tipOn(page: Page, control: Locator) {
  await page.mouse.move(0, 0);
  await control.locator('xpath=..').hover({ force: true });
  const tip = page.getByRole('tooltip').first();
  await expect(tip).toBeVisible();
  return (await tip.innerText()).trim();
}

// ---------------------------------------------------------------------------
// The YAML import dialog
// ---------------------------------------------------------------------------

export const importDialog = (page: Page) => modal(page, 'Import a workflow');

export const importTitle = (page: Page) =>
  modalTitle(page, 'Import a workflow');

// The dialog's Create button, whatever it says while it works
export const importCreateButton = (page: Page) =>
  importDialog(page).getByRole('button', {
    name: /^(Create|Validating\.\.\.|Importing\.\.\.)$/,
  });

// The text box holding the YAML, in paste mode
export const importText = (page: Page) =>
  importDialog(page).getByRole('textbox');

// When I upload file <name> holding <content>. Today a visually hidden file
// input under the drop area.
export async function uploadFile(
  page: Page,
  name: string,
  content: string | Buffer
) {
  await importDialog(page)
    .locator('input[type="file"]')
    .setInputFiles({
      name,
      mimeType: name.endsWith('.json') ? 'application/json' : 'text/yaml',
      buffer: typeof content === 'string' ? Buffer.from(content) : content,
    });
}

// When I open the import dialog from the keyboard (Ctrl+\ or Cmd+\)
export const importByKeyboard = (page: Page) =>
  page.keyboard.press('ControlOrMeta+\\');

// ---------------------------------------------------------------------------
// The template browser
// ---------------------------------------------------------------------------

// Today the dialog is named "Browse workflow templates" and headed
// "Templates"
export const templatesDialog = (page: Page) =>
  modal(page, 'Browse workflow templates');

export const templatesTitle = (page: Page) =>
  templatesDialog(page).getByRole('heading', { name: 'Templates' });

export const templateSearch = (page: Page) =>
  templatesDialog(page).getByRole('textbox', { name: 'Search templates' });

// A template in the list. Today a toggle button named by its name and
// description.
export const templateCard = (page: Page, name: string) =>
  templatesDialog(page).getByRole('button', {
    name: new RegExp(`^${escape(name)}`),
  });

const templateCards = (page: Page) =>
  templatesDialog(page).locator('button[aria-pressed]');

// The templates listed, top to bottom, by name
export async function templateNames(page: Page) {
  await expect(
    templatesDialog(page).getByText('Loading templates...')
  ).toHaveCount(0, READY);
  return templateCards(page).evaluateAll(cards =>
    cards.map(c => (c.querySelector('p')?.textContent ?? '').trim())
  );
}

// The preview diagram of template <name>, labelled with the name its YAML
// gives
export const previewDiagram = (page: Page, name: string) =>
  templatesDialog(page).getByLabel(`Preview of ${name}`, { exact: true });

// The browser's Create button, whatever it says while it works
export const templateCreateButton = (page: Page) =>
  templatesDialog(page).getByRole('button', {
    name: /^(Create|Creating\.\.\.)$/,
  });

// The footer under the preview: the previewed template's name, description
// and Create. Today the innermost block holding Create.
export const previewFooter = (page: Page) =>
  templatesDialog(page)
    .locator('div')
    // `has` is matched inside each div, so it can't start at the dialog
    .filter({
      has: page.getByRole('button', { name: /^(Create|Creating\.\.\.)$/ }),
    })
    .last();

// Whether every template in the list is off
export const allTemplatesDisabled = (page: Page) =>
  templateCards(page).evaluateAll(cards =>
    cards.every(c => (c as HTMLButtonElement).disabled)
  );

// Given the page's request for published templates will fail: the channel's
// "list_templates" is answered with an error and never reaches the server.
// Call before the page opens. Not to be combined with watchEditorSocket on
// the same page.
export async function failTemplateLoading(page: Page) {
  await page.routeWebSocket(/\/socket\/websocket/, ws => {
    const server = ws.connectToServer();
    ws.onMessage(m => {
      if (typeof m === 'string') {
        const [joinRef, ref, topic, event] = JSON.parse(m) as [
          string | null,
          string | null,
          string,
          string,
        ];
        if (event === 'list_templates') {
          ws.send(
            JSON.stringify([
              joinRef,
              ref,
              topic,
              'phx_reply',
              {
                status: 'error',
                response: { type: 'internal_error', errors: {} },
              },
            ])
          );
          return;
        }
      }
      server.send(m);
    });
    server.onMessage(m => ws.send(m));
  });
}

// ---------------------------------------------------------------------------
// Build with AI
// ---------------------------------------------------------------------------

export const aiPrompt = (page: Page) =>
  page.getByRole('textbox', { name: 'Build with AI' });

export const aiDisclaimer = (page: Page) =>
  page.getByText(/Please use AI responsibly/);

// The AI assistant panel
export const aiPanel = (page: Page) =>
  page.getByRole('complementary', { name: 'AI Assistant' });

// The tooltip on the AI prompt. Today it hangs off the box round the prompt
// and "Build it"; the prompt itself is disabled, so the box's bottom edge is
// pointed at.
export async function aiPromptTip(page: Page) {
  const box = aiPrompt(page).locator('xpath=..');
  const size = await box.boundingBox();
  if (!size) throw new Error('prompt not on screen');
  await page.mouse.move(0, 0);
  await box.hover({ force: true, position: { x: 4, y: size.height - 4 } });
  const tip = page.getByRole('tooltip').first();
  await expect(tip).toBeVisible();
  return (await tip.innerText()).trim();
}

// ---------------------------------------------------------------------------
// The collaboration channel
// ---------------------------------------------------------------------------

// When the page joins the room for a new workflow with id <workflowId> in
// project <projectId>, as the editor on /w/new would — resolves to the
// server's reply. The page must be on a signed-in Lightning page.
export const joinNewRoom = (
  page: Page,
  projectId: string,
  workflowId: string
) =>
  joinRoom(page, roomFor(workflowId), {
    project_id: projectId,
    action: 'new',
  });

// ---------------------------------------------------------------------------
// Seeding
// ---------------------------------------------------------------------------

export type TemplateSeed = {
  name: string;
  description?: string;
  tags?: string[];
  /** the template's workflow YAML; one webhook and one step by default */
  code?: string;
};

// A v1 workflow named <name>: a webhook leading to one step "Fetch"
export const templateYaml = (name: string) => `name: ${JSON.stringify(name)}
jobs:
  Fetch:
    name: Fetch
    adaptor: "@openfn/language-common@latest"
    body: |
      fn(state => state)
triggers:
  webhook:
    type: webhook
    enabled: true
edges:
  webhook->Fetch:
    source_trigger: webhook
    target_job: Fetch
    condition_type: always
    enabled: true`;

// Given template <name> has been published from a workflow of project
// <projectId>, built by "<by>". Templates are listed on every project of the
// instance. Returns a function that removes it (before the project goes).
export function seedTemplate(
  projectId: string,
  by: string,
  { name, description = '', tags = [], code = templateYaml(name) }: TemplateSeed
) {
  const source = seedEditorWorkflow(projectId, by, {
    name: `${name} (template source)`,
  });
  const id = randomUUID();
  exec(`insert into workflow_templates
          (id, name, description, code, tags, workflow_id, inserted_at, updated_at)
        values ('${id}', $n$${name}$n$, $d$${description}$d$, $c$${code}$c$,
                '{${tags.join(',')}}', '${source.id}', now(), now())`);
  return () => exec(`delete from workflow_templates where id = '${id}'`);
}

// Given the AI assistant is configured on this instance. The endpoint is a
// placeholder nothing answers on, so the assistant never replies.
// Instance-wide (@serial). Returns a function that puts the setting back.
export function withAiAssistant() {
  const was = lastLine(onNode('Application.get_env(:lightning, :apollo)'));
  onNode(`Application.put_env(:lightning, :apollo,
            Keyword.merge(Application.get_env(:lightning, :apollo) || [],
              endpoint: "http://127.0.0.1:1", ai_assistant_api_key: "scenario-key"))`);
  return () =>
    onNode(
      was === 'nil'
        ? 'Application.delete_env(:lightning, :apollo)'
        : `Application.put_env(:lightning, :apollo, ${was})`
    );
}
