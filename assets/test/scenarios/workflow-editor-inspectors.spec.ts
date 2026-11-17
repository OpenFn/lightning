// Scenarios from annotations/views/workflow-editor-inspectors.md, and the
// shared scenarios the side panels inherit.
//
// Who's who: "I" is editor@openfn.org; each test gives me the role its Given
// names. owner@openfn.org owns every project and saves its workflows through
// Lightning; super@openfn.org stands in for "amara@example.org", the
// collaborator a test needs. Every project ("Malawi HIV" and any other) is
// seeded by the test and removed again afterwards, with its workflows. "Intake"
// is a webhook trigger leading to "Fetch", then "Load" on success, unless a
// test says otherwise.
//
// The editor is not being ported: these record what today's panels do,
// through pages/workflow-editor-inspectors.ts, so a rebuild that keeps the
// Value passes.
import { expect, test, type Page } from '@playwright/test';
import YAML from 'yaml';

import { chooseAuthType } from './pages/project-settings';
import {
  editorQuery,
  editorReady,
  editorToast,
  node,
  openEditor,
  openSettings,
  panelHeading,
  renameStep,
  renameWorkflow,
  saveButton,
  watchEditorSocket,
  workflowSwitch,
} from './pages/workflow-editor';
import {
  TITLES,
  adaptorBox,
  addCustomUrl,
  attachAuthMethodsOnNode,
  authMethodForm,
  authMethodsOn,
  authPickers,
  authenticationToggle,
  cancelAuthMethodForm,
  cancelButton,
  changeTriggerType,
  choose,
  chooseAuthMethod,
  chooseResponseType,
  codeButton,
  conditionChoices,
  connectionChoice,
  copyUrlButton,
  copyYamlButton,
  createAuthMethodButton,
  cronExpressionField,
  customPathField,
  deleteButton,
  deleteCustomUrl,
  deletePath,
  deleteStep,
  downloadYaml,
  draftOf,
  draftTrigger,
  editTrigger,
  editTriggerButton,
  expandResponseOptions,
  expressionWarning,
  finishButton,
  flip,
  openAdaptorPicker,
  openTriggerWizard,
  panel,
  panelQuery,
  pathEnabled,
  pathIdOf,
  postToWebhook,
  publishButton,
  publishReason,
  publishTemplate,
  removeTemplatesOf,
  resetButton,
  resetToLatest,
  setProjectConcurrency,
  setTrigger,
  showSaveErrorOnNode,
  shownValue,
  switchNamed,
  templatesOf,
  toConfigure,
  tooltipOf,
  triggerNode,
  viewAsYaml,
  webhookUrl,
  yamlCode,
} from './pages/workflow-editor-inspectors';
import * as adaptorConfig from './shared/adaptor-credential-config';
import * as runRetry from './shared/run-retry-controls';
import {
  addWebhookAuthMethodOnNode,
  catalogueUnavailable,
  changeRoleOnNode,
  deleteWorkflowOnNode,
  field,
  fieldBlock,
  goLiveOnNode,
  keepAccount,
  makeSupportUser,
  modal,
  modalTitle,
  otherSession,
  removeCredentialsNamed,
  removeWorkflowData,
  renameStepOnNode,
  seedCredential,
  seedEditorWorkflow,
  seedKeychain,
  seedWorkspace,
  setPreferences,
  sharedDocOf,
  signInAs,
  storedWorkflow,
  submit,
  watchLiveView,
  type EditorWorkflow,
  type EditorWorkflowSeed,
  type WorkspaceSeed,
} from './steps';

const ME = 'editor@openfn.org';
const OWNER = 'owner@openfn.org';
const THIRD = 'super@openfn.org';

type Role = 'owner' | 'admin' | 'editor' | 'viewer';

const PENDING = { tag: '@pending' };
const PENDING_SERIAL = { tag: ['@pending', '@serial'] };
const PASSING_OLD = { tag: '@passing-old' };
const PASSING_OLD_SERIAL = { tag: ['@passing-old', '@serial'] };

// A page that has to react to something done elsewhere gets this long
const EVENTUALLY = { timeout: 15000 };

const DHIS2 = '@openfn/language-dhis2@latest';
const SALESFORCE = '@openfn/language-salesforce@latest';
const KOBO = { username: 'kobo', password: 'testpassword123' };
const NO_PERMISSION = 'You do not have permission to edit this workflow';
const LIVE =
  'This workflow is live. Switch to draft or edit in a sandbox to make changes.';
const LOGS = 'Allow console.log() usage';

let cleanups: (() => void)[] = [];
test.beforeEach(() => {
  // Some tests change my preferences or support flag
  cleanups = [keepAccount(ME)];
});
test.afterEach(() => {
  for (const cleanup of cleanups.reverse()) cleanup();
});

// Given project <name> exists with these members (owner@openfn.org owns it
// unless another owner is named) — removed after the test with its workflows
function givenProject(
  members: Record<string, Role> = { [ME]: 'editor' },
  { name = 'Malawi HIV', ...rest }: Partial<WorkspaceSeed> = {}
) {
  const owned = Object.values(members).includes('owner')
    ? members
    : { ...members, [OWNER]: 'owner' as const };
  const by = Object.entries(owned).find(([, r]) => r === 'owner')![0];
  const w = seedWorkspace({ name, members: owned, ...rest }, by);
  cleanups.push(w.remove);
  const id = w.id(name);
  cleanups.push(() => removeWorkflowData(id));
  return { id, w, by };
}

// Given project "Malawi HIV" with these members has workflow "Intake" (or
// <seed>'s), saved by its owner
function givenIntake(
  members: Record<string, Role> = { [ME]: 'editor' },
  seed: EditorWorkflowSeed = {},
  project: Partial<WorkspaceSeed> = {}
) {
  const p = givenProject(members, project);
  const wf = seedEditorWorkflow(p.id, p.by, seed);
  return { ...p, wf };
}

// When I sign in as <email> and open <wf> in the editor, with <query>
async function openAs(page: Page, wf: EditorWorkflow, email = ME, query = '') {
  await signInAs(page, email);
  await openEditor(page, wf.projectId, wf.id, query);
}

// When I open <wf> again with <query>, already signed in
const reopen = (page: Page, wf: EditorWorkflow, query = '') =>
  openEditor(page, wf.projectId, wf.id, query);

// The query that opens step <name>'s inspector
const stepOf = (wf: EditorWorkflow, name: string) =>
  panelQuery({ job: wf.steps[name] });

// Given I have experimental features on
function experimental() {
  setPreferences(ME, { experimental_features: true });
}

// Given <email> has experimental features off (put back after the test)
function withoutExperimental(email: string) {
  if (email !== ME) cleanups.push(keepAccount(email));
  setPreferences(email, { experimental_features: false });
}

// Given "<owner>" owns credential <name> of <schema>, shared with project
// <projectId> — removed after the test
function givenCredential(
  projectId: string,
  name: string,
  { schema = 'dhis2', owner = OWNER, secret = 'district' } = {}
) {
  const c = seedCredential(owner, {
    name,
    schema,
    bodies: {
      main: {
        username: 'admin',
        password: secret,
        hostUrl: 'https://play.dhis2.example.org',
      },
    },
    projects: [projectId],
  });
  cleanups.push(c.remove);
  return c.id;
}

// When I save the workflow
async function saveWorkflow(page: Page) {
  await saveButton(page).click();
  await expect(editorToast(page, 'Workflow saved')).toBeVisible();
}

// What my clipboard holds
const clipboard = (page: Page) =>
  page.evaluate(() => navigator.clipboard.readText());

// Then on "Fetch", the trigger and (unless left out) the path from "Fetch" to
// "Load", the fields are disabled, and "Edit trigger" and the delete buttons
// are disabled with <reason>. Soft, so every panel is checked.
async function expectPanelsLocked(
  page: Page,
  wf: EditorWorkflow,
  reason: string,
  { path = true } = {}
) {
  await reopen(page, wf, stepOf(wf, 'Fetch'));
  await expect.soft(field(page, 'Job Name')).toBeDisabled();
  const step = deleteButton(panel(page, 'Fetch'));
  await expect.soft(step).toBeDisabled();
  expect.soft(await tooltipOf(page, step)).toBe(reason);

  await reopen(page, wf, panelQuery({ trigger: wf.triggerId! }));
  await expect.soft(editTriggerButton(page)).toBeDisabled();
  expect.soft(await tooltipOf(page, editTriggerButton(page))).toBe(reason);

  if (!path) return;
  await reopen(
    page,
    wf,
    panelQuery({ edge: pathIdOf(wf.id, 'Fetch', 'Load') })
  );
  for (const label of ['Label', 'Condition'])
    await expect.soft(field(page, label), label).toBeDisabled();
  const edge = deleteButton(panel(page, TITLES.path));
  await expect.soft(edge).toBeDisabled();
  expect.soft(await tooltipOf(page, edge)).toBe(reason);
}

