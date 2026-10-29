// Scenarios from annotations/views/workflow-editor-new.md, and the shared
// scenarios the new workflow page (/projects/:id/w/new) hosts.
//
// Who's who: "I" is editor@openfn.org; each test gives me the role its Given
// names. owner@openfn.org owns every project ("Malawi HIV", "Kenya TB") and
// saves its workflows and templates' source workflows through Lightning.
// Every project is seeded by the test and removed again afterwards, with its
// workflows and any template seeded from it.
//
// The editor is not being ported: these record what today's page does,
// through pages/workflow-editor-new.ts, so a rebuild that keeps the Value
// passes.
//
// Stand-ins:
// - a save "still running" or a join "still connecting" is the server's
//   frames held back by watchEditorSocket (S05, S06, S12); "disconnected" is
//   the connection dropped and kept down (S06)
// - a save that fails for a server reason is the adaptor catalogue made
//   unavailable (S07, S12, S19), as on workflow-editor-canvas
// - published templates fail to load when the channel's request for them is
//   answered with an error before it reaches the server (S14)
// - published templates are rows written to the database (S09, S11, S13)
// - the AI assistant is "configured" by giving the instance a placeholder
//   endpoint nothing answers on (S20, S21, S23); the hand-off is checked, not
//   a reply
// - the AI quota and the activation limit are usage limiters put on the node
//   that refuse those actions (S23, S27)
//
// shared-workflow-yaml-format runs here, through the landing screen's import
// link. Its S01 is page S18, which calls it.
//
// Of the route's shared scenarios, two run here because /w/new mounts
// differently from /w/:id: shared-project-scope S06 (a support user also
// needs the create-workflow permission here) and shared-flash-messages S02
// (this mount's own "not authorized" flash, run by page S02). The rest of
// shared-authenticated-session, shared-project-scope,
// shared-usage-limits-banner, shared-editor-session and shared-flash-messages
// run once on /projects/:id/w/:id in workflow-editor-canvas.spec.ts; the
// room's "new" join is page S03.
import { expect, test, type Page } from '@playwright/test';
import YAML from 'yaml';

import {
  breadcrumbs,
  editorReady,
  editorToast,
  node,
  openEditor,
  panelHeading,
  saveButton,
  toastButton,
  watchEditorSocket,
  workflowsListPath,
} from './pages/workflow-editor';
import { closeIdeButton } from './pages/workflow-editor-ide';
import { panelQuery, yamlCode } from './pages/workflow-editor-inspectors';
import {
  aiDisclaimer,
  aiPanel,
  aiPrompt,
  aiPromptTip,
  allTemplatesDisabled,
  canvasShown,
  createdWorkflowId,
  failTemplateLoading,
  importByKeyboard,
  importCreateButton,
  importDialog,
  importLink,
  importText,
  importTitle,
  joinNewRoom,
  landingHeading,
  newWorkflowPath,
  newWorkflowReady,
  openNew,
  previewDiagram,
  previewFooter,
  seedTemplate,
  startCard,
  templateCard,
  templateCreateButton,
  templateNames,
  templateSearch,
  templatesDialog,
  templatesTitle,
  tipOn,
  uploadFile,
  withAiAssistant,
} from './pages/workflow-editor-new';
import * as flashMessages from './shared/flash-messages';
import * as projectScope from './shared/project-scope';
import * as yamlFormat from './shared/workflow-yaml-format';
import {
  catalogueUnavailable,
  expectAt,
  makeSupportUser,
  open,
  removeWorkflowData,
  seedEditorWorkflow,
  seedRun,
  seedWorkspace,
  signInAs,
  sql,
  storedWorkflow,
  withLimiterRefusing,
  withRefusingLimiter,
  workflowsOf,
  type WorkspaceSeed,
} from './steps';

const ME = 'editor@openfn.org';
const OWNER = 'owner@openfn.org';

type Role = 'owner' | 'admin' | 'editor' | 'viewer';

const PENDING = { tag: '@pending' };
const PASSING_OLD = { tag: '@passing-old' };
const PASSING_OLD_SERIAL = { tag: ['@passing-old', '@serial'] };

// A page that has to react to something done elsewhere gets this long
const EVENTUALLY = { timeout: 15000 };
// A save with the adaptor catalogue unavailable fails only once the server
// has waited for the catalogue
const SAVE_FAILS = { timeout: 120000 };

const COMMON = '@openfn/language-common@latest';
const NOT_AUTHORIZED = 'You are not authorized to perform this action.';

let cleanups: (() => void)[] = [];
test.beforeEach(() => {
  cleanups = [];
});
test.afterEach(() => {
  for (const cleanup of cleanups.reverse()) cleanup();
});

// Given project <name> exists with these members (owner@openfn.org owns it)
// — removed after the test with its workflows
function givenProject(
  members: Record<string, Role> = { [ME]: 'editor' },
  { name = 'Malawi HIV', ...rest }: Partial<WorkspaceSeed> = {}
) {
  const owned = { ...members, [OWNER]: 'owner' as const };
  const w = seedWorkspace({ name, members: owned, ...rest }, OWNER);
  cleanups.push(w.remove);
  const id = w.id(name);
  cleanups.push(() => removeWorkflowData(id));
  return id;
}

// Given template <name> is published on this instance — removed after the
// test, before its project
function givenTemplate(
  projectId: string,
  seed: Parameters<typeof seedTemplate>[2]
) {
  cleanups.push(seedTemplate(projectId, OWNER, seed));
}

// Given the adaptor catalogue is unavailable, so saves fail. Resolves to
// what makes it available again (also done after the test).
function givenSavesFail() {
  let putBack: (() => void) | null = catalogueUnavailable();
  const recover = () => {
    putBack?.();
    putBack = null;
  };
  cleanups.push(recover);
  return recover;
}

