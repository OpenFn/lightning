// The workflow editor's side panels (annotations/views/workflow-editor-inspectors.md):
// the step, trigger and path inspectors, workflow settings, the YAML code view
// and the template publish form. Everything here knows how today's panels are
// built: the URL params that open them, the trigger wizard's steps, the cron
// builder, the path form, and the controls with no accessible name. Specs find
// things through these helpers, so a rebuild only changes this file.
// Editor-wide helpers are in ./workflow-editor.
import { expect, type Locator, type Page } from '@playwright/test';

import {
  exec,
  field,
  lastLine,
  modal,
  modalTitle,
  onNode,
  sql,
  user,
} from '../steps';

import { authMethodDialog } from './project-settings';
import { headerTooltip, panelHeading } from './workflow-editor';

// ---------------------------------------------------------------------------
// Opening a panel
// ---------------------------------------------------------------------------

// The query that opens a panel: { job }, { trigger }, { edge } (a path) or
// { panel: 'settings' | 'code' | 'publish-template' }, with anything else the
// URL carries (a version pin, v)
export const panelQuery = (params: Record<string, string | number>) =>
  `?${new URLSearchParams(
    Object.entries(params).map(([k, v]) => [k, String(v)])
  ).toString()}`;

// The panels' headings, as shown
export const TITLES = {
  settings: 'Workflow settings',
  code: 'Workflow as Code',
  publish: 'Publish Workflow as Template',
  update: 'Update Template',
  path: 'Path',
  webhook: 'On webhook call',
  cron: 'On a schedule',
} as const;

// An open panel, by its heading. Today it is an unnamed card, so it is found
// as the card around its heading.
export const panel = (page: Page, title: string) =>
  page
    .getByRole('complementary', { name: title })
    .or(
      panelHeading(page, title).locator(
        'xpath=ancestor::div[contains(concat(" ", normalize-space(@class), " "), " rounded-lg ")][1]'
      )
    )
    .first();

// The trigger on the canvas. React Flow draws it as a trigger node whose name
// depends on its type.
export const triggerNode = (page: Page) =>
  page.locator('.react-flow__node-trigger').first();

// The tooltip shown when pointing at <control> (Radix tooltips, which open on
// hover of the element they wrap, disabled or not)
export const tooltipOf = (page: Page, control: Locator) =>
  headerTooltip(page, control);

// The "Delete" button in a panel's footer
export const deleteButton = (within: Locator) =>
  within.getByRole('button', { name: 'Delete', exact: true });

// ---------------------------------------------------------------------------
// The step inspector
// ---------------------------------------------------------------------------

// The adaptor box under "Adaptor": the adaptor, its version and credential,
// with "Change adaptor" and "Edit" or "Connect". Today "Adaptor" is a bare
// label with no control of its own, so the box is the element after it.
export const adaptorBox = (page: Page) =>
  page
    .getByRole('group', { name: 'Adaptor' })
    .or(
      page
        .locator('label')
        .filter({ hasText: /^\s*Adaptor\s*$/ })
        .locator('xpath=following-sibling::*[1]')
    )
    .first();

// When I open the adaptor picker from the adaptor box
export const openAdaptorPicker = (box: Locator) =>
  box.getByRole('button', { name: /^Change( adaptor)?$/ }).click();

// A credential's choice in "Configure connection"
export const connectionChoice = (page: Page, name: string) =>
  modal(page, 'Configure connection').getByRole('radio', {
    name: new RegExp(`\\b${name}\\b`),
  });

// The step inspector's code button (an icon button named "Code")
export const codeButton = (page: Page) =>
  page.getByRole('button', { name: 'Code', exact: true });

// When I delete step <name> from its inspector and confirm "Delete Job"
export async function deleteStep(page: Page, name: string) {
  await deleteButton(panel(page, name)).click();
  await expect(modalTitle(page, 'Delete Job?')).toBeVisible();
  await modal(page, 'Delete Job?')
    .getByRole('button', { name: 'Delete Job', exact: true })
    .click();
  await expect(modalTitle(page, 'Delete Job?')).toBeHidden();
}