// ---------------------------------------------------------------------------
// Steps
// ---------------------------------------------------------------------------

// @S01
// Scenario: Selecting a step opens its inspector
//   Given I am an editor on "Malawi HIV"
//   When I open "Intake" with "?job=<Fetch id>"
//   Then I see a panel titled "Fetch" with "Job Name" and "Adaptor"
//   When I open "?job=<Fetch id>&panel=settings"
//   Then I see "Workflow settings" instead
test('@S01', PASSING_OLD, async ({ page }) => {
  const { wf } = givenIntake();
  await openAs(page, wf, ME, stepOf(wf, 'Fetch'));

  await expect(panelHeading(page, 'Fetch')).toBeVisible();
  await expect(field(page, 'Job Name')).toHaveValue('Fetch');
  await expect(adaptorBox(page)).toBeVisible();

  await reopen(
    page,
    wf,
    panelQuery({ job: wf.steps.Fetch, panel: 'settings' })
  );
  await expect(panelHeading(page, TITLES.settings)).toBeVisible();
  await expect(panelHeading(page, 'Fetch')).toHaveCount(0);
});

// @S02
// Scenario: Step edits reach collaborators and theirs reach me
//   Given "amara@example.org" and I are editors with "Fetch" open
//   When I rename "Fetch" to "Fetch patients"
//   Then "amara@example.org" sees "Fetch patients" in the "Job Name" field without reloading
test('@S02', PASSING_OLD, async ({ page, browser }) => {
  const { wf } = givenIntake({ [ME]: 'editor', [THIRD]: 'editor' });
  const amara = await otherSession(browser, THIRD);
  await reopen(amara, wf, stepOf(wf, 'Fetch'));
  await openAs(page, wf, ME, stepOf(wf, 'Fetch'));

  await field(page, 'Job Name').fill('Fetch patients');

  await expect(field(amara, 'Job Name')).toHaveValue(
    'Fetch patients',
    EVENTUALLY
  );
  // and theirs reach me
  await field(amara, 'Job Name').fill('Fetch all');
  await expect(field(page, 'Job Name')).toHaveValue('Fetch all', EVENTUALLY);
});

// @S03
// Scenario: A step's validation errors show on its own fields
//   Given the workflow error map holds a "name" error for "Fetch"
//   When I open "Fetch"
//   Then the "Job Name" field shows that error
//   And opening "Load" shows no error
test('@S03', PASSING_OLD, async ({ page }) => {
  const { wf } = givenIntake();
  const error = 'has already been taken';
  await openAs(page, wf);
  showSaveErrorOnNode(wf.id, 'jobs', wf.steps.Fetch, 'name', error);

  await node(page, 'Fetch').click();
  await expect(fieldBlock(page, 'Job Name')).toContainText(error);

  await node(page, 'Load').click();
  await expect(panelHeading(page, 'Load')).toBeVisible();
  await expect(fieldBlock(page, 'Job Name')).not.toContainText(error);
});

// @S04
// Scenario Outline: A step without a credential is flagged when its adaptor needs one
//   Given "Fetch" uses <adaptor> and has no credential
//   When I open "Fetch"
//   Then the adaptor box offers "<button>"
//   Examples:
//     | adaptor                       | button  |
//     | @openfn/language-dhis2@latest | Connect |
//     | @openfn/language-http@latest  | Edit    |
// Same as shared-adaptor-credential-config S01; one step per example.
test('@S04', PASSING_OLD, async ({ page }) => {
  const { wf } = givenIntake();
  const [dhis2, http] = adaptorConfig.given.S01;
  adaptorConfig.jobUses(wf.steps.Fetch, dhis2.adaptor);
  adaptorConfig.jobUses(wf.steps.Load, http.adaptor);
  await signInAs(page, ME);

  for (const [step, example] of [
    ['Fetch', dhis2],
    ['Load', http],
  ] as const)
    await test.step(example.adaptor, async () => {
      await reopen(page, wf, stepOf(wf, step));
      await adaptorConfig.S01(page, adaptorBox(page), example.button);
    });
});

// @S05
// Scenario: Picking a credential attaches it to the step
//   Given "Fetch" uses the DHIS2 adaptor
//   And the project has DHIS2 credential "DHIS2 prod"
//   When I open "Configure connection" from "Fetch" and choose "DHIS2 prod"
//   Then "Fetch" shows a "DHIS2 prod" credential badge
//   And the step's project credential is set and its keychain credential is empty
//   When I clear the selection
//   Then "Fetch" has no credential
// Shared-adaptor-credential-config S03, which also picks a keychain in between.
test('@S05', PASSING_OLD, async ({ page }) => {
  const { id, wf } = givenIntake();
  adaptorConfig.jobUses(wf.steps.Fetch, DHIS2);
  givenCredential(id, 'DHIS2 prod');
  seedKeychain(id, { name: 'Per facility', path: '$.facility_id' }, OWNER);
  await openAs(page, wf, ME, stepOf(wf, 'Fetch'));

  await adaptorConfig.S03(
    page,
    adaptorBox(page),
    { projectId: id, jobId: wf.steps.Fetch },
    () => saveWorkflow(page)
  );
});

// @S06
// Scenario: Credentials that match the adaptor are offered first
//   Given "Fetch" uses the Salesforce adaptor
//   And the project has a Salesforce credential, a raw credential and a keychain credential
//   When I open "Configure connection"
//   Then I see only the Salesforce credential
//   When I click "Other credentials"
//   Then I see the raw one under "Generic Credentials" and the keychain under "Keychain Credentials"
// Same as shared-adaptor-credential-config S04.
test('@S06', PASSING_OLD, async ({ page }) => {
  const { id, wf } = givenIntake();
  adaptorConfig.jobUses(wf.steps.Fetch, SALESFORCE);
  givenCredential(id, 'Salesforce prod', { schema: 'salesforce' });
  givenCredential(id, 'Raw token', { schema: 'raw' });
  seedKeychain(id, { name: 'Per facility' }, OWNER);
  await openAs(page, wf, ME, stepOf(wf, 'Fetch'));

  await adaptorConfig.S04(page, adaptorBox(page), {
    salesforce: 'Salesforce prod',
    raw: 'Raw token',
    keychain: 'Per facility',
  });
});

// Given "Fetch" of a new "Intake" uses DHIS2 with credential "DHIS2 prod",
// and I have it open
async function givenFetchOnDhis2(page: Page, role: Role = 'editor') {
  const h = givenIntake({ [ME]: role });
  const credentialId = givenCredential(h.id, 'DHIS2 prod');
  adaptorConfig.jobUses(h.wf.steps.Fetch, DHIS2, {
    projectId: h.id,
    credentialId,
  });
  await openAs(page, h.wf, ME, stepOf(h.wf, 'Fetch'));
  return h;
}

// @S07
// Scenario: Changing adaptor on a step with a credential asks first and clears it
//   Given "Fetch" uses DHIS2 with credential "DHIS2 prod"
//   When I pick "Salesforce" in the adaptor picker
//   Then I see "Change Adaptor?" warning that the credential will be reset
//   When I click "Continue"
//   Then "Fetch" uses Salesforce and has no credential
//   And "Configure connection" opens
// Shared-adaptor-credential-config S05, which first re-picks DHIS2.
test('@S07', PASSING_OLD, async ({ page }) => {
  const { id, wf } = await givenFetchOnDhis2(page);

  await adaptorConfig.S05(
    page,
    adaptorBox(page),
    { projectId: id, jobId: wf.steps.Fetch },
    () => saveWorkflow(page)
  );
});

// @S08
// Scenario: Cancelling an adaptor change keeps everything as it was
//   Given "Fetch" uses DHIS2 with credential "DHIS2 prod"
//   When I pick "Salesforce" and then "Cancel" the warning
//   Then "Fetch" still uses DHIS2 with "DHIS2 prod"
//   And the adaptor picker is open again
// Same as shared-adaptor-credential-config S06.
test('@S08', PASSING_OLD, async ({ page }) => {
  await givenFetchOnDhis2(page);

  await adaptorConfig.S06(page, adaptorBox(page));
});