// When I sign in as <email> and open the new workflow page of <projectId>
async function openAs(page: Page, projectId: string, email = ME, query = '') {
  await signInAs(page, email);
  await openNew(page, projectId, query);
}

// The host's opener for the import dialog: a fresh landing screen (a created
// workflow leaves it), then "import a YAML file manually"
const importOpener =
  (page: Page, projectId: string): yamlFormat.OpenImport =>
  async () => {
    await openNew(page, projectId);
    await importLink(page).click();
  };

// When I open the import dialog and paste <yaml>
async function pasteYaml(page: Page, yaml: string) {
  await importLink(page).click();
  await expect(importTitle(page)).toBeVisible();
  await importDialog(page).getByRole('button', { name: 'Paste text' }).click();
  await importText(page).fill(yaml);
}

// When I open the template browser and wait for the published templates
async function browseTemplates(page: Page) {
  await startCard(page, 'Browse templates').click();
  await expect(templatesTitle(page)).toBeVisible();
  await templateNames(page);
}

// Then the editor shows the new workflow, with step <step>
async function editorShows(page: Page, step: string) {
  await expect(landingHeading(page)).toHaveCount(0);
  await editorReady(page);
  await expect(node(page, step)).toBeVisible();
  await expect(saveButton(page)).toBeVisible();
}

// What a stored workflow does: its steps, triggers and edges, by name
const shape = yamlFormat.shapeOf;

// A small workflow to import: a webhook, then "Fetch submissions", then
// "Load to Postgres" on success
const KOBO_SYNC = YAML.stringify({
  name: 'Kobo sync',
  jobs: {
    fetch: {
      name: 'Fetch submissions',
      adaptor: '@openfn/language-http@latest',
      body: 'fn(state => state)\n',
    },
    load: { name: 'Load to Postgres', adaptor: COMMON, body: 'fn(s => s)\n' },
  },
  triggers: { webhook: { type: 'webhook', enabled: true } },
  edges: {
    'webhook->fetch': {
      source_trigger: 'webhook',
      target_job: 'fetch',
      condition_type: 'always',
      enabled: true,
    },
    'fetch->load': {
      source_job: 'fetch',
      target_job: 'load',
      condition_type: 'on_job_success',
      enabled: true,
    },
  },
});

// ---------------------------------------------------------------------------
// Get to the starting screen
// ---------------------------------------------------------------------------

// @S01
// Scenario: Editor sees the ways to start a workflow
//   Given I am an editor on project "Malawi HIV"
//   When I open "/projects/<Malawi HIV id>/w/new"
//   Then I see "Where would you like to start today?"
//   And I see a "Build from scratch" card and a "Browse templates" card
//   And I see a link "import a YAML file manually"
//   And the workflow header and canvas are not shown
test('@S01', PASSING_OLD, async ({ page }) => {
  const id = givenProject();

  await openAs(page, id);

  await expect(landingHeading(page)).toBeVisible();
  await expect(startCard(page, 'Build from scratch')).toBeVisible();
  await expect(startCard(page, 'Browse templates')).toBeVisible();
  await expect(importLink(page)).toBeVisible();
  await expect(saveButton(page)).toHaveCount(0);
  await expect(breadcrumbs(page)).toHaveCount(0);
  expect(await canvasShown(page)).toBe(false);
});

// @S02
// Scenario: A viewer who opens the new workflow URL is sent back to the list
//   Given I am a viewer on project "Malawi HIV"
//   When I open "/projects/<Malawi HIV id>/w/new"
//   Then I am on "/projects/<Malawi HIV id>/w"
//   And I see "You are not authorized to perform this action."
// The flash is this mount's own, so shared-flash-messages S02 runs here.
test('@S02', PASSING_OLD, async ({ page }) => {
  const id = givenProject({ [ME]: 'viewer' });
  await signInAs(page, ME);

  await flashMessages.S02(page, NOT_AUTHORIZED, async () => {
    await page.goto(newWorkflowPath(id));
  });

  await expectAt(page, workflowsListPath(id));
});

// @S03
// Scenario: A new workflow cannot claim an id owned by another project
//   Given I am an editor on project "Malawi HIV"
//   And workflow "Lab results" with id "<lab id>" belongs to project "Kenya TB"
//   When my editor joins the new workflow room for id "<lab id>" in project "Malawi HIV"
//   Then the join is refused with "workflow not found"
test('@S03', PASSING_OLD, async ({ page }) => {
  const malawi = givenProject();
  const kenya = givenProject({}, { name: 'Kenya TB' });
  const lab = seedEditorWorkflow(kenya, OWNER, { name: 'Lab results' });
  const before = storedWorkflow(lab.id);
  await signInAs(page, ME);
  await open(page, '/projects');

  const reply = await joinNewRoom(page, malawi, lab.id);

  expect(reply.status).toBe('error');
  expect(JSON.stringify(reply.response)).toMatch(/workflow not found/);
  expect(storedWorkflow(lab.id)).toEqual(before);
  expect(
    sql(`select id from workflows where id = '${lab.id}'
           and project_id = '${kenya}'`)
  ).toHaveLength(1);
});