// ---------------------------------------------------------------------------
// The trigger inspector and its wizard (Choose, then Configure, then Finish)
// ---------------------------------------------------------------------------

export const editTriggerButton = (page: Page) =>
  page.getByRole('button', { name: 'Edit trigger' });

export const finishButton = (page: Page) =>
  page.getByRole('button', { name: 'Finish', exact: true });

export const cancelButton = (page: Page) =>
  page.getByRole('button', { name: 'Cancel', exact: true });

// When I click "Edit" on the trigger: the wizard opens on Choose
export async function editTrigger(page: Page) {
  await editTriggerButton(page).click();
  await expect(page.getByRole('button', { name: 'Next' })).toBeVisible();
}

// On Choose: when I click "Next" and the wizard moves on to Configure
export async function toConfigure(page: Page) {
  await page.getByRole('button', { name: 'Next' }).click();
  await expect(finishButton(page)).toBeVisible();
}

// When I open the trigger wizard and go on to Configure
export async function openTriggerWizard(page: Page) {
  await editTrigger(page);
  await toConfigure(page);
}

// When I choose <option> in the field labelled <label> (native selects today:
// the cron builder, "Cron Input Source", a path's "Condition")
export const choose = (page: Page, label: string, option: string) =>
  field(page, label).selectOption({ label: option });

// On Choose: when I click "Change" and pick <to> ("On webhook call", "On a
// schedule"); the wizard returns to Choose for that type
export async function changeTriggerType(
  page: Page,
  to: (typeof TITLES)['webhook' | 'cron']
) {
  await page.getByRole('button', { name: 'Change', exact: true }).click();
  await page.getByRole('button', { name: new RegExp(`^${to}`) }).click();
  await expect(panelHeading(page, to)).toBeVisible();
  await expect(page.getByRole('button', { name: 'Next' })).toBeVisible();
}

// A webhook URL in the list, by its label ("Default", "Custom")
export const webhookUrl = (page: Page, label: 'Default' | 'Custom') =>
  page
    .getByRole('listitem')
    .filter({ has: page.getByText(label, { exact: true }) });

// The copy button on a webhook URL. Today it is an icon button named for what
// it does, or "Not a usable URL yet" when the URL can't be copied.
export const copyUrlButton = (page: Page, label: 'Default' | 'Custom') =>
  webhookUrl(page, label).getByRole('button', {
    name: new RegExp(`^(Copy ${label} URL|Not a usable URL yet|Copied.*)$`),
  });

// The custom URL controls on Configure
export const addCustomUrl = (page: Page) =>
  page.getByRole('button', { name: 'Add custom URL' }).click();
export const customPathField = (page: Page) => field(page, 'Custom path');
export const deleteCustomUrl = (page: Page) =>
  page.getByRole('button', { name: 'Delete custom URL' }).click();

// The "Authentication" section's header, which says how many methods are
// attached on the resting panel
export const authenticationToggle = (page: Page) =>
  page.getByRole('button', { name: /^Authentication(\s*\(.*\))?$/ });

// The auth method pickers under "Authentication", one per attached method
export const authPickers = (page: Page) =>
  page.getByRole('button', { name: /^Authentication credential \d+$/ });

// On Configure: when I attach auth method <name> in the last picker
export async function chooseAuthMethod(page: Page, name: string) {
  await authPickers(page).last().click();
  await page.getByRole('option', { name: new RegExp(`^${name}`) }).click();
}

export const createAuthMethodButton = (page: Page) =>
  page.getByRole('button', { name: 'Create a new authentication method' });

// The auth method form the trigger opens (the LiveView form shared with
// project settings), on its first step
export const authMethodForm = (page: Page) =>
  authMethodDialog(page, 'Basic HTTP Authentication');