// @S09
// Scenario: A step can be pinned to an adaptor version
//   Given the DHIS2 adaptor has versions "4.2.0", "4.10.0" and "4.9.1"
//   When I open "Configure connection" on "Fetch"
//   Then the version list reads "latest", "4.10.0", "4.9.1", "4.2.0"
//   When I choose "4.9.1"
//   Then "Fetch" shows "v4.9.1"
// Same as shared-adaptor-credential-config S07. The adaptor catalogue is
// instance-wide.
test('@S09', PASSING_OLD_SERIAL, async ({ page }) => {
  cleanups.push(adaptorConfig.withAdaptorVersions());
  const { wf } = givenIntake();
  adaptorConfig.jobUses(wf.steps.Fetch, DHIS2);
  await openAs(page, wf, ME, stepOf(wf, 'Fetch'));

  await adaptorConfig.S07(page, adaptorBox(page));
});

// @S10
// Scenario: Searching for an adaptor that does not exist suggests HTTP
//   When I search the adaptor picker for "zzz-unknown"
//   Then I see "No adaptor found" and the HTTP adaptor
// Shared-adaptor-credential-config S08, which also chooses HTTP with Enter.
test('@S10', PASSING_OLD, async ({ page }) => {
  const { wf } = givenIntake();
  await openAs(page, wf, ME, stepOf(wf, 'Fetch'));

  await adaptorConfig.S08(
    page,
    () => openAdaptorPicker(adaptorBox(page)),
    adaptorBox(page)
  );
});

// @S11
// Scenario: A failed adaptor catalogue load can be retried
//   Given the adaptor catalogue request fails
//   When I open the adaptor picker
//   Then I see "Couldn't load adaptors. Please try again." and "Retry"
//   When the catalogue becomes available and I click "Retry"
//   Then the adaptor list appears
// Same as shared-adaptor-credential-config S09. The adaptor catalogue is
// instance-wide.
test('@S11', PASSING_OLD_SERIAL, async ({ page }) => {
  let putBack: (() => void) | null = catalogueUnavailable();
  const makeAvailable = () => {
    putBack?.();
    putBack = null;
  };
  cleanups.push(makeAvailable);
  const { wf } = givenIntake();
  await openAs(page, wf, ME, stepOf(wf, 'Fetch'));

  await adaptorConfig.S09(
    page,
    () => openAdaptorPicker(adaptorBox(page)),
    makeAvailable
  );
});

// @S12
// Scenario: A credential created from a step is attached to it and offered to collaborators
//   Given I am an editor with "Fetch" (DHIS2) open and "amara@example.org" has "Intake" open
//   When I click "New Credential" in "Configure connection" and save a DHIS2 credential "DHIS2 test"
//   Then "Fetch" has "DHIS2 test" as its project credential
//   And "Configure connection" opens again with "DHIS2 test" selected
//   And "credentials_updated" is broadcast on "workflow:collaborate:<Intake id>"
//   And "amara@example.org" sees "DHIS2 test" in her credential list
// Shared-adaptor-credential-config S11, then the collaborator's list.
test('@S12', PASSING_OLD, async ({ page, browser }) => {
  const { id, wf } = givenIntake({ [ME]: 'editor', [THIRD]: 'editor' });
  cleanups.push(() => removeCredentialsNamed(ME, ['DHIS2 test']));
  adaptorConfig.jobUses(wf.steps.Fetch, DHIS2);
  const amara = await otherSession(browser, THIRD);
  await reopen(amara, wf, stepOf(wf, 'Fetch'));
  const sock = await watchEditorSocket(page);
  await openAs(page, wf, ME, stepOf(wf, 'Fetch'));

  await adaptorConfig.S11(
    page,
    adaptorBox(page),
    { projectId: id, jobId: wf.steps.Fetch, projectName: 'Malawi HIV' },
    () => saveWorkflow(page)
  );

  expect(sock.pushed('credentials_updated').length).toBeGreaterThan(0);
  await adaptorConfig.configureButton(adaptorBox(amara)).click();
  await expect(connectionChoice(amara, 'DHIS2 test')).toBeVisible(EVENTUALLY);
});

// @S13
// Scenario: Only a credential's owner can edit it from a step
//   Given "DHIS2 prod" is owned by "amara@example.org" and shared with the project
//   When I open "Configure connection" on "Fetch"
//   Then the edit button on "DHIS2 prod" is disabled with a tooltip naming its owner
//   When "open_credential_modal" is sent with the id of "DHIS2 prod"
//   Then no credential form opens and "credential_modal_closed" is pushed back
// Same as shared-adaptor-credential-config S13.
test('@S13', PASSING_OLD, async ({ page }) => {
  const { id, wf } = givenIntake();
  const secret = 'amara-only-4471';
  const credentialId = givenCredential(id, 'DHIS2 prod', {
    owner: THIRD,
    secret,
  });
  adaptorConfig.jobUses(wf.steps.Fetch, DHIS2);
  const lv = watchLiveView(page);
  await openAs(page, wf, ME, stepOf(wf, 'Fetch'));

  await adaptorConfig.S13(page, lv, adaptorBox(page), {
    id: credentialId,
    owner: THIRD,
    secret,
  });
});

// @S14
// Scenario: An admin creates a keychain credential from a step
//   Given I am an admin on "Malawi HIV"
//   When I open a new credential from "Fetch", click "Advanced", choose keychain and save a keychain "Per facility" with path "$.facility_id"
//   Then the keychain credential exists on the project
//   And "Fetch" has "Per facility" as its keychain credential
// Same as shared-adaptor-credential-config S14.
// Still pending, old: the keychain credential made from the step is selected but not stored on the step (unconfirmed)
test('@S14', PENDING, async ({ page }) => {
  const { id, wf } = givenIntake({ [ME]: 'admin' });
  adaptorConfig.jobUses(wf.steps.Fetch, DHIS2);
  await openAs(page, wf, ME, stepOf(wf, 'Fetch'));

  await adaptorConfig.S14(
    page,
    adaptorBox(page),
    { projectId: id, jobId: wf.steps.Fetch },
    () => saveWorkflow(page)
  );
});

// @S15
// Scenario: People below admin cannot create a keychain credential from a step
//   Given I am an editor on "Malawi HIV"
//   When I submit a keychain credential "Planted" from the step's advanced credential setup
//   Then no keychain credential "Planted" exists
// Shared-adaptor-credential-config S15, run here as an editor.
test('@S15', PASSING_OLD, async ({ page }) => {
  const { id, wf } = givenIntake();
  const lv = watchLiveView(page);
  await openAs(page, wf, ME, stepOf(wf, 'Fetch'));

  await adaptorConfig.S15(page, lv, id);
});

// @S16
// Scenario: Deleting a step removes it with its incoming paths and any cron input pointing at it
//   Given "Load" is a leaf step and the cron input source of a schedule trigger is "Load"
//   When I delete "Load" and confirm "Delete Job"
//   Then "Load" and the path from "Fetch" to "Load" are gone
//   And the schedule's input source reads "Final run state (default)"
test('@S16', PASSING_OLD, async ({ page }) => {
  const { wf } = givenIntake({ [ME]: 'editor' }, { trigger: 'cron' });
  setTrigger(wf.triggerId!, { cron_cursor_job_id: wf.steps.Load });
  await openAs(page, wf, ME, stepOf(wf, 'Load'));

  await deleteStep(page, 'Load');

  await expect(node(page, 'Load')).toHaveCount(0);
  await expect
    .poll(() =>
      draftOf(wf.id)?.edges.filter(e => e.target_job_id === wf.steps.Load)
    )
    .toEqual([]);
  expect(draftTrigger(wf.id)?.cron_cursor_job_id).toBeNull();
  await triggerNode(page).click();
  await expect(shownValue(page, 'Cron Input Source')).toHaveText(
    'Final run state (default)'
  );
});

// @S17
// Scenario Outline: Some steps cannot be deleted
//   When I open <step>
//   Then the delete button is disabled with "<reason>"
//   Examples:
//     | step  | reason                                          |
//     | Fetch | Cannot delete: other jobs depend on this step   |
test('@S17', PASSING_OLD, async ({ page }) => {
  const { wf } = givenIntake();
  await openAs(page, wf, ME, stepOf(wf, 'Fetch'));

  const remove = deleteButton(panel(page, 'Fetch'));
  await expect(remove).toBeDisabled();
  expect(await tooltipOf(page, remove)).toContain(
    'Cannot delete: other jobs depend on this step'
  );
});

// @S18
// Scenario: The first step cannot be deleted
//   Given "Solo" is the only step, reached from the trigger
//   When I open "Solo"
//   Then the delete button is disabled with "You can't delete the first step in a workflow."
test('@S18', PASSING_OLD, async ({ page }) => {
  const { wf } = givenIntake({ [ME]: 'editor' }, { steps: ['Solo'] });
  await openAs(page, wf, ME, stepOf(wf, 'Solo'));

  const remove = deleteButton(panel(page, 'Solo'));
  await expect(remove).toBeDisabled();
  expect(await tooltipOf(page, remove)).toContain(
    "You can't delete the first step in a workflow."
  );
});