// @S24
// Scenario: Links into the editor still open on the landing screen
//   Given I am an editor on project "Malawi HIV" with an existing workflow "Lab results"
//   When I open "/projects/<Malawi HIV id>/w/new?id=<lab id>&chat=true&panel=settings&run=<run id>"
//   Then I see the landing screen for a brand new workflow
//   And "Lab results" is not shown, and no settings, code, run or AI panel is open
// A brand new workflow: building from it creates a workflow of its own and
// leaves "Lab results" as it was.
// Still pending, old: the settings panel named in the link is in the page under the landing screen (unconfirmed whether it can be seen)
test('@S24', PENDING, async ({ page }) => {
  const id = givenProject();
  const run = seedRun(
    id,
    { workflow: 'Lab results', steps: [{ name: 'Fetch' }] },
    OWNER
  );
  cleanups.unshift(run.removeCredentials);
  const before = storedWorkflow(run.workflowId);
  const query = `?${new URLSearchParams({
    id: run.workflowId,
    chat: 'true',
    panel: 'settings',
    run: run.runId,
  }).toString()}`;

  await openAs(page, id, ME, query);

  await expect(landingHeading(page)).toBeVisible();
  await expect(page.getByText('Lab results')).toHaveCount(0);
  await expect(panelHeading(page, 'Workflow settings')).toHaveCount(0);
  await expect(closeIdeButton(page)).toHaveCount(0);
  await expect(aiPanel(page)).toHaveCount(0);

  await startCard(page, 'Build from scratch').click();
  const created = await createdWorkflowId(page, id);
  expect(created).not.toBe(run.workflowId);
  expect(storedWorkflow(run.workflowId)).toEqual(before);
});

// ---------------------------------------------------------------------------
// Build from scratch
// ---------------------------------------------------------------------------

// @S04
// Scenario: Editor builds a blank workflow from scratch
//   Given I am an editor on project "Malawi HIV" with no workflow named "Untitled workflow"
//   And I am on the new workflow landing screen
//   When I click "Build from scratch"
//   Then a workflow named "Untitled workflow" is saved with a webhook trigger, a step "Untitled step" on "@openfn/language-common@latest" and an always edge between them
//   And the address becomes "/projects/<Malawi HIV id>/w/<new id>"
//   And the landing screen is gone and the workflow editor (workflow-editor-canvas) shows the new workflow
test('@S04', PASSING_OLD, async ({ page }) => {
  const id = givenProject();
  await openAs(page, id);

  await startCard(page, 'Build from scratch').click();

  const created = await createdWorkflowId(page, id);
  expect(storedWorkflow(created).name).toBe('Untitled workflow');
  const saved = shape(created);
  expect(saved.jobs).toEqual([
    expect.objectContaining({ name: 'Untitled step', adaptor: COMMON }),
  ]);
  expect(saved.triggers.map(t => t.type)).toEqual(['webhook']);
  expect(saved.edges).toEqual([
    expect.objectContaining({
      from: 'webhook',
      to: 'Untitled step',
      condition: 'always',
    }),
  ]);
  await editorShows(page, 'Untitled step');
});

// @S05
// Scenario: Clicking build from scratch twice creates one workflow
//   Given I am on the new workflow landing screen
//   When I click "Build from scratch" twice while the first save is still running
//   Then the "Build from scratch" card is disabled until the save finishes
//   And exactly one workflow is created
// The second click is forced: a user's click lands on a disabled card too.
test('@S05', PASSING_OLD, async ({ page }) => {
  const id = givenProject();
  const sock = await watchEditorSocket(page);
  await openAs(page, id);
  const card = startCard(page, 'Build from scratch');

  sock.hold();
  await card.click();
  await expect(card).toBeDisabled();
  await card.click({ force: true });
  sock.release();

  await createdWorkflowId(page, id);
  await page.waitForTimeout(2000);
  expect(workflowsOf(id)).toHaveLength(1);
});

// @S06
// Scenario Outline: Creating while not connected tells me why nothing happened
//   Given I am on the new workflow landing screen
//   And the editor is <state> to the server
//   When I click "Build from scratch"
//   Then I see an alert "<title>"
//   And no workflow is created and the landing screen stays
//   Examples:
//     | state                | title            |
//     | disconnected from    | Not connected    |
//     | still connecting     | Still connecting |
// Still connecting first: the server's answer to the join is held back.
// Then it is let through, and the connection dropped.
// Still pending, old: says "Not connected" while the first join is still waiting, not "Still connecting"
test('@S06', PENDING, async ({ page }) => {
  const id = givenProject();
  const sock = await watchEditorSocket(page);
  await signInAs(page, ME);
  const card = startCard(page, 'Build from scratch');
  const nothingCreated = async () => {
    await page.waitForTimeout(1000);
    expect(workflowsOf(id)).toHaveLength(0);
    await expect(landingHeading(page)).toBeVisible();
  };

  sock.hold();
  await open(page, newWorkflowPath(id));
  await expect(landingHeading(page)).toBeVisible();
  await card.click();
  await expect(editorToast(page, 'Still connecting')).toBeVisible();
  await nothingCreated();

  sock.release();
  await newWorkflowReady(page);
  sock.drop();
  await card.click();
  await expect(editorToast(page, 'Not connected')).toBeVisible();
  await nothingCreated();
});

// @S07
// Scenario: A new workflow that fails to save can be retried
//   Given I am on the new workflow landing screen
//   And the next save of the workflow will fail with a server error
//   When I click "Build from scratch"
//   Then I see a "Failed to save workflow" notification with a "Retry" action that does not disappear on its own
//   And the landing screen stays
//   When the server recovers and I click "Retry"
//   Then the workflow is saved and the editor shows it at "/projects/<Malawi HIV id>/w/<new id>"
// The adaptor catalogue is instance-wide
test('@S07', PASSING_OLD_SERIAL, async ({ page }) => {
  test.setTimeout(240000);
  const id = givenProject();
  await openAs(page, id);
  const recover = givenSavesFail();
  const failed = editorToast(page, 'Failed to save workflow');

  await startCard(page, 'Build from scratch').click();

  await expect(failed).toBeVisible(SAVE_FAILS);
  // Longer than a toast that hides itself stays
  await page.waitForTimeout(8000);
  await expect(failed).toBeVisible();
  await expect(landingHeading(page)).toBeVisible();
  expect(workflowsOf(id)).toHaveLength(0);

  recover();
  await toastButton(page, 'Failed to save workflow', 'Retry').click();

  const created = await createdWorkflowId(page, id);
  expect(storedWorkflow(created).steps).toEqual(['Untitled step']);
  await editorShows(page, 'Untitled step');
});