// Its first step has no "Cancel", only the close button
export const cancelAuthMethodForm = (page: Page) =>
  authMethodForm(page)
    .getByRole('button', { name: /^(cancel|close)$/i })
    .first()
    .click();

// On Configure: when I set "Response Type" to <choice>. Today it is a listbox
// whose options carry a description under their name.
export async function chooseResponseType(
  page: Page,
  choice: 'Immediately' | 'On Complete'
) {
  await page
    .getByRole('button', { name: /Response Type/ })
    .or(
      page
        .getByText('Response Type', { exact: true })
        .locator('xpath=following::button[1]')
    )
    .first()
    .click();
  await page.getByRole('option', { name: new RegExp(`^${choice}`) }).click();
}

// On Configure, with "On Complete": the default status code fields
export async function expandResponseOptions(page: Page) {
  await page.getByRole('button', { name: 'Response Options' }).click();
  await expect(field(page, 'Success Code')).toBeVisible();
}

// The cron builder's raw expression. Today it sits under a collapsed "Cron
// Expression" toggle and has no label, only its placeholder.
export async function cronExpressionField(page: Page) {
  const box = page
    .getByRole('textbox', { name: 'Cron Expression' })
    .or(page.getByPlaceholder('0 0 * * *'))
    .first();
  if (!(await box.isVisible()))
    await page.getByRole('button', { name: 'Cron Expression' }).click();
  await expect(box).toBeVisible();
  return box;
}

// A value on a resting trigger panel ("Frequency", "Cron Input Source"): a
// caption above a read-only box
export const shownValue = (page: Page, label: string) =>
  page
    .getByText(label, { exact: true })
    .locator('xpath=following-sibling::*[1]');

// ---------------------------------------------------------------------------
// The path inspector
// ---------------------------------------------------------------------------

// The choices "Condition" offers, in order (a native select today)
export const conditionChoices = (page: Page) =>
  field(page, 'Condition').locator('option').allInnerTexts();

// The warning about an unsafe path expression. Today it is an icon beside the
// "Javascript Expression" label, explained only by its tooltip.
export async function expressionWarning(page: Page) {
  const said = page.getByText(/potentially unsafe functions/);
  if (await said.isVisible()) return (await said.innerText()).trim();
  const mark = page
    .locator('label')
    .filter({ hasText: 'Javascript Expression' })
    .locator('xpath=following-sibling::*[1]');
  return tooltipOf(page, mark);
}

// The path's "Enabled" switch
export const pathEnabled = (page: Page) =>
  panel(page, TITLES.path).getByRole('checkbox', { name: 'Enabled' });

// When I delete the open path and confirm. Today the confirmation is the
// browser's own dialog.
export async function deletePath(page: Page) {
  page.once('dialog', d => void d.accept());
  await deleteButton(panel(page, TITLES.path)).click();
}

// ---------------------------------------------------------------------------
// Workflow settings, the code view and the template form
// ---------------------------------------------------------------------------

// A switch in a panel, by its label ("Allow console.log() usage", "Enabled").
// Today it is a visually hidden checkbox drawn as a switch.
export const switchNamed = (within: Page | Locator, label: string) =>
  within
    .getByRole('switch', { name: label })
    .or(within.getByRole('checkbox', { name: label }))
    .first();

// When I flip that switch, by clicking its label
export const flip = (within: Page | Locator, label: string) =>
  within.getByText(label, { exact: true }).click();

export const resetButton = (page: Page) =>
  page.getByRole('button', { name: 'Reset to Latest Snapshot' });

// When I click "Reset to Latest Snapshot" and confirm "Reset Workflow"
export async function resetToLatest(page: Page) {
  await resetButton(page).click();
  await expect(modalTitle(page, 'Reset Workflow?')).toBeVisible();
  await modal(page, 'Reset Workflow?')
    .getByRole('button', { name: 'Reset Workflow', exact: true })
    .click();
  await expect(modalTitle(page, 'Reset Workflow?')).toBeHidden();
}