// @S19
// Scenario: A step hands off to its code editor and to a manual run
//   When I open "Fetch" and click the code button
//   Then the URL has "panel=editor" and "job=<Fetch id>" (workflow-editor-ide takes over)
//   When I return and click "Run From Here"
//   Then the manual run panel opens for "Fetch" (workflow-editor-manual-run takes over)
test('@S19', PASSING_OLD, async ({ page }) => {
  const { wf } = givenIntake();
  const fetch = wf.steps.Fetch;
  await openAs(page, wf, ME, stepOf(wf, 'Fetch'));

  await codeButton(page).click();
  await expect
    .poll(() => editorQuery(page))
    .toMatchObject({ panel: 'editor', job: fetch });

  await reopen(page, wf, stepOf(wf, 'Fetch'));
  await runRetry.runButton(panel(page, 'Fetch')).click();
  await expect
    .poll(() => editorQuery(page))
    .toMatchObject({ panel: 'run', job: fetch });
});

// ---------------------------------------------------------------------------
// Triggers
// ---------------------------------------------------------------------------

// @S20
// Scenario: A webhook trigger shows the URLs it answers on
//   Given the webhook trigger has custom path "kobo-intake"
//   When I open the trigger
//   Then I see a "Default" URL ending "/i/<trigger id>" and a "Custom" URL ending "/i/<project id>/kobo-intake"
//   And each can be copied
test('@S20', PASSING_OLD, async ({ page }) => {
  const { id, wf } = givenIntake({ [ME]: 'viewer' });
  setTrigger(wf.triggerId!, { custom_path: 'kobo-intake' });
  await page.context().grantPermissions(['clipboard-read', 'clipboard-write']);
  await openAs(page, wf, ME, panelQuery({ trigger: wf.triggerId! }));

  for (const [label, ending] of [
    ['Default', `/i/${wf.triggerId}`],
    ['Custom', `/i/${id}/kobo-intake`],
  ] as const) {
    await expect(webhookUrl(page, label)).toContainText(
      new RegExp(`${ending}\\s*$`)
    );
    await copyUrlButton(page, label).click();
    expect(await clipboard(page)).toMatch(new RegExp(`${ending}$`));
  }
});

// @S21
// Scenario: The webhook panel says how the trigger is protected
//   Given "Kobo basic" is attached to the trigger
//   When I open the trigger and expand "Authentication"
//   Then the header reads "(1 configured)" and lists "Kobo basic (Basic Auth)"
//   Given no method is attached and I am an editor
//   Then I see "No authentication configured." with "Add authentication", which opens the wizard on Configure with Authentication expanded
test('@S21', PASSING_OLD, async ({ page }) => {
  const { id, by, wf } = givenIntake();
  const kobo = addWebhookAuthMethodOnNode(id, 'Kobo basic', by, {
    basic: KOBO,
  });
  attachAuthMethodsOnNode(wf.triggerId!, [kobo], by);
  const open = seedEditorWorkflow(id, by, { name: 'Open intake' });
  await openAs(page, wf, ME, panelQuery({ trigger: wf.triggerId! }));

  await authenticationToggle(page).click();
  await expect(authenticationToggle(page)).toHaveText(/\(1 configured\)/);
  await expect(panel(page, TITLES.webhook)).toContainText(
    /Kobo basic\s*\(Basic Auth\s*\)/
  );

  await reopen(page, open, panelQuery({ trigger: open.triggerId! }));
  await authenticationToggle(page).click();
  await expect(page.getByText('No authentication configured.')).toBeVisible();
  await page.getByRole('button', { name: 'Add authentication' }).click();
  await expect(finishButton(page)).toBeVisible();
  await expect(authPickers(page).first()).toBeVisible();
});

// @S22
// Scenario: Trigger edits are a draft until Finish
//   Given I opened the trigger wizard and "amara@example.org" then disabled the trigger on the canvas
//   When I change the response type and click "Finish"
//   Then only the response type is written to the trigger
//   And the trigger stays disabled
//   When I open the wizard again, change the response type and click "Cancel"
//   Then nothing is written
// Both of us without experimental features, so the header has the switch.
test('@S22', PASSING_OLD, async ({ page, browser }) => {
  withoutExperimental(ME);
  withoutExperimental(THIRD);
  const { wf } = givenIntake(
    { [ME]: 'editor', [THIRD]: 'editor' },
    { enabled: true }
  );
  const amara = await otherSession(browser, THIRD);
  await reopen(amara, wf);
  await openAs(page, wf, ME, panelQuery({ trigger: wf.triggerId! }));
  await openTriggerWizard(page);

  await workflowSwitch(amara).click();
  await expect.poll(() => draftTrigger(wf.id)?.enabled).toBe(false);
  const before = draftTrigger(wf.id)!;

  await chooseResponseType(page, 'On Complete');
  await finishButton(page).click();

  await expect
    .poll(() => draftTrigger(wf.id))
    .toEqual({ ...before, webhook_reply: 'after_completion' });

  await openTriggerWizard(page);
  await chooseResponseType(page, 'Immediately');
  await cancelButton(page).click();

  await expect(editTriggerButton(page)).toBeVisible();
  expect(draftTrigger(wf.id)).toEqual({
    ...before,
    webhook_reply: 'after_completion',
  });
});

// @S23
// Scenario Outline: A custom webhook path is checked before Finish
//   Given another workflow in "Malawi HIV" uses path "kobo"
//   When I add a custom URL and type "<path>"
//   Then I see "<message>"
//   And "Finish" is <finish>
//   Examples:
//     | path                                 | message                                                        | finish   |
//     | kobo                                 | Already used by another workflow in this project.             | disabled |
//     | Kobo Intake                          | Use lowercase letters, numbers, hyphens and underscores only. | disabled |
//     | 0b3c5e1a-3f1d-4c4e-9d55-4c0a7f2e9a11 | A UUID cannot be used as a path.                               | disabled |
//     | kobo-intake                          | (nothing)                                                      | enabled  |
test('@S23', PASSING_OLD, async ({ page }) => {
  const { id, by, wf } = givenIntake();
  const other = seedEditorWorkflow(id, by, { name: 'Kobo' });
  setTrigger(other.triggerId!, { custom_path: 'kobo' });
  await openAs(page, wf, ME, panelQuery({ trigger: wf.triggerId! }));
  await openTriggerWizard(page);
  await addCustomUrl(page);

  const taken = 'Already used by another workflow in this project.';
  const format =
    'Use lowercase letters, numbers, hyphens and underscores only.';
  const uuid = 'A UUID cannot be used as a path.';
  for (const [path, message] of [
    ['kobo', taken],
    ['Kobo Intake', format],
    ['0b3c5e1a-3f1d-4c4e-9d55-4c0a7f2e9a11', uuid],
    ['kobo-intake', null],
  ] as const)
    await test.step(path, async () => {
      await customPathField(page).fill(path);
      if (message) {
        await expect
          .soft(page.getByText(message, { exact: true }))
          .toBeVisible();
        await expect.soft(finishButton(page)).toBeDisabled();
      } else {
        // Enabled once the uniqueness check has answered
        await expect.soft(finishButton(page)).toBeEnabled();
        for (const m of [taken, format, uuid])
          await expect.soft(page.getByText(m, { exact: true })).toHaveCount(0);
      }
    });
});

// @S24
// Scenario: A path the server refused is reported on the trigger
//   Given the last save returned a "custom_path" error for the trigger
//   When I open the trigger
//   Then I see "The custom path was not saved:" followed by the error
//   And the custom URL cannot be copied
test('@S24', PASSING_OLD, async ({ page }) => {
  const { wf } = givenIntake();
  const error = 'has already been taken';
  setTrigger(wf.triggerId!, { custom_path: 'kobo-intake' });
  await openAs(page, wf);
  showSaveErrorOnNode(wf.id, 'triggers', wf.triggerId!, 'custom_path', error);

  await triggerNode(page).click();

  await expect(
    page.getByText(new RegExp(`The custom path was not saved:\\s*${error}`))
  ).toBeVisible();
  await expect(copyUrlButton(page, 'Custom')).toBeDisabled();
  await expect(copyUrlButton(page, 'Default')).toBeEnabled();
});