// @S08
// Scenario: A created workflow gets a name unique in the project
//   Given project "Malawi HIV" already has workflows "Event-based workflow" and "Untitled workflow"
//   When I create a workflow from the "Event-based workflow" template
//   Then the new workflow is named "Event-based workflow 1"
//   When I go back to the landing screen and click "Build from scratch"
//   Then the new workflow is named "Untitled workflow 1"
test('@S08', PASSING_OLD, async ({ page }) => {
  const id = givenProject();
  seedEditorWorkflow(id, OWNER, { name: 'Event-based workflow' });
  seedEditorWorkflow(id, OWNER, { name: 'Untitled workflow' });
  await openAs(page, id);

  await browseTemplates(page);
  await templateCard(page, 'Event-based workflow').click();
  await templateCreateButton(page).click();
  const fromTemplate = await createdWorkflowId(page, id);
  expect(storedWorkflow(fromTemplate).name).toBe('Event-based workflow 1');

  await openNew(page, id);
  await startCard(page, 'Build from scratch').click();
  const blank = await createdWorkflowId(page, id);
  expect(storedWorkflow(blank).name).toBe('Untitled workflow 1');
});

// @S27 @variant:activation-limited
// Scenario: At the activation limit a new workflow is created with its triggers off
//   Given project "Malawi HIV" is at its workflow activation limit
//   When I click "Build from scratch"
//   Then the workflow is created
//   And its webhook trigger is saved disabled
// The usage limiter is instance-wide
test('@S27', PASSING_OLD_SERIAL, async ({ page }) => {
  const id = givenProject();
  cleanups.push(withRefusingLimiter());
  await openAs(page, id);

  await startCard(page, 'Build from scratch').click();

  const created = await createdWorkflowId(page, id);
  expect(storedWorkflow(created).triggers_enabled).toEqual([false]);
});

// ---------------------------------------------------------------------------
// Templates
// ---------------------------------------------------------------------------

// @S09
// Scenario: Editor browses templates
//   Given templates "Kobo to DHIS2" and "Appointment reminders" have been published on this instance
//   And I am on the new workflow landing screen
//   When I click "Browse templates"
//   Then I see a "Templates" dialog listing "Event-based workflow" and "Scheduled workflow" first
//   And then "Appointment reminders" and "Kobo to DHIS2"
//   And "Event-based workflow" is previewed as a diagram with its name and description
// Templates are listed from the whole instance
test('@S09', PASSING_OLD_SERIAL, async ({ page }) => {
  const id = givenProject();
  givenTemplate(id, { name: 'Kobo to DHIS2' });
  givenTemplate(id, { name: 'Appointment reminders' });
  await openAs(page, id);

  await startCard(page, 'Browse templates').click();

  await expect(templatesTitle(page)).toBeVisible();
  await expect(templateCard(page, 'Kobo to DHIS2')).toBeVisible(EVENTUALLY);
  const names = await templateNames(page);
  expect(names.slice(0, 2)).toEqual([
    'Event-based workflow',
    'Scheduled workflow',
  ]);
  const [reminders, kobo] = [
    names.indexOf('Appointment reminders'),
    names.indexOf('Kobo to DHIS2'),
  ];
  expect(reminders).toBeGreaterThan(1);
  expect(kobo).toBeGreaterThan(reminders);
  await expect(previewDiagram(page, 'Event-based workflow')).toBeVisible();
  await expect(previewFooter(page)).toContainText('Event-based workflow');
  await expect(previewFooter(page)).toContainText(
    'when a webhook notification is received'
  );
});

// @S10
// Scenario: Clicking a template previews it without creating anything
//   Given the template browser is open
//   When I click "Scheduled workflow"
//   Then the preview shows "Scheduled workflow" and its description
//   And no workflow has been created
test('@S10', PASSING_OLD, async ({ page }) => {
  const id = givenProject();
  await openAs(page, id);
  await browseTemplates(page);

  await templateCard(page, 'Scheduled workflow').click();

  await expect(previewDiagram(page, 'Scheduled workflow')).toBeVisible();
  await expect(previewFooter(page)).toContainText('Scheduled workflow');
  await expect(previewFooter(page)).toContainText('using a "cron" schedule');
  await page.waitForTimeout(1000);
  expect(workflowsOf(id)).toHaveLength(0);
});

// @S11
// Scenario: Searching narrows the published templates but keeps the shipped ones
//   Given templates "Kobo to DHIS2" tagged "survey" and "Appointment reminders" have been published
//   And the template browser is open with "Appointment reminders" previewed
//   When I search for "SURVEY"
//   Then the list shows "Event-based workflow", "Scheduled workflow" and "Kobo to DHIS2"
//   And "Appointment reminders" is not listed and the preview moves to "Event-based workflow"
//   When I search for "zzz"
//   Then I see "No saved templates match your search."
// Templates are listed from the whole instance
test('@S11', PASSING_OLD_SERIAL, async ({ page }) => {
  const id = givenProject();
  givenTemplate(id, { name: 'Kobo to DHIS2', tags: ['survey'] });
  givenTemplate(id, { name: 'Appointment reminders' });
  await openAs(page, id);
  await browseTemplates(page);
  await templateCard(page, 'Appointment reminders').click();
  await expect(previewDiagram(page, 'Appointment reminders')).toBeVisible();

  await templateSearch(page).fill('SURVEY');

  await expect
    .poll(() => templateNames(page))
    .toEqual(['Event-based workflow', 'Scheduled workflow', 'Kobo to DHIS2']);
  await expect(templateCard(page, 'Appointment reminders')).toHaveCount(0);
  await expect(previewDiagram(page, 'Event-based workflow')).toBeVisible();

  await templateSearch(page).fill('zzz');

  await expect(
    page.getByText('No saved templates match your search.')
  ).toBeVisible();
});