// When I click "View your workflow as YAML code" in workflow settings
export async function viewAsYaml(page: Page) {
  await page
    .getByRole('button', { name: 'View your workflow as YAML code' })
    .or(page.getByRole('link', { name: 'View your workflow as YAML code' }))
    .first()
    .click();
  await expect(panelHeading(page, TITLES.code)).toBeVisible();
}

// The YAML shown in the code view
export const yamlCode = (page: Page) =>
  page.getByRole('textbox', { name: 'Workflow YAML code' });

// When I click "Download" — resolves to the file's name
export async function downloadYaml(page: Page) {
  const [file] = await Promise.all([
    page.waitForEvent('download'),
    page.getByRole('button', { name: 'Download', exact: true }).click(),
  ]);
  return file.suggestedFilename();
}

export const copyYamlButton = (page: Page) =>
  page.getByRole('button', { name: /^(Copy Code|Copied.*)$/ });

// "Publish Template", or "Update Template" once the workflow has one
export const publishButton = (page: Page) =>
  page.getByRole('button', { name: /^(Publish|Update) Template$/ });

// Why "Publish Template" is off. Today the reason is the button's title.
export async function publishReason(page: Page) {
  const title = await publishButton(page).getAttribute('title');
  return title || tooltipOf(page, publishButton(page));
}

// When I click "Publish Template" in the code view, enter <tags> and publish
// An earlier toast can sit over the button, so it is pressed with Enter
export async function publishTemplate(page: Page, tags: string) {
  await publishButton(page).press('Enter');
  await expect(
    page.getByRole('heading', {
      level: 2,
      name: new RegExp(`^(${TITLES.publish}|${TITLES.update})$`),
    })
  ).toBeVisible();
  if ((await field(page, 'Name').inputValue()) === '')
    await field(page, 'Name').fill('Intake');
  await field(page, 'Tags').fill(tags);
  await publishButton(page).press('Enter');
}

// ---------------------------------------------------------------------------
// Reading and seeding
// ---------------------------------------------------------------------------

// The id of the path from <from> to <to> in workflow <workflowId>, by step
// name; "trigger" for the path leaving the trigger
export function pathIdOf(workflowId: string, from: string, to: string) {
  const source =
    from === 'trigger'
      ? 'e.source_trigger_id is not null'
      : `sj.name = $n$${from}$n$`;
  return sql<{ id: string }>(
    `select e.id from workflow_edges e
       left join jobs sj on sj.id = e.source_job_id
       join jobs tj on tj.id = e.target_job_id
     where e.workflow_id = '${workflowId}' and ${source} and tj.name = $n$${to}$n$`
  )[0].id;
}

export type TriggerSeed = {
  custom_path?: string;
  webhook_reply?: 'before_start' | 'after_completion';
  /** the job id a schedule takes its input from */
  cron_cursor_job_id?: string;
};

// Given trigger <triggerId> is saved with these settings. Before anyone opens
// the workflow: the shared draft is built from what is saved.
export function setTrigger(triggerId: string, seed: TriggerSeed) {
  const sets = Object.entries(seed).map(([k, v]) => `${k} = $v$${v}$v$`);
  exec(`update triggers set ${sets.join(', ')} where id = '${triggerId}'`);
}

// Given project <projectId> allows <n> concurrent runs
export const setProjectConcurrency = (projectId: string, n: number) =>
  exec(`update projects set concurrency = ${n} where id = '${projectId}'`);

export type DraftTrigger = {
  id: string;
  type: 'webhook' | 'cron';
  enabled: boolean;
  custom_path: string | null;
  webhook_reply: string | null;
  webhook_response_config: {
    success_code: number | null;
    error_code: number | null;
  } | null;
  cron_expression: string | null;
  cron_cursor_job_id: string | null;
};