// @S25
// Scenario: Deleting a custom URL asks first
//   Given the trigger has custom path "kobo-intake"
//   When I click "Delete custom URL" in the wizard
//   Then I see "Delete this webhook URL?" saying the default URL is unaffected
//   When I confirm and click "Finish"
//   Then the trigger has no custom path
test('@S25', PASSING_OLD, async ({ page }) => {
  const { wf } = givenIntake();
  setTrigger(wf.triggerId!, { custom_path: 'kobo-intake' });
  await openAs(page, wf, ME, panelQuery({ trigger: wf.triggerId! }));
  await openTriggerWizard(page);

  await deleteCustomUrl(page);

  const ask = 'Delete this webhook URL?';
  await expect(modalTitle(page, ask)).toBeVisible();
  await expect(modal(page, ask)).toContainText(
    'The default URL is unaffected.'
  );
  expect(draftTrigger(wf.id)?.custom_path).toBe('kobo-intake');

  await modal(page, ask)
    .getByRole('button', { name: 'Delete', exact: true })
    .click();
  await finishButton(page).click();

  await expect.poll(() => draftTrigger(wf.id)?.custom_path).toBeNull();
});

// @S26
// Scenario: Response timing and default status codes
//   When I set "Response Type" to "On Complete" and set success code 200 and error code 422 and click "Finish"
//   Then the trigger replies after completion with those defaults
//   When I set "Response Type" to "Immediately" and click "Finish"
//   Then the response configuration is cleared
test('@S26', PASSING_OLD, async ({ page }) => {
  const { wf } = givenIntake();
  await openAs(page, wf, ME, panelQuery({ trigger: wf.triggerId! }));
  await openTriggerWizard(page);

  await chooseResponseType(page, 'On Complete');
  await expandResponseOptions(page);
  await field(page, 'Success Code').fill('200');
  await field(page, 'Error Code').fill('422');
  await finishButton(page).click();

  await expect
    .poll(() => draftTrigger(wf.id))
    .toMatchObject({
      webhook_reply: 'after_completion',
      webhook_response_config: { success_code: 200, error_code: 422 },
    });

  await openTriggerWizard(page);
  await chooseResponseType(page, 'Immediately');
  await finishButton(page).click();

  await expect
    .poll(() => draftTrigger(wf.id))
    .toMatchObject({
      webhook_reply: 'before_start',
      webhook_response_config: null,
    });
});

// @S27
// Scenario: Attaching auth methods on Finish starts enforcement
//   Given I am an admin and "Kobo basic" exists in the project
//   When I open the trigger wizard, expand "Authentication", select "Kobo basic" and click "Finish"
//   Then "update_trigger_auth_methods" is sent once, on Finish, with "Kobo basic"
//   And I see "Authentication updated"
//   And every collaborator's trigger shows "(1 configured)"
//   And the flow "flow-webhook-auth-method-enforcement" has taken over for requests to the trigger
// The request shows by its effect: nothing attached before Finish, then
// "Kobo basic".
test('@S27', PASSING_OLD, async ({ page, browser }) => {
  const { id, by, wf } = givenIntake({ [ME]: 'admin', [THIRD]: 'editor' });
  addWebhookAuthMethodOnNode(id, 'Kobo basic', by, { basic: KOBO });
  const trigger = panelQuery({ trigger: wf.triggerId! });
  const amara = await otherSession(browser, THIRD);
  await reopen(amara, wf, trigger);
  await openAs(page, wf, ME, trigger);
  await openTriggerWizard(page);

  await authenticationToggle(page).click();
  await chooseAuthMethod(page, 'Kobo basic');
  expect(authMethodsOn(wf.triggerId!)).toEqual([]);
  await finishButton(page).click();

  await expect.poll(() => authMethodsOn(wf.triggerId!)).toEqual(['Kobo basic']);
  await expect(editorToast(page, 'Authentication updated')).toBeVisible();
  for (const p of [page, amara])
    await expect(authenticationToggle(p)).toHaveText(
      /\(1 configured\)/,
      EVENTUALLY
    );
  // Enforcement: a request without credentials is turned away
  expect((await postToWebhook(page, wf.triggerId!)).status()).toBe(401);
});

// @S28
// Scenario: A failed auth change keeps the wizard open and writes nothing
//   Given the auth method request will fail
//   When I select a method, change the response type and click "Finish"
//   Then I see "Failed to update"
//   And the wizard is still open and no trigger field was written
// The request fails because I am made an editor after the wizard opened, so
// the page still offers the change.
test('@S28', PASSING_OLD, async ({ page }) => {
  const { id, by, wf } = givenIntake({ [ME]: 'admin' });
  addWebhookAuthMethodOnNode(id, 'Kobo basic', by, { basic: KOBO });
  await openAs(page, wf, ME, panelQuery({ trigger: wf.triggerId! }));
  const before = draftTrigger(wf.id);
  await openTriggerWizard(page);
  await authenticationToggle(page).click();
  await chooseAuthMethod(page, 'Kobo basic');
  await chooseResponseType(page, 'On Complete');
  changeRoleOnNode(id, ME, 'editor', { quietly: true });

  await finishButton(page).click();

  await expect(editorToast(page, 'Failed to update')).toBeVisible();
  await expect(finishButton(page)).toBeVisible();
  expect(draftTrigger(wf.id)).toEqual(before);
  expect(authMethodsOn(wf.triggerId!)).toEqual([]);
});

// @S29
// Scenario: Auth methods that load late are not wiped by Finish
//   Given "Kobo basic" is attached and the auth methods load after the wizard opens
//   When I change only the response type and click "Finish"
//   Then "Kobo basic" is still attached and no auth request was sent
// As an admin, so a request that was sent would be carried out.
test('@S29', PASSING_OLD, async ({ page }) => {
  const { id, by, wf } = givenIntake({ [ME]: 'admin' });
  const kobo = addWebhookAuthMethodOnNode(id, 'Kobo basic', by, {
    basic: KOBO,
  });
  attachAuthMethodsOnNode(wf.triggerId!, [kobo], by);
  const sock = await watchEditorSocket(page);
  await openAs(page, wf);

  sock.hold();
  await triggerNode(page).click();
  await openTriggerWizard(page);
  sock.release();

  await chooseResponseType(page, 'On Complete');
  await finishButton(page).click();

  await expect
    .poll(() => draftTrigger(wf.id)?.webhook_reply)
    .toBe('after_completion');
  expect(authMethodsOn(wf.triggerId!)).toEqual(['Kobo basic']);
});

// @S30
// Scenario: Creating an auth method from the trigger hands off to the shared form
//   Given I am an admin in the trigger wizard with Authentication expanded
//   When I click "Create a new authentication method"
//   Then the webhook auth method form opens (shared-webhook-auth-method-form S12 owns the rest)
//   When I cancel it
//   Then "close_webhook_auth_modal_complete" is pushed and it can be opened again
test('@S30', PASSING_OLD, async ({ page }) => {
  const { wf } = givenIntake({ [ME]: 'admin' });
  const lv = watchLiveView(page);
  await openAs(page, wf, ME, panelQuery({ trigger: wf.triggerId! }));
  await openTriggerWizard(page);
  await authenticationToggle(page).click();

  await createAuthMethodButton(page).click();
  await expect(authMethodForm(page)).toBeVisible();

  const sent = lv.events();
  await cancelAuthMethodForm(page);
  await expect(authMethodForm(page)).toHaveCount(0);
  await lv.answered(sent + 1);

  await createAuthMethodButton(page).click();
  await expect(authMethodForm(page)).toBeVisible();
});

// @S31
// Scenario: Switching trigger type does not re-enable it or drop its path
//   Given the webhook trigger is disabled and has custom path "kobo-intake"
//   When I click "Change", pick "On a schedule", then "Change" again and pick "On webhook call", and click "Finish"
//   Then the trigger is still disabled and still has path "kobo-intake"
//   When I click "Change" and pick the type it already has
//   Then its configuration is unchanged
// The second half runs on a trigger that replies on completion, so a reset to
// the defaults would show.
test('@S31', PASSING_OLD, async ({ page }) => {
  const { id, by, wf } = givenIntake({ [ME]: 'editor' }, { enabled: false });
  setTrigger(wf.triggerId!, { custom_path: 'kobo-intake' });
  const kobo = seedEditorWorkflow(id, by, { name: 'Kobo' });
  setTrigger(kobo.triggerId!, { webhook_reply: 'after_completion' });
  await openAs(page, wf, ME, panelQuery({ trigger: wf.triggerId! }));

  await editTrigger(page);
  await changeTriggerType(page, TITLES.cron);
  await changeTriggerType(page, TITLES.webhook);
  await toConfigure(page);
  await finishButton(page).click();

  await expect
    .poll(() => draftTrigger(wf.id))
    .toMatchObject({
      type: 'webhook',
      enabled: false,
      custom_path: 'kobo-intake',
    });

  await reopen(page, kobo, panelQuery({ trigger: kobo.triggerId! }));
  const before = draftTrigger(kobo.id);
  await editTrigger(page);
  await changeTriggerType(page, TITLES.webhook);
  await toConfigure(page);
  await finishButton(page).click();

  await expect(editTriggerButton(page)).toBeVisible();
  expect(draftTrigger(kobo.id)).toEqual(before);
});