// @S12
// Scenario: Editor creates a workflow from a template
//   Given the template browser is open with "Scheduled workflow" previewed
//   When I click "Create"
//   Then the button reads "Creating..." and every template card is disabled while it saves
//   And a workflow "Scheduled workflow" is saved with a cron trigger "0 0 * * *" and a step "Get data"
//   And the dialog and the landing screen close and the editor shows the new workflow
//   But if the save fails the dialog stays open and "Create" is enabled again
// The save is held back to see it running; the failing save makes the
// adaptor catalogue (instance-wide) unavailable.
test('@S12', PASSING_OLD_SERIAL, async ({ page }) => {
  test.setTimeout(240000);
  const id = givenProject();
  const sock = await watchEditorSocket(page);
  await openAs(page, id);
  await browseTemplates(page);
  await templateCard(page, 'Scheduled workflow').click();

  sock.hold();
  await templateCreateButton(page).click();

  await expect(templateCreateButton(page)).toHaveText('Creating...');
  expect(await allTemplatesDisabled(page)).toBe(true);
  sock.release();
  const created = await createdWorkflowId(page, id);
  expect(storedWorkflow(created).name).toBe('Scheduled workflow');
  const saved = shape(created);
  expect(saved.triggers).toEqual([
    expect.objectContaining({ type: 'cron', cron_expression: '0 0 * * *' }),
  ]);
  expect(saved.jobs.map(j => j.name)).toEqual(['Get data']);
  await expect(templatesTitle(page)).toHaveCount(0);
  await editorShows(page, 'Get data');

  await openNew(page, id);
  givenSavesFail();
  await browseTemplates(page);
  await templateCard(page, 'Scheduled workflow').click();
  await templateCreateButton(page).click();

  await expect(editorToast(page, 'Failed to save workflow')).toBeVisible(
    SAVE_FAILS
  );
  await expect(templatesTitle(page)).toBeVisible();
  await expect(templateCreateButton(page)).toHaveText('Create');
  await expect(templateCreateButton(page)).toBeEnabled();
});

// @S13
// Scenario: An unreadable template cannot be used
//   Given a published template "Broken" whose definition is not valid workflow YAML
//   And the template browser is open
//   When I click "Broken"
//   Then the preview says "This template can't be previewed." with the parse error
//   And "Create" is disabled with the tooltip "This template can't be read."
// Templates are listed from the whole instance
test('@S13', PASSING_OLD_SERIAL, async ({ page }) => {
  const id = givenProject();
  givenTemplate(id, { name: 'Broken', code: 'name: Broken\njobs: [' });
  await openAs(page, id);
  await browseTemplates(page);

  await templateCard(page, 'Broken').click();

  const dialog = templatesDialog(page);
  await expect(
    dialog.getByText("This template can't be previewed.")
  ).toBeVisible();
  await expect(previewFooter(page)).toContainText('Broken');
  // The parse error quotes the broken line
  await expect(dialog).toContainText('jobs: [');
  await expect(templateCreateButton(page)).toBeDisabled();
  expect(await tipOn(page, templateCreateButton(page))).toBe(
    "This template can't be read."
  );
});

// @S14
// Scenario: The shipped templates are still offered when published templates fail to load
//   Given loading published templates will fail
//   When I open the template browser
//   Then I see an alert "Failed to load templates" with "Please check your connection and try again."
//   And "Event-based workflow" and "Scheduled workflow" are listed and can be created
test('@S14', PASSING_OLD, async ({ page }) => {
  const id = givenProject();
  await failTemplateLoading(page);
  await openAs(page, id);

  await startCard(page, 'Browse templates').click();

  const alert = editorToast(page, 'Failed to load templates');
  await expect(alert).toBeVisible();
  await expect(alert).toContainText(
    'Please check your connection and try again.'
  );
  expect(await templateNames(page)).toEqual([
    'Event-based workflow',
    'Scheduled workflow',
  ]);
  await templateCard(page, 'Event-based workflow').click();
  await templateCreateButton(page).click();
  const created = await createdWorkflowId(page, id);
  expect(storedWorkflow(created).steps).toEqual(['Transform data']);
});

// ---------------------------------------------------------------------------
// Import YAML
// ---------------------------------------------------------------------------