export type DraftEdge = {
  id: string;
  source_job_id: string | null;
  target_job_id: string;
  enabled: boolean;
  condition_type: string;
};

export type Draft = {
  name: string;
  jobs: { id: string; name: string }[];
  edges: DraftEdge[];
  triggers: DraftTrigger[];
};

// The shared (unsaved) draft of workflow <id> as the server holds it while
// someone has it open, or null when nobody does
export function draftOf(id: string): Draft | null {
  const out = onNode(`
    case Lightning.Collaboration.Session.lookup_shared_doc("workflow:${id}") do
      nil -> "null"
      pid ->
        pid
        |> Yex.Sync.SharedDoc.get_doc()
        |> Lightning.Collaboration.WorkflowSerializer.deserialize_from_ydoc("${id}")
        |> Map.take(["name", "jobs", "edges", "triggers"])
        |> Jason.encode!()
    end`);
  return JSON.parse(JSON.parse(lastLine(out)) as string) as Draft | null;
}

// The first trigger of the shared draft of workflow <id>
export const draftTrigger = (id: string) => draftOf(id)?.triggers[0];

// Given the last save of workflow <workflowId> came back with <message> on
// <field> of the step, trigger or path <id>. The server writes a refused
// save's errors into the shared draft for everyone; this writes them the same
// way. Someone must have the workflow open.
export function showSaveErrorOnNode(
  workflowId: string,
  kind: 'jobs' | 'triggers' | 'edges',
  id: string,
  fieldName: string,
  message: string
) {
  const errors = JSON.stringify({ [id]: { [fieldName]: [message] } });
  onNode(`
    pid = Lightning.Collaboration.Session.lookup_shared_doc("workflow:${workflowId}")
    Yex.Sync.SharedDoc.update_doc(pid, fn doc ->
      errors = Yex.Doc.get_map(doc, "errors")
      Yex.Doc.transaction(doc, "scenario_save_errors", fn ->
        Yex.Map.set(errors, "${kind}", Jason.decode!(${JSON.stringify(errors)}))
      end)
    end)
    :ok`);
}

// Given webhook auth methods <methodIds> are attached to trigger <triggerId>,
// by "<by>" through Lightning
export function attachAuthMethodsOnNode(
  triggerId: string,
  methodIds: string[],
  by: string
) {
  onNode(`
    import Ecto.Query
    trigger = Lightning.Repo.get!(Lightning.Workflows.Trigger, "${triggerId}")
    ids = ${JSON.stringify(methodIds)}
    methods = Lightning.Repo.all(from w in Lightning.Workflows.WebhookAuthMethod, where: w.id in ^ids)
    actor = Lightning.Repo.get!(Lightning.Accounts.User, "${user(by).id}")
    {:ok, _} = Lightning.WebhookAuthMethods.update_trigger_auth_methods(trigger, methods, actor: actor)
    :ok`);
}

// The names of the auth methods attached to trigger <triggerId>, as saved
export const authMethodsOn = (triggerId: string) =>
  sql<{ name: string }>(
    `select w.name from trigger_webhook_auth_methods t
       join webhook_auth_methods w on w.id = t.webhook_auth_method_id
     where t.trigger_id = '${triggerId}' order by w.name`
  ).map(r => r.name);

// What a request with no credentials to trigger <triggerId>'s default URL is
// answered with
export const postToWebhook = (page: Page, triggerId: string) =>
  page.request.post(`/i/${triggerId}`, { data: { from: 'scenario' } });

// The templates published from workflow <workflowId>
export const templatesOf = (workflowId: string) =>
  sql<{ id: string; name: string; tags: string[] }>(
    `select id, name, tags from workflow_templates where workflow_id = '${workflowId}'`
  );

export const removeTemplatesOf = (workflowId: string) =>
  exec(`delete from workflow_templates where workflow_id = '${workflowId}'`);