// @S32
// Scenario: Building a schedule
//   Given the trigger is a schedule
//   When I choose "Every weekday (Mon-Fri)" at hour "09" minute "30"
//   Then the expression is "30 9 * * 1-5" and Finish saves it
//   When I type "every morning" under "Cron Expression"
//   Then I see "Invalid cron expression"
//   And clicking "Finish" shows "Invalid cron expression. Use format: minute hour day month weekday" and keeps the wizard open
test('@S32', PASSING_OLD, async ({ page }) => {
  const { wf } = givenIntake({ [ME]: 'editor' }, { trigger: 'cron' });
  await openAs(page, wf, ME, panelQuery({ trigger: wf.triggerId! }));
  await openTriggerWizard(page);

  await choose(page, 'Frequency', 'Every weekday (Mon-Fri)');
  await choose(page, 'Hour', '09');
  await choose(page, 'Minute', '30');
  // The hour may be written "09"; cron reads both the same
  const weekdays930 = /^30 0?9 \* \* 1-5$/;
  await expect(await cronExpressionField(page)).toHaveValue(weekdays930);
  await finishButton(page).click();
  await expect
    .poll(() => draftTrigger(wf.id)?.cron_expression)
    .toMatch(weekdays930);

  await openTriggerWizard(page);
  await (await cronExpressionField(page)).fill('every morning');
  await expect(
    page.getByText('Invalid cron expression', { exact: true })
  ).toBeVisible();
  await finishButton(page).click();

  await expect(
    page.getByText(
      'Invalid cron expression. Use format: minute hour day month weekday'
    )
  ).toBeVisible();
  await expect(finishButton(page)).toBeVisible();
  expect(draftTrigger(wf.id)?.cron_expression).toMatch(weekdays930);
});

// @S33
// Scenario: A schedule can take its input from a step's last output
//   Given the trigger is a schedule
//   When I set "Cron Input Source" to "Fetch" and click "Finish"
//   Then the schedule panel shows "Fetch" as its input source
test('@S33', PASSING_OLD, async ({ page }) => {
  const { wf } = givenIntake({ [ME]: 'editor' }, { trigger: 'cron' });
  await openAs(page, wf, ME, panelQuery({ trigger: wf.triggerId! }));
  await openTriggerWizard(page);

  await choose(page, 'Cron Input Source', 'Fetch');
  await finishButton(page).click();

  await expect(shownValue(page, 'Cron Input Source')).toHaveText('Fetch');
  expect(draftTrigger(wf.id)?.cron_cursor_job_id).toBe(wf.steps.Fetch);
});

// ---------------------------------------------------------------------------
// Paths
// ---------------------------------------------------------------------------

// @S34
// Scenario: A path's condition decides when the next step runs
//   When I open the path from "Fetch" to "Load"
//   Then "Condition" offers "Always", "On Success", "On Failure" and "On Match"
//   When I open the path from the trigger to "Fetch"
//   Then "Condition" offers only "Always" and "On Match"
//   When I choose "On Match" and leave the expression empty
//   Then I see "can't be blank"
//   When I type "require('fs')"
//   Then a warning says the expression contains potentially unsafe functions
test('@S34', PASSING_OLD, async ({ page }) => {
  const { wf } = givenIntake();
  const offered = async () => [...(await conditionChoices(page))].sort();
  await openAs(
    page,
    wf,
    ME,
    panelQuery({ edge: pathIdOf(wf.id, 'Fetch', 'Load') })
  );
  expect(await offered()).toEqual(
    ['Always', 'On Success', 'On Failure', 'On Match'].sort()
  );

  await reopen(
    page,
    wf,
    panelQuery({ edge: pathIdOf(wf.id, 'trigger', 'Fetch') })
  );
  expect(await offered()).toEqual(['Always', 'On Match']);

  await choose(page, 'Condition', 'On Match');
  const expression = field(page, 'Javascript Expression');
  await expression.focus();
  await expression.blur();
  await expect(page.getByText("can't be blank")).toBeVisible();

  await expression.fill("require('fs')");
  expect(await expressionWarning(page)).toMatch(/potentially unsafe functions/);
});

// @S35
// Scenario: A job-to-job path can be disabled or deleted, a trigger path cannot
//   When I open the path from "Fetch" to "Load" and turn off "Enabled"
//   Then the path is disabled
//   When I click "Delete" and confirm
//   Then the path is gone and the panel closes
//   When I open the path from the trigger to "Fetch"
//   Then there is no footer and I see "This path will be active if its trigger is enabled"
test('@S35', PASSING_OLD, async ({ page }) => {
  const { wf } = givenIntake();
  const jobPath = pathIdOf(wf.id, 'Fetch', 'Load');
  const edge = () => draftOf(wf.id)?.edges.find(e => e.id === jobPath);
  await openAs(page, wf, ME, panelQuery({ edge: jobPath }));

  await flip(panel(page, TITLES.path), 'Enabled');
  await expect(pathEnabled(page)).not.toBeChecked();
  await expect.poll(() => edge()?.enabled).toBe(false);

  await deletePath(page);
  await expect.poll(edge).toBeUndefined();
  await expect(panelHeading(page, TITLES.path)).toHaveCount(0);

  await reopen(
    page,
    wf,
    panelQuery({ edge: pathIdOf(wf.id, 'trigger', 'Fetch') })
  );
  const triggerPath = panel(page, TITLES.path);
  await expect(triggerPath).toContainText(
    'This path will be active if its trigger is enabled'
  );
  await expect(deleteButton(triggerPath)).toHaveCount(0);
  await expect(pathEnabled(page)).toHaveCount(0);
});

// ---------------------------------------------------------------------------
// Workflow settings, code, templates
// ---------------------------------------------------------------------------

// @S36
// Scenario: Workflow concurrency is bounded by the project
//   Given "Malawi HIV" allows 3 concurrent runs
//   When I set "Max Concurrency" to 5 in "Workflow settings"
//   Then I see "exceeds project concurrency limit (3) and has no effect"
//   Given "Malawi HIV" allows 1 concurrent run
//   Then "Max Concurrency" is disabled and a note links to the project setup page
test('@S36', PASSING_OLD, async ({ page }) => {
  const { id, wf } = givenIntake();
  setProjectConcurrency(id, 3);
  await openAs(page, wf, ME, panelQuery({ panel: 'settings' }));

  const max = field(page, 'Max Concurrency');
  await max.fill('5');
  await max.blur();
  await expect(
    page.getByText('exceeds project concurrency limit (3) and has no effect')
  ).toBeVisible();

  setProjectConcurrency(id, 1);
  await page.reload();
  await editorReady(page);
  await expect(field(page, 'Max Concurrency')).toBeDisabled();
  await expect(
    panel(page, TITLES.settings).getByRole('link', { name: 'project setup' })
  ).toHaveAttribute('href', new RegExp(`/projects/${id}/settings`));
});

// @S37
// Scenario: Workflow name and console logging are set from settings
//   When I rename "Intake" to "Intake v2" and turn off "Allow console.log() usage" in "Workflow settings"
//   Then collaborators see the new name and setting without reloading
test('@S37', PASSING_OLD, async ({ page, browser }) => {
  const { wf } = givenIntake({ [ME]: 'editor', [THIRD]: 'editor' });
  const settings = panelQuery({ panel: 'settings' });
  const amara = await otherSession(browser, THIRD);
  await reopen(amara, wf, settings);
  await openAs(page, wf, ME, settings);
  await expect(switchNamed(amara, LOGS)).toBeChecked();

  await renameWorkflow(page, 'Intake v2');
  await flip(page, LOGS);

  await expect(field(amara, 'Workflow Name')).toHaveValue(
    'Intake v2',
    EVENTUALLY
  );
  await expect(switchNamed(amara, LOGS)).not.toBeChecked(EVENTUALLY);
});