// @S15
// Scenario: Editor imports a workflow from a YAML file
//   Given I am on the new workflow landing screen
//   When I click "import a YAML file manually"
//   Then I see "Import a workflow" with "Upload or drop a YAML file." and "YML or YAML, up to 8MB"
//   When I upload "kobo-sync.yaml" containing a valid workflow named "Kobo sync"
//   Then the file's text is shown in the text editor
//   And "Create" becomes enabled
//   When I click "Create"
//   Then a workflow "Kobo sync" is saved with the file's steps, triggers and edges
//   And the dialog and the landing screen close and the editor shows the new workflow
test('@S15', PASSING_OLD, async ({ page }) => {
  const id = givenProject();
  await openAs(page, id);

  await importLink(page).click();

  await expect(importTitle(page)).toBeVisible();
  const dialog = importDialog(page);
  await expect(dialog.getByText('Upload or drop a YAML file.')).toBeVisible();
  await expect(dialog.getByText('YML or YAML, up to 8MB')).toBeVisible();

  await uploadFile(page, 'kobo-sync.yaml', KOBO_SYNC);

  await expect(importText(page)).toHaveValue(KOBO_SYNC);
  await expect(importCreateButton(page)).toBeEnabled();

  await importCreateButton(page).click();

  const created = await createdWorkflowId(page, id);
  expect(storedWorkflow(created).name).toBe('Kobo sync');
  const saved = shape(created);
  expect(saved.jobs.map(j => [j.name, j.adaptor])).toEqual([
    ['Fetch submissions', '@openfn/language-http@latest'],
    ['Load to Postgres', COMMON],
  ]);
  expect(saved.triggers.map(t => t.type)).toEqual(['webhook']);
  expect(saved.edges.map(e => [e.from, e.to, e.condition])).toEqual([
    ['Fetch submissions', 'Load to Postgres', 'on_job_success'],
    ['webhook', 'Fetch submissions', 'always'],
  ]);
  await expect(importTitle(page)).toHaveCount(0);
  await editorShows(page, 'Fetch submissions');
});

// @S16
// Scenario Outline: Only YAML files up to 8MB are accepted
//   Given the YAML import dialog is open in upload mode
//   When I upload <file>
//   Then I see "<message>"
//   And nothing is loaded into the editor
//   Examples:
//     | file                     | message                                    |
//     | "workflow.json"          | File must be .yml or .yaml format          |
//     | a 9MB file "big.yaml"    | File size 9.0MB exceeds maximum of 8MB     |
// One step per example; soft, so both are checked.
test('@S16', PASSING_OLD, async ({ page }) => {
  const id = givenProject();
  await openAs(page, id);
  await importLink(page).click();
  await expect(importTitle(page)).toBeVisible();
  const examples = [
    {
      file: 'workflow.json',
      content: '{"name": "Kobo sync"}',
      message: 'File must be .yml or .yaml format',
    },
    {
      file: 'big.yaml',
      content: Buffer.alloc(9 * 1024 * 1024, '#'),
      message: 'File size 9.0MB exceeds maximum of 8MB',
    },
  ];

  for (const { file, content, message } of examples) {
    await test.step(file, async () => {
      await uploadFile(page, file, content);
      await expect
        .soft(importDialog(page).getByText(message, { exact: true }))
        .toBeVisible();
      await expect.soft(importText(page)).toHaveCount(0);
    });
  }
});

// @S17
// Scenario: Invalid YAML is explained before anything is created
//   Given the YAML import dialog is open
//   When I click "Paste text"
//   Then "Create" is disabled with the tooltip "Enter YAML content to create workflow"
//   When I paste YAML whose edge refers to a step "load-data" that does not exist
//   Then I see "Validation Error" with the code "JOB_NOT_FOUND" and "Job reference error: The job 'load-data' referenced in edge"
//   And "Create" is disabled with the tooltip "Fix validation errors to continue"
test('@S17', PASSING_OLD, async ({ page }) => {
  const id = givenProject();
  await openAs(page, id);
  await importLink(page).click();
  await expect(importTitle(page)).toBeVisible();

  await importDialog(page).getByRole('button', { name: 'Paste text' }).click();

  await expect(importCreateButton(page)).toBeDisabled();
  expect(await tipOn(page, importCreateButton(page))).toBe(
    'Enter YAML content to create workflow'
  );

  const broken = YAML.parse(KOBO_SYNC) as {
    edges: Record<string, { target_job: string }>;
  };
  broken.edges['fetch->load'].target_job = 'load-data';
  await importText(page).fill(YAML.stringify(broken));

  const dialog = importDialog(page);
  await expect(
    dialog.getByText('Validation Error', { exact: true })
  ).toBeVisible();
  await expect(dialog).toContainText('JOB_NOT_FOUND');
  await expect(dialog).toContainText(
    "Job reference error: The job 'load-data' referenced in edge"
  );
  await expect(importCreateButton(page)).toBeDisabled();
  expect(await tipOn(page, importCreateButton(page))).toBe(
    'Fix validation errors to continue'
  );
  expect(workflowsOf(id)).toHaveLength(0);
});

// @S18
// Scenario Outline: Both workflow YAML formats import
//   Given the YAML import dialog is open in paste mode
//   When I paste the canonical workflow in <format> format and click "Create"
//   Then the created workflow has steps "ingest", "load", "maybe skip", "report failure" and "transform"
//   And it has a cron trigger and a webhook trigger
//   Examples:
//     | format                                   |
//     | v1 (jobs, triggers, edges maps)          |
//     | v2 (steps list)                          |
// This is shared-workflow-yaml-format S01, run here for both formats.
test('@S18', PASSING_OLD, async ({ page }) => {
  const id = givenProject();
  await signInAs(page, ME);

  for (const format of ['v1', 'v2'] as const)
    await test.step(format, () =>
      yamlFormat.S01(page, importOpener(page, id), id, format)
    );
});

// @S19
// Scenario: A failed import save keeps the dialog usable
//   Given the YAML import dialog holds valid YAML
//   And the next save will fail
//   When I click "Create"
//   Then the button reads "Importing..." while it saves
//   And afterwards the dialog is still open with my YAML and "Create" is enabled
//   And the landing screen is still shown
// The adaptor catalogue is instance-wide
test('@S19', PASSING_OLD_SERIAL, async ({ page }) => {
  test.setTimeout(240000);
  const id = givenProject();
  await openAs(page, id);
  await pasteYaml(page, KOBO_SYNC);
  await expect(importCreateButton(page)).toBeEnabled();
  givenSavesFail();

  await importCreateButton(page).click();

  await expect(importCreateButton(page)).toHaveText('Importing...');
  await expect(editorToast(page, 'Failed to save workflow')).toBeVisible(
    SAVE_FAILS
  );
  await expect(importTitle(page)).toBeVisible();
  await expect(importText(page)).toHaveValue(KOBO_SYNC);
  await expect(importCreateButton(page)).toHaveText('Create');
  await expect(importCreateButton(page)).toBeEnabled();
  await expect(landingHeading(page)).toBeVisible();
  expect(workflowsOf(id)).toHaveLength(0);
});