// @S38
// Scenario: Resetting discards everyone's unsaved changes after confirmation
//   Given "amara@example.org" and I have unsaved changes to "Intake"
//   When I click "Reset to Latest Snapshot" and confirm "Reset Workflow"
//   Then both of us see "Intake" as last saved
//   Given I am a viewer
//   Then I do not see "Reset Workflow"
//   And a "reset_workflow" request from me is refused
// The refusal shows by its effect: amara's next unsaved change stays.
test('@S38', PASSING_OLD, async ({ page, browser }) => {
  const { id, wf } = givenIntake({ [ME]: 'editor', [THIRD]: 'editor' });
  const sock = await watchEditorSocket(page);
  const amara = await otherSession(browser, THIRD);
  await reopen(amara, wf);
  await openAs(page, wf);
  await renameStep(page, 'Fetch', 'Fetch mine');
  await renameStep(amara, 'Load', 'Load hers');
  await expect
    .poll(() => sharedDocOf(wf.id)?.steps)
    .toEqual(['Fetch mine', 'Load hers']);

  await openSettings(page);
  await resetToLatest(page);

  await expect.poll(() => sharedDocOf(wf.id)?.steps).toEqual(['Fetch', 'Load']);
  for (const p of [page, amara])
    for (const step of ['Fetch', 'Load'])
      await expect(node(p, step)).toBeVisible(EVENTUALLY);

  changeRoleOnNode(id, ME, 'viewer');
  await reopen(page, wf, panelQuery({ panel: 'settings' }));
  await expect(panelHeading(page, TITLES.settings)).toBeVisible();
  await expect(resetButton(page)).toHaveCount(0);

  await renameStep(amara, 'Load', 'Load hers');
  await expect.poll(() => sharedDocOf(wf.id)?.steps).toContain('Load hers');
  const reply = await sock.push('reset_workflow');
  expect(reply.status).toBe('error');
  expect(sharedDocOf(wf.id)?.steps).toContain('Load hers');
});

// @S39
// Scenario: The workflow can be viewed, copied and downloaded as YAML
//   When I click "View your workflow as YAML code" in "Workflow settings"
//   Then I see the workflow as YAML
//   When I click "Download"
//   Then a file "Intake.yaml" is saved
//   Given the workflow is named "ワークフロー"
//   Then the download is named "workflow.yaml"
test('@S39', PASSING_OLD, async ({ page }) => {
  const { wf } = givenIntake();
  await page.context().grantPermissions(['clipboard-read', 'clipboard-write']);
  await openAs(page, wf, ME, panelQuery({ panel: 'settings' }));

  await viewAsYaml(page);
  const yaml = await yamlCode(page).inputValue();
  expect((YAML.parse(yaml) as { name: string }).name).toBe('Intake');
  for (const step of ['Fetch', 'Load']) expect(yaml).toContain(step);

  await copyYamlButton(page).click();
  expect(await clipboard(page)).toBe(yaml);

  expect(await downloadYaml(page)).toBe('Intake.yaml');

  await renameWorkflow(page, 'ワークフロー');
  await viewAsYaml(page);
  expect(await downloadYaml(page)).toBe('workflow.yaml');
});

// @S40
// Scenario: A support user publishes the workflow as a template
//   Given I am a support user and an editor on "Malawi HIV" and "Intake" has no unsaved changes
//   When I open the YAML view, click "Publish Template", enter tags "hiv, intake" and publish
//   Then I see "Workflow published as template"
//   And the template has tags "hiv" and "intake"
//   When I publish again
//   Then the same template is updated and I see "Template updated"
// A support user is instance-wide.
// Still pending, old: no "Template updated" message on the second publish (unconfirmed)
test('@S40', PENDING_SERIAL, async ({ page }) => {
  const { wf } = givenIntake();
  cleanups.push(() => removeTemplatesOf(wf.id));
  cleanups.push(makeSupportUser(ME));
  await openAs(page, wf, ME, panelQuery({ panel: 'code' }));

  await publishTemplate(page, 'hiv, intake');

  await expect(
    editorToast(page, 'Workflow published as template')
  ).toBeVisible();
  await expect
    .poll(() => templatesOf(wf.id).map(t => t.tags))
    .toEqual([['hiv', 'intake']]);
  const [first] = templatesOf(wf.id);

  await expect(panelHeading(page, TITLES.code)).toBeVisible();
  await publishTemplate(page, 'hiv, intake');

  await expect(editorToast(page, 'Template updated')).toBeVisible();
  expect(templatesOf(wf.id).map(t => t.id)).toEqual([first.id]);
});

// @S41
// Scenario: Templates are published only from saved work, and only by support users
//   Given I am a support user and "Intake" has unsaved changes
//   Then "Publish Template" is disabled with "You must save your workflow first before publishing a template."
//   Given I am not a support user
//   Then I do not see "Publish Template"
//   And a "publish_template" request from me is refused with "You don't have permission to publish templates"
// The refusal is checked on a second workflow with nothing unsaved, by its
// effect: no template. A support user is instance-wide.
// Still pending, old: Publish stays enabled while there are unsaved edits; only an older saved version turns it off
test('@S41', PENDING_SERIAL, async ({ page }) => {
  const { id, by, wf } = givenIntake();
  const saved = seedEditorWorkflow(id, by, { name: 'Intake saved' });
  cleanups.push(() => removeTemplatesOf(wf.id));
  cleanups.push(() => removeTemplatesOf(saved.id));
  const notSupport = makeSupportUser(ME);
  cleanups.push(notSupport);
  const sock = await watchEditorSocket(page);
  await openAs(page, wf);
  await renameStep(page, 'Fetch', 'Fetch v2');
  await openSettings(page);
  await viewAsYaml(page);

  await expect(publishButton(page)).toBeDisabled();
  expect(await publishReason(page)).toBe(
    'You must save your workflow first before publishing a template.'
  );

  notSupport();
  await reopen(page, saved, panelQuery({ panel: 'code' }));
  await expect(yamlCode(page)).toBeVisible();
  await expect(publishButton(page)).toHaveCount(0);

  const reply = await sock.push('publish_template', {
    name: 'Planted',
    description: '',
    tags: ['planted'],
    code: await yamlCode(page).inputValue(),
    positions: {},
  });
  expect(reply.status).toBe('error');
  expect(templatesOf(saved.id)).toEqual([]);
});

// ---------------------------------------------------------------------------
// Read-only, keyboard, deletions
// ---------------------------------------------------------------------------

// @S42
// Scenario: Viewers see the panels with editing disabled and a reason
//   Given I am a viewer on "Malawi HIV"
//   When I open "Fetch", the trigger and the path from "Fetch" to "Load"
//   Then the fields are disabled, and "Edit trigger" and the delete buttons are disabled with "You do not have permission to edit this workflow"
//   And the code button on "Fetch" still works
test('@S42', PASSING_OLD, async ({ page }) => {
  const { wf } = givenIntake({ [ME]: 'viewer' });
  await signInAs(page, ME);

  await expectPanelsLocked(page, wf, NO_PERMISSION);

  await reopen(page, wf, stepOf(wf, 'Fetch'));
  await codeButton(page).click();
  await expect
    .poll(() => editorQuery(page))
    .toMatchObject({ panel: 'editor', job: wf.steps.Fetch });
});

// @S43
// Scenario: Escape backs out one layer at a time
//   Given "Configure connection" is open over "Fetch"
//   When I press Escape
//   Then the dialog closes and "Fetch" stays open
//   When I press Escape again, even with focus in a field
//   Then the panel closes
//   Given the YAML view is open
//   When I press Escape
//   Then "Workflow settings" is shown
test('@S43', PASSING_OLD, async ({ page }) => {
  const { wf } = givenIntake();
  await openAs(page, wf, ME, stepOf(wf, 'Fetch'));
  await adaptorConfig.configureButton(adaptorBox(page)).click();
  await expect(modalTitle(page, 'Configure connection')).toBeVisible();

  await page.keyboard.press('Escape');
  await expect(modalTitle(page, 'Configure connection')).toBeHidden();
  await expect(panelHeading(page, 'Fetch')).toBeVisible();

  await field(page, 'Job Name').focus();
  await page.keyboard.press('Escape');
  await expect(panelHeading(page, 'Fetch')).toHaveCount(0);

  await reopen(page, wf, panelQuery({ panel: 'code' }));
  await expect(panelHeading(page, TITLES.code)).toBeVisible();
  await page.keyboard.press('Escape');
  await expect(panelHeading(page, TITLES.settings)).toBeVisible();
});

// @S44
// Scenario: A panel for a node a collaborator deleted closes
//   Given I have "Load" open
//   When "amara@example.org" deletes "Load"
//   Then my inspector closes
test('@S44', PASSING_OLD, async ({ page, browser }) => {
  const { wf } = givenIntake({ [ME]: 'editor', [THIRD]: 'editor' });
  await openAs(page, wf, ME, stepOf(wf, 'Load'));
  await expect(panelHeading(page, 'Load')).toBeVisible();
  const amara = await otherSession(browser, THIRD);
  await reopen(amara, wf, stepOf(wf, 'Load'));

  await deleteStep(amara, 'Load');

  await expect(panelHeading(page, 'Load')).toHaveCount(0, EVENTUALLY);
});

// @S45 @variant:experimental-features
// Scenario: A live workflow's panels are locked until it is back in draft
//   Given "Intake" is live and I am an editor with experimental features on
//   When I open "Fetch" and the trigger
//   Then the fields are disabled, and "Edit trigger" and the delete button are disabled with "This workflow is live. Switch to draft or edit in a sandbox to make changes."
//   And a "reset_workflow" request from me is refused
// The refusal shows by its effect: a colleague without experimental features
// is not locked, and her unsaved change stays.
test('@S45', PASSING_OLD, async ({ page, browser }) => {
  experimental();
  withoutExperimental(THIRD);
  const { by, wf } = givenIntake(
    { [ME]: 'editor', [THIRD]: 'editor' },
    { enabled: false }
  );
  goLiveOnNode(wf.id, by);
  const sock = await watchEditorSocket(page);
  await signInAs(page, ME);

  await expectPanelsLocked(page, wf, LIVE, { path: false });

  const amara = await otherSession(browser, THIRD);
  await reopen(amara, wf);
  await renameStep(amara, 'Load', 'Load hers');
  await expect.poll(() => sharedDocOf(wf.id)?.steps).toContain('Load hers');
  const reply = await sock.push('reset_workflow');
  expect(reply.status).toBe('error');
  expect(sharedDocOf(wf.id)?.steps).toContain('Load hers');
});

// ---------------------------------------------------------------------------
// shared-adaptor-credential-config. The page's own scenarios already run most
// of it on the step inspector's adaptor box: shared S01=S04, S03=S05,
// S04=S06, S05=S07, S06=S08, S07=S09, S08=S10, S09=S11, S11=S12, S13=S13,
// S14=S14, S15=S15. These are the rest.
// ---------------------------------------------------------------------------

test.describe('shared-adaptor-credential-config', () => {
  const name = (id: string) =>
    `shared-adaptor-credential-config@${id} on workflow-editor-inspectors`;

  // "Fetch" points at the project credential of "Kenya TB", which is not in
  // "Malawi HIV"'s list
  test(name('S02'), PASSING_OLD, async ({ page }) => {
    const { wf } = givenIntake();
    const kenya = givenProject({ [OWNER]: 'owner' }, { name: 'Kenya TB' });
    const credentialId = givenCredential(kenya.id, 'Kenya DHIS2');
    adaptorConfig.jobUses(wf.steps.Fetch, DHIS2, {
      projectId: kenya.id,
      credentialId,
    });
    await openAs(page, wf, ME, stepOf(wf, 'Fetch'));

    await adaptorConfig.S02(page, adaptorBox(page));
  });

  // The adaptor catalogue is instance-wide
  test(name('S10'), PASSING_OLD_SERIAL, async ({ page }) => {
    cleanups.push(adaptorConfig.withRetiredAdaptors());
    const { wf } = givenIntake();
    adaptorConfig.jobUses(wf.steps.Fetch, DHIS2);
    await openAs(page, wf, ME, stepOf(wf, 'Fetch'));

    await adaptorConfig.S10(
      page,
      () => openAdaptorPicker(adaptorBox(page)),
      adaptorBox(page)
    );
  });

  test(name('S12'), PASSING_OLD, async ({ page }) => {
    const { wf } = givenIntake({ [ME]: 'viewer' });
    cleanups.push(() => removeCredentialsNamed(ME, ['Viewer raw']));
    const lv = watchLiveView(page);
    await openAs(page, wf, ME, stepOf(wf, 'Fetch'));

    await adaptorConfig.S12(page, lv, ME);
  });

  test(name('S16'), PENDING, () => {
    test.skip(
      true,
      "needs another project's credential written into the shared document"
    );
  });

  test(name('S17'), PASSING_OLD, async ({ page }) => {
    await givenFetchOnDhis2(page);
    await adaptorConfig.S17(page, adaptorBox(page));
  });

  test(name('S18'), PASSING_OLD, async ({ page }) => {
    await givenFetchOnDhis2(page, 'viewer');
    await adaptorConfig.S18(page, adaptorBox(page));
  });
});

// ---------------------------------------------------------------------------
// shared-run-retry-controls: the step inspector's "Run From Here" (S10). The
// header's control runs on workflow-editor-canvas; the run panel's and the
// IDE's on workflow-editor-manual-run and workflow-editor-ide.
// ---------------------------------------------------------------------------

test.describe('shared-run-retry-controls', () => {
  // Examples, one step each. '"Intake" is new and not yet created' is left
  // out: on /w/new the inspector does not open.
  test(
    'shared-run-retry-controls@S10 on workflow-editor-inspectors',
    PASSING_OLD,
    async ({ page }) => {
      const why = runRetry.given.S10;
      const h = givenIntake({ [ME]: 'viewer' });
      const fetch = h.wf.steps.Fetch;
      const surface = () => panel(page, 'Fetch');
      const sock = await watchEditorSocket(page);
      await openAs(page, h.wf, ME, stepOf(h.wf, 'Fetch'));

      await test.step('I am a viewer', () =>
        runRetry.S10(page, surface(), why.viewer));

      changeRoleOnNode(h.id, ME, 'editor', { quietly: true });
      const pinned = storedWorkflow(h.wf.id).lock_version;
      renameStepOnNode(h.wf.id, 'Load', 'Load v2', h.by);
      await test.step('I am viewing a pinned version', async () => {
        await reopen(page, h.wf, panelQuery({ v: pinned, job: fetch }));
        await runRetry.S10(page, surface(), why.pinned);
      });

      await test.step('the editor is disconnected', async () => {
        await reopen(page, h.wf, stepOf(h.wf, 'Fetch'));
        sock.drop();
        await runRetry.S10(page, surface(), why.disconnected);
        sock.reconnect();
      });
    }
  );

  // Still pending, old: an open editor leaves for the workflow list when its workflow is deleted, so no reason is shown
  test(
    'shared-run-retry-controls@S10 on workflow-editor-inspectors, deleted',
    PENDING,
    async ({ page }) => {
      const h = givenIntake({ [ME]: 'editor' });
      await openAs(page, h.wf, ME, stepOf(h.wf, 'Fetch'));
      deleteWorkflowOnNode(h.wf.id, OWNER);
      await runRetry.S10(
        page,
        panel(page, 'Fetch'),
        runRetry.given.S10.deleted
      );
    }
  );
});

// ---------------------------------------------------------------------------
// shared-webhook-auth-method-form: this page opens its create form from the
// trigger (S12; page S30 covers cancelling it). S01 to S11 are the same
// LiveView form and run on project-settings-webhook-security.
// ---------------------------------------------------------------------------

test.describe('shared-webhook-auth-method-form', () => {
  // @S12
  // Scenario: Creating a method from the workflow editor hands off to every open editor
  //   Given I am an owner editing workflow "Intake" on project "Malawi HIV"
  //   And I have opened the auth method form from the trigger's "Create a new authentication method" link
  //   When I create basic auth method "Kobo basic"
  //   Then the auth method form closes
  //   And "webhook_auth_methods_updated" is broadcast on "workflow:collaborate:<workflow_id>" including "Kobo basic"
  test(
    'shared-webhook-auth-method-form@S12 on workflow-editor-inspectors',
    PASSING_OLD,
    async ({ page }) => {
      const { wf } = givenIntake({ [ME]: 'owner' });
      const sock = await watchEditorSocket(page);
      await openAs(page, wf, ME, panelQuery({ trigger: wf.triggerId! }));
      await openTriggerWizard(page);
      await authenticationToggle(page).click();
      await createAuthMethodButton(page).click();

      await chooseAuthType(page, 'Basic HTTP Authentication');
      await field(page, 'Auth method name').fill('Kobo basic');
      await field(page, 'Username').fill(KOBO.username);
      await field(page, 'Password').fill(KOBO.password);
      await submit(page.getByRole('dialog'), 'Create auth method');

      await expect(field(page, 'Auth method name')).toBeHidden();
      await expect
        .poll(() => JSON.stringify(sock.pushed('webhook_auth_methods_updated')))
        .toContain('Kobo basic');
      // Offered on the trigger without reloading
      await chooseAuthMethod(page, 'Kobo basic');
    }
  );
});

// shared-workflow-yaml-format is about importing a file; it runs where files
// are imported (workflow-editor-new, workflow-editor-ai-assistant). This page
// only shows and downloads the YAML (S39).
//
// shared-authenticated-session, shared-project-scope,
// shared-usage-limits-banner, shared-editor-session and shared-flash-messages
// belong to the route /projects/:id/w/:id, and run on it in
// workflow-editor-canvas.spec.ts.