// ---------------------------------------------------------------------------
// Creation dialogs
// ---------------------------------------------------------------------------

// @S25
// Scenario: Only one creation dialog is open at a time
//   Given the template browser is open
//   When the YAML import dialog is opened
//   Then the template browser is closed
// With the template browser over the landing screen, the import dialog can
// only be opened from the keyboard.
test('@S25', PASSING_OLD, async ({ page }) => {
  const id = givenProject();
  await openAs(page, id);
  await browseTemplates(page);

  await importByKeyboard(page);

  await expect(importTitle(page)).toBeVisible();
  await expect(templatesTitle(page)).toHaveCount(0);
});

// @S26
// Scenario: Closing a creation dialog returns to the landing screen
//   Given the YAML import dialog is open
//   When I click "Cancel"
//   Then the dialog closes and the landing screen is shown
//   And the same happens when I press Escape or click "Close" on the template browser
test('@S26', PASSING_OLD, async ({ page }) => {
  const id = givenProject();
  await openAs(page, id);
  const backOnLanding = async () => {
    await expect(importTitle(page)).toHaveCount(0);
    await expect(templatesTitle(page)).toHaveCount(0);
    await expect(startCard(page, 'Build from scratch')).toBeVisible();
  };

  await importLink(page).click();
  await expect(importTitle(page)).toBeVisible();
  await importDialog(page).getByRole('button', { name: 'Cancel' }).click();
  await backOnLanding();

  await importLink(page).click();
  await expect(importTitle(page)).toBeVisible();
  await page.keyboard.press('Escape');
  await backOnLanding();

  await browseTemplates(page);
  await page.keyboard.press('Escape');
  await backOnLanding();

  await browseTemplates(page);
  await templatesDialog(page)
    .getByRole('button', { name: 'Close', exact: true })
    .click();
  await backOnLanding();
  expect(workflowsOf(id)).toHaveLength(0);
});

// ---------------------------------------------------------------------------
// Build with AI
// ---------------------------------------------------------------------------

// @S20 @variant:ai-enabled
// Scenario: Editor hands a description to the AI assistant
//   Given the AI assistant is configured on this instance
//   And I am on the new workflow landing screen
//   Then I see "Build with AI" marked "Recommended" with the AI disclaimer and a "Learn more." link
//   When I type "Sync new KoboToolbox submissions into Postgres" and press Enter
//   Then the landing screen closes
//   And the AI assistant panel opens and sends "Sync new KoboToolbox submissions into Postgres" (handoff to workflow-editor-ai-assistant)
// The AI configuration is instance-wide
test('@S20', PASSING_OLD_SERIAL, async ({ page }) => {
  const id = givenProject();
  cleanups.push(withAiAssistant());
  const goal = 'Sync new KoboToolbox submissions into Postgres';
  await openAs(page, id);

  await expect(aiPrompt(page)).toBeVisible();
  await expect(page.getByText('Recommended', { exact: true })).toBeVisible();
  await expect(aiDisclaimer(page)).toBeVisible();
  await expect(page.getByRole('link', { name: 'Learn more.' })).toBeVisible();

  await aiPrompt(page).fill(goal);
  await aiPrompt(page).press('Enter');

  await expect(landingHeading(page)).toHaveCount(0);
  await expect(aiPanel(page)).toBeVisible();
  await expect(aiPanel(page).getByText(goal)).toBeVisible(EVENTUALLY);
});

// @S21 @variant:ai-enabled
// Scenario: Build with AI needs a description
//   Given the AI assistant is configured and I am on the landing screen
//   When the prompt is empty or only spaces
//   Then "Build it" is disabled and Enter does nothing
//   When I type a first line and press Shift+Enter or Alt+Enter
//   Then a new line is added and nothing is sent
// The AI configuration is instance-wide
test('@S21', PASSING_OLD_SERIAL, async ({ page }) => {
  const id = givenProject();
  cleanups.push(withAiAssistant());
  await openAs(page, id);
  const buildIt = page.getByRole('button', { name: 'Build it' });
  const nothingSent = async () => {
    await page.waitForTimeout(500);
    await expect(landingHeading(page)).toBeVisible();
    await expect(aiPanel(page)).not.toBeVisible();
  };

  for (const prompt of ['', '   ']) {
    await aiPrompt(page).fill(prompt);
    await expect(buildIt).toBeDisabled();
    await aiPrompt(page).press('Enter');
    await nothingSent();
  }

  await aiPrompt(page).fill('Fetch Kobo submissions');
  await aiPrompt(page).press('Shift+Enter');
  await expect(aiPrompt(page)).toHaveValue('Fetch Kobo submissions\n');
  await nothingSent();
  await aiPrompt(page).press('Alt+Enter');
  // Chromium adds no line on Alt+Enter; the page only has to leave it unsent
  await expect(aiPrompt(page)).toHaveValue(/^Fetch Kobo submissions\n+$/);
  await nothingSent();
});

// @S22
// Scenario: Without the AI assistant, the other options still show
//   Given the AI assistant is not configured on this instance
//   When I open the new workflow landing screen
//   Then I do not see "Build with AI", "Recommended" or the AI disclaimer
//   And I see "Build from scratch", "Browse templates" and "import a YAML file manually"
// The e2e instance has no AI assistant; the tests that configure one are
// @serial and run after this.
test('@S22', PASSING_OLD, async ({ page }) => {
  const id = givenProject();

  await openAs(page, id);

  await expect(page.getByText('Build with AI')).toHaveCount(0);
  await expect(page.getByText('Recommended', { exact: true })).toHaveCount(0);
  await expect(aiDisclaimer(page)).toHaveCount(0);
  await expect(startCard(page, 'Build from scratch')).toBeVisible();
  await expect(startCard(page, 'Browse templates')).toBeVisible();
  await expect(importLink(page)).toBeVisible();
});

// @S23 @variant:ai-limit-reached
// Scenario: When the AI quota is spent the prompt is disabled with the reason
//   Given project "Malawi HIV" has used its AI assistant quota with the message "AI usage limit reached for this month"
//   When I open the new workflow landing screen
//   Then the "Build with AI" prompt and "Build it" are disabled
//   And hovering the prompt shows "AI usage limit reached for this month"
//   And "Build from scratch" is enabled
// The AI configuration and the usage limiter are instance-wide
test('@S23', PASSING_OLD_SERIAL, async ({ page }) => {
  const limit = 'AI usage limit reached for this month';
  const id = givenProject();
  cleanups.push(withAiAssistant());
  cleanups.push(withLimiterRefusing('ai_usage', limit));

  await openAs(page, id);

  await expect(aiPrompt(page)).toBeDisabled();
  await expect(page.getByRole('button', { name: 'Build it' })).toBeDisabled();
  expect(await aiPromptTip(page)).toBe(limit);
  await expect(startCard(page, 'Build from scratch')).toBeEnabled();
});

// ---------------------------------------------------------------------------
// shared-workflow-yaml-format: the import dialog on the landing screen. S01
// is page S18. Each import that creates a workflow leaves the landing screen,
// so the opener opens a fresh one.
// ---------------------------------------------------------------------------

test.describe('shared-workflow-yaml-format', () => {
  const name = (id: string) =>
    `shared-workflow-yaml-format@${id} on workflow-editor-new`;

  // Page S18 calls it, for both formats
  test(name('S01'), PENDING, () => {
    test.skip(true, 'run by page scenario S18');
  });

  // The code view of the seeded workflow gives the exported YAML
  test(name('S02'), PASSING_OLD, async ({ page }) => {
    const id = givenProject();
    const original = yamlFormat.seedCanonicalWorkflow(id, OWNER);
    await signInAs(page, ME);
    await openEditor(page, id, original.id, panelQuery({ panel: 'code' }));
    const exported = await yamlCode(page).inputValue();

    await yamlFormat.S02(page, importOpener(page, id), id, original, exported);
  });

  // Examples, one step each
  test(name('S03'), PASSING_OLD, async ({ page }) => {
    const id = givenProject();
    await signInAs(page, ME);
    for (const example of yamlFormat.given.S03)
      await test.step(JSON.stringify(example.next), () =>
        yamlFormat.S03(page, importOpener(page, id), id, example)
      );
  });

  test(name('S04'), PASSING_OLD, async ({ page }) => {
    const id = givenProject();
    await signInAs(page, ME);
    await yamlFormat.S04(page, importOpener(page, id), id);
  });

  test(name('S05'), PASSING_OLD, async ({ page }) => {
    const id = givenProject();
    await signInAs(page, ME);
    for (const example of yamlFormat.given.S05)
      await test.step(example.problem, () =>
        yamlFormat.S05(page, importOpener(page, id), id, example)
      );
  });

  test(name('S06'), PASSING_OLD, async ({ page }) => {
    const id = givenProject();
    await signInAs(page, ME);
    for (const format of ['v1', 'v2'] as const)
      await test.step(format, () =>
        yamlFormat.S06(page, importOpener(page, id), id, format)
      );
  });

  test(name('S07'), PASSING_OLD, async ({ page }) => {
    const id = givenProject();
    await signInAs(page, ME);
    await yamlFormat.S07(page, importOpener(page, id), id);
  });

  test(name('S08'), PASSING_OLD, async ({ page }) => {
    const id = givenProject();
    await signInAs(page, ME);
    await yamlFormat.S08(page, importOpener(page, id), id);
  });

  test(name('S09'), PASSING_OLD, async ({ page }) => {
    const id = givenProject();
    await signInAs(page, ME);
    for (const example of yamlFormat.given.S09)
      await test.step(`${example.format} ${String(example.enabled)}`, () =>
        yamlFormat.S09(page, importOpener(page, id), id, example));
  });

  test(name('S10'), PASSING_OLD, async ({ page }) => {
    const id = givenProject();
    const lab = yamlFormat.seedCanonicalWorkflow(id, OWNER, {
      name: 'Lab results',
    });
    await signInAs(page, ME);
    await yamlFormat.S10(page, importOpener(page, id), id, lab);
  });
});

// ---------------------------------------------------------------------------
// shared-project-scope: S06 only. On /w/new a support user also has to pass
// the create-workflow check, which has its own rule for support access. The
// rest runs on /w/:id (workflow-editor-canvas).
// ---------------------------------------------------------------------------

test.describe('shared-project-scope', () => {
  // Support users are instance-wide
  test(
    'shared-project-scope@S06 on workflow-editor-new',
    PASSING_OLD_SERIAL,
    async ({ page }) => {
      const id = givenProject(
        { [OWNER]: 'owner' },
        { allowSupportAccess: true }
      );
      cleanups.push(makeSupportUser(ME));
      await projectScope.S06(
        page,
        newWorkflowPath(id),
        ME,
        startCard(page, 'Build from scratch')
      );
    }
  );
});
