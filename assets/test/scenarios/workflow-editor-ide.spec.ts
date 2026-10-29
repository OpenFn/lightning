// Scenarios from annotations/views/workflow-editor-ide.md, and the shared
// scenarios the full-screen code editor (the IDE) hosts.
//
// Who's who: "I" (and "Joe") is editor@openfn.org; each test gives me the
// role its Given names. owner@openfn.org owns every project and saves its
// workflows through Lightning; super@openfn.org stands in for "Amara", the
// collaborator a test needs. Every project ("Malawi HIV" and its sandboxes)
// is seeded by the test and removed again afterwards, with its workflows.
// "Intake" is a webhook trigger leading to "Fetch", then "Send to DHIS2", unless
// a test says otherwise.
//
// The editor is not being ported: these record what today's IDE does,
// through pages/workflow-editor-ide.ts, so a rebuild that keeps the Value
// passes.
//
// Stand-ins: the metadata service is answered by the test (S11), since no
// external system is reachable; a step with a blank name is the change the
// server will not save (run-retry S08).
//
// shared-authenticated-session, shared-project-scope,
// shared-usage-limits-banner, shared-editor-session and shared-flash-messages
// belong to the route /projects/:id/w/:id and run on it once, in
// workflow-editor-canvas.spec.ts. shared-log-viewer's own behaviour runs on
// run-show; the IDE only hosts it.
import { expect, test, type Page } from '@playwright/test';

import {
  editorQuery,
  editorToast,
  header,
  panelHeading,
  saveButton,
  watchEditorSocket,
} from './pages/workflow-editor';
import {
  FROM_STAND_IN,
  addStepOnNode,
  adaptorBox,
  blankStepName,
  changeAdaptorButton,
  changeAdaptorTo,
  closeDocsButton,
  closeIdeButton,
  closeRunChip,
  codeFocused,
  codeLines,
  codeText,
  cursorLine,
  cursorToEnd,
  cursorToEndOfLine,
  docsBelowCode,
  docsLink,
  docsOperations,
  docsPanel,
  docsTab,
  docsTitle,
  firstExample,
  focusCode,
  headerToggle,
  historyButton,
  historyWorkOrder,
  holdAdaptorDownloads,
  ide,
  ideHeader,
  ideReady,
  inputChoice,
  jobSelector,
  loadingTypes,
  markedLogLines,
  metadataEntity,
  metadataGeneratedAt,
  openIde,
  openJobSelector,
  openRunPanel,
  orientationButton,
  pickHistoryRun,
  pickJob,
  remoteCodeCursors,
  replaceCode,
  runChip,
  runTab,
  sandboxBanner,
  savedBodyOf,
  setJobBody,
  signatureHelp,
  standInMetadata,
  suggestions,
  tabShowing,
  toggledOn,
  typeCode,
  versionWarning,
} from './pages/workflow-editor-ide';
import { codeButton } from './pages/workflow-editor-inspectors';
import { connectRunWorkflow } from './pages/workflow-editor-manual-run';
import * as adaptorConfig from './shared/adaptor-credential-config';
import * as runRetry from './shared/run-retry-controls';
import {
  changeRoleOnNode,
  deleteWorkflowOnNode,
  exec,
  expandWorkOrder,
  goLiveOnNode,
  inspectStepLink,
  keepAccount,
  modalTitle,
  nameOf,
  open,
  openHistory,
  otherSession,
  removeCredentialsNamed,
  removeWorkflowData,
  renameStepOnNode,
  seedCredential,
  seedEditorWorkflow,
  seedKeychain,
  seedRun,
  seedWorkspace,
  setPreferences,
  signInAs,
  sql,
  storedAdaptor,
  storedWorkflow,
  type EditorWorkflow,
  type EditorWorkflowSeed,
  type RunSeed,
  type WorkspaceSeed,
} from './steps';

const ME = 'editor@openfn.org';
const OWNER = 'owner@openfn.org';
const THIRD = 'super@openfn.org';

type Role = 'owner' | 'admin' | 'editor' | 'viewer';

const PENDING = { tag: '@pending' };
const PASSING_OLD = { tag: '@passing-old' };
const PASSING_OLD_SERIAL = { tag: ['@passing-old', '@serial'] };

// A page that has to react to something done elsewhere gets this long
const EVENTUALLY = { timeout: 15000 };

const SEND = 'Send to DHIS2';
const DHIS2 = '@openfn/language-dhis2@latest';

let cleanups: (() => void)[] = [];
test.beforeEach(() => {
  // Some tests change my preferences
  cleanups = [keepAccount(ME)];
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
  return { id, w, by: OWNER };
}

// Given project "Malawi HIV" with these members has workflow "Intake" (or
// <seed>'s), saved by its owner
function givenIntake(
  members: Record<string, Role> = { [ME]: 'editor' },
  seed: EditorWorkflowSeed = {}
) {
  const p = givenProject(members);
  const wf = seedEditorWorkflow(p.id, p.by, {
    steps: ['Fetch', SEND],
    ...seed,
  });
  return { ...p, wf };
}

// Given project "Malawi HIV" with these members has a run of a workflow,
// seeded through Lightning (steps "Fetch" and "Load" unless <seed> says)
function givenRun(
  members: Record<string, Role> = { [ME]: 'editor' },
  seed: RunSeed = {}
) {
  const p = givenProject(members);
  const run = seedRun(
    p.id,
    {
      workflow: 'Intake',
      steps: [{ name: 'Fetch' }, { name: 'Load' }],
      ...seed,
    },
    p.by
  );
  cleanups.unshift(run.removeCredentials);
  return { ...p, run };
}

// The id of job <name> in workflow <workflowId>
const jobIdOf = (workflowId: string, name: string) =>
  sql<{ id: string }>(
    `select id from jobs where workflow_id = '${workflowId}' and name = $n$${name}$n$`
  )[0].id;

// When I sign in as <email> and open the IDE on step <step> of <wf>
async function openAs(
  page: Page,
  wf: EditorWorkflow,
  step: string,
  {
    email = ME,
    extra = {},
  }: { email?: string; extra?: Record<string, string> } = {}
) {
  await signInAs(page, email);
  await openIde(page, wf.projectId, wf.id, wf.steps[step], extra);
}

// When I open the IDE on step <step> of <wf> again, already signed in
const reopen = (
  page: Page,
  wf: EditorWorkflow,
  step: string,
  extra: Record<string, string | number> = {}
) => openIde(page, wf.projectId, wf.id, wf.steps[step], extra);

// Given "<owner>" owns DHIS2 credential <name>, shared with project
// <projectId> — removed after the test
function givenCredential(projectId: string, name: string) {
  const c = seedCredential(OWNER, {
    name,
    schema: 'dhis2',
    bodies: {
      main: {
        username: 'admin',
        password: 'district',
        hostUrl: 'https://play.dhis2.example.org',
      },
    },
    projects: [projectId],
  });
  cleanups.push(c.remove);
  return c.id;
}

// Given step <step> of a new "Intake" uses DHIS2 with credential "DHIS2
// prod", and I have the IDE open on it
async function givenStepOnDhis2(page: Page, role: Role = 'editor') {
  const h = givenIntake({ [ME]: role });
  const credentialId = givenCredential(h.id, 'DHIS2 prod');
  adaptorConfig.jobUses(h.wf.steps.Fetch, DHIS2, {
    projectId: h.id,
    credentialId,
  });
  await openAs(page, h.wf, 'Fetch');
  return h;
}

// When I save the workflow
async function saveWorkflow(page: Page) {
  await saveButton(page).click();
  await expect(editorToast(page, 'Workflow saved')).toBeVisible();
}

// Whitespace-insensitive, since the editor wraps long lines
const flat = (s: string) => s.replace(/\s+/g, ' ').trim();

// ---------------------------------------------------------------------------
// Open and move around
// ---------------------------------------------------------------------------

// @S01
// Scenario: Opening a step's code from the canvas
//   Given I am an editor on workflow "Intake" and step "Send to DHIS2" is selected
//   When I click the "Code" button in the step's inspector
//   Then the URL has panel "editor" and job "<Send to DHIS2 id>"
//   And the IDE shows "Send to DHIS2" in the job selector and that step's code
//   When I return to the canvas and press Ctrl+E with the step selected
//   Then the IDE opens on "Send to DHIS2" again
test('@S01', PASSING_OLD, async ({ page }) => {
  const { wf } = givenIntake();
  setJobBody(wf.steps[SEND], '// sends to DHIS2\nfn(s => s);');
  await signInAs(page, ME);
  await open(
    page,
    `/projects/${wf.projectId}/w/${wf.id}?job=${wf.steps[SEND]}`
  );
  await expect(panelHeading(page, SEND)).toBeVisible(EVENTUALLY);

  await codeButton(page).click();

  await ideReady(page);
  await expect
    .poll(() => editorQuery(page))
    .toMatchObject({ panel: 'editor', job: wf.steps[SEND] });
  await expect(jobSelector(page)).toHaveText(new RegExp(SEND));
  await expect.poll(() => codeText(page)).toContain('// sends to DHIS2');

  await closeIdeButton(page).click();
  await expect(panelHeading(page, SEND)).toBeVisible();
  await page.keyboard.press('ControlOrMeta+e');

  await ideReady(page);
  await expect(jobSelector(page)).toHaveText(new RegExp(SEND));
  expect(editorQuery(page)).toMatchObject({ panel: 'editor' });
});

// @S02
// Scenario: Leaving the IDE returns to the same step on the canvas, and Escape in the code does not
//   Given the IDE is open on "Send to DHIS2" with the cursor in the code
//   When I press Escape
//   Then the code editor loses focus and the IDE stays open
//   When I press Escape again
//   Then the IDE closes and the canvas shows "Send to DHIS2" selected in its inspector
//   And clicking "Close IDE" from a reopened IDE does the same
test('@S02', PASSING_OLD, async ({ page }) => {
  const { wf } = givenIntake();
  await openAs(page, wf, SEND);
  const backOnCanvas = async () => {
    await expect(closeIdeButton(page)).toHaveCount(0);
    await expect(panelHeading(page, SEND)).toBeVisible();
    const query = editorQuery(page);
    expect(query.job).toBe(wf.steps[SEND]);
    expect(query.panel).toBeUndefined();
  };
  await focusCode(page);
  expect(await codeFocused(page)).toBe(true);

  await page.keyboard.press('Escape');
  await expect.poll(() => codeFocused(page)).toBe(false);
  await expect(closeIdeButton(page)).toBeVisible();

  await page.keyboard.press('Escape');
  await backOnCanvas();

  await reopen(page, wf, SEND);
  await closeIdeButton(page).click();
  await backOnCanvas();
});

// @S03
// Scenario: Escape does not close the IDE while a modal is open over it
//   Given the IDE is open and the adaptor configuration modal is open
//   When I press Escape
//   Then the IDE is still open
test('@S03', PASSING_OLD, async ({ page }) => {
  const { wf } = givenIntake();
  adaptorConfig.jobUses(wf.steps[SEND], DHIS2);
  await openAs(page, wf, SEND);
  await adaptorConfig.configureButton(adaptorBox(page)).click();
  await expect(modalTitle(page, 'Configure connection')).toBeVisible();

  await page.keyboard.press('Escape');

  await page.waitForTimeout(500);
  await expect(closeIdeButton(page)).toBeVisible();
  expect(editorQuery(page).panel).toBe('editor');
});

// @S07
// Scenario: A job that isn't in the opened version is explained, not shown blank
//   Given job "New step" was added after version 3
//   When I open the IDE on job "New step" on version 3
//   Then I see "The job you're trying to view didn't exist in this version of the workflow."
//   And I see "You can change versions or select another job."
//   And the job selector still lists the jobs of version 3
test('@S07', PASSING_OLD, async ({ page }) => {
  const { wf } = givenIntake();
  const pinned = storedWorkflow(wf.id).lock_version;
  const newStep = addStepOnNode(wf.id, 'New step', OWNER);
  await signInAs(page, ME);

  await openIde(page, wf.projectId, wf.id, newStep, { v: pinned });

  await expect(
    ide(page).getByText(
      "The job you're trying to view didn't exist in this version of the workflow."
    )
  ).toBeVisible();
  await expect(
    ide(page).getByText('You can change versions or select another job.')
  ).toBeVisible();
  const listed = (await openJobSelector(page)).map(j => j.name);
  expect(listed).toEqual(expect.arrayContaining(['Fetch', SEND]));
  expect(listed).not.toContain('New step');
});

// @S08
// Scenario: Switching jobs from the job selector, in workflow order
//   Given workflow "Intake" runs "Fetch", then "Transform", then "Load"
//   And the IDE is open on "Load"
//   When I open the job selector
//   Then it lists "Fetch", "Transform", "Load" in that order with "Load" marked
//   When I pick "Transform"
//   Then the URL job becomes "<Transform id>" and the IDE shows "Transform"'s code
// Seeded in another order, so the list's order comes from the paths.
test('@S08', PASSING_OLD, async ({ page }) => {
  const { wf } = givenIntake(
    { [ME]: 'editor' },
    {
      steps: ['Load', 'Fetch', 'Transform'],
      paths: [
        ['trigger', 'Fetch'],
        ['Fetch', 'Transform'],
        ['Transform', 'Load'],
      ],
    }
  );
  setJobBody(wf.steps.Transform, '// transforms the patients');
  await openAs(page, wf, 'Load');

  expect(await openJobSelector(page)).toEqual([
    { name: 'Fetch', marked: false },
    { name: 'Transform', marked: false },
    { name: 'Load', marked: true },
  ]);
  await pickJob(page, 'Transform');

  await expect.poll(() => editorQuery(page).job).toBe(wf.steps.Transform);
  await expect
    .poll(() => codeText(page))
    .toContain('// transforms the patients');
});

// @S09
// Scenario: With a run loaded, switching jobs follows the run's step for that job
//   Given the IDE is following run "R" which executed "Fetch" and "Transform"
//   When I pick "Transform" in the job selector
//   Then the URL step becomes "R"'s step for "Transform"
//   And the run viewer selects that step
// The run viewer shows its selected step by marking that step's log lines.
test('@S09', PASSING_OLD, async ({ page }) => {
  const { id, run } = givenRun(
    { [ME]: 'editor' },
    {
      steps: [{ name: 'Fetch' }, { name: 'Transform' }],
      jobs: ['Load'],
      logs: [
        { message: 'fetching patients', step: 'Fetch' },
        { message: 'transforming patients', step: 'Transform' },
      ],
    }
  );
  await signInAs(page, ME);
  await openIde(page, id, run.workflowId, jobIdOf(run.workflowId, 'Fetch'), {
    run: run.runId,
  });
  await expect(runChip(page, run.runId)).toBeVisible(EVENTUALLY);

  await pickJob(page, 'Transform');

  await expect.poll(() => editorQuery(page).step).toBe(run.steps.Transform);
  await expect
    .poll(() => markedLogLines(page), EVENTUALLY)
    .toEqual(
      expect.arrayContaining([expect.stringContaining('transforming patients')])
    );
});

// @S21 @variant:sandbox
// Scenario: The IDE says when it is in a sandbox
//   Given I am in sandbox "staging-fix" of project "Malawi HIV"
//   When I open the IDE
//   Then I see "You are currently working in the sandbox staging-fix" above the IDE header
test('@S21', PASSING_OLD, async ({ page }) => {
  const { w } = givenProject(
    { [ME]: 'editor' },
    { sandboxes: [{ name: 'staging-fix' }] }
  );
  const sandboxId = w.id('staging-fix');
  cleanups.push(() => removeWorkflowData(sandboxId));
  const wf = seedEditorWorkflow(sandboxId, OWNER, { steps: [SEND] });

  await openAs(page, wf, SEND);

  await expect(sandboxBanner(page)).toHaveText(
    /You are currently working in the sandbox\s+staging-fix/
  );
  const [banner, bar] = [
    await sandboxBanner(page).boundingBox(),
    await ideHeader(page).boundingBox(),
  ];
  expect(banner!.y + banner!.height).toBeLessThanOrEqual(bar!.y + 1);
});

// ---------------------------------------------------------------------------
// Write code together
// ---------------------------------------------------------------------------

// @S04
// Scenario: Two editors type in the same job and see each other
//   Given "Amara" and "Joe" are editors with the IDE open on "Send to DHIS2"
//   When "Amara" types "fn(state => state);" on line 3
//   Then "Joe" eventually sees "fn(state => state);" on line 3 without reloading
//   And "Joe" sees a cursor labelled "Amara" in "Amara"'s colour at that position
// Amara is super@openfn.org, Joe is me. The cursor is checked by its label
// and line; its colour is how it is drawn, not what it protects.
test('@S04', PASSING_OLD, async ({ page, browser }) => {
  const { wf } = givenIntake({ [ME]: 'editor', [THIRD]: 'editor' });
  setJobBody(wf.steps[SEND], '// sends to DHIS2\nfn(s => s);\n');
  await openAs(page, wf, SEND);
  const amara = await otherSession(browser, THIRD);
  await reopen(amara, wf, SEND);

  await cursorToEnd(amara);
  await typeCode(amara, 'fn(state => state);');

  await expect
    .poll(async () => (await codeLines(page))[2], EVENTUALLY)
    .toBe('fn(state => state);');
  await expect
    .poll(() => remoteCodeCursors(page), EVENTUALLY)
    .toContainEqual({ name: nameOf(THIRD).full, line: 3 });
});

// @S05
// Scenario: Code typed in the IDE is saved with the workflow
//   Given I am an editor with the IDE open on "Send to DHIS2"
//   When I replace the code with "get('/api/me');"
//   And I save the workflow
//   Then job "Send to DHIS2" has body "get('/api/me');" after reload
test('@S05', PASSING_OLD, async ({ page }) => {
  const { wf } = givenIntake();
  await openAs(page, wf, SEND);

  await replaceCode(page, "get('/api/me');");
  await saveWorkflow(page);

  await expect.poll(() => savedBodyOf(wf.steps[SEND])).toBe("get('/api/me');");
  await reopen(page, wf, SEND);
  await expect.poll(() => codeText(page)).toBe("get('/api/me');");
});

// @S06
// Scenario Outline: The IDE is read-only for <who>
//   Given <who>
//   When I open the IDE on "Send to DHIS2"
//   Then I can read the code but typing does not change it
//   And the adaptor shows without "Change adaptor" or "Edit" controls
//   And clicking "ADD" on a docs example does not change the code
//   And "Docs", "Metadata" and "History" are still available
//   Examples:
//     | who                                                                  |
//     | I am a viewer on the project                                         |
//     | I am an editor viewing version 3 from the version picker             |
//     | I am an editor who followed a run link to the version that run used  |
// One step per example; soft, so every example is checked.
test('@S06', PASSING_OLD, async ({ page }) => {
  const h = givenIntake({ [ME]: 'viewer' });
  setJobBody(h.wf.steps[SEND], '// sends to DHIS2');
  const run = seedRun(
    h.id,
    { workflow: 'Intake run', steps: [{ name: SEND }] },
    h.by
  );
  cleanups.unshift(run.removeCredentials);
  await signInAs(page, ME);

  const expectReadOnly = async (who: string) => {
    await expect.poll(() => codeText(page)).not.toBe('');
    const before = await codeText(page);
    await focusCode(page);
    await typeCode(page, 'typed();');
    await page.waitForTimeout(500);
    expect.soft(await codeText(page), who).toBe(before);

    const box = adaptorBox(page);
    await expect.soft(changeAdaptorButton(box), who).toHaveCount(0);
    await expect.soft(adaptorConfig.configureButton(box), who).toHaveCount(0);

    const example = await firstExample(page);
    await example.add.click();
    await page.waitForTimeout(500);
    expect.soft(await codeText(page), who).toBe(before);

    for (const control of [
      headerToggle(page, 'Docs'),
      headerToggle(page, 'Metadata'),
      historyButton(page),
    ])
      await expect.soft(control, who).toBeEnabled();
  };

  await test.step('I am a viewer on the project', async () => {
    await reopen(page, h.wf, SEND);
    await expectReadOnly('viewer');
  });

  changeRoleOnNode(h.id, ME, 'editor', { quietly: true });
  const pinned = storedWorkflow(h.wf.id).lock_version;
  renameStepOnNode(h.wf.id, 'Fetch', 'Fetch v2', h.by);
  await test.step('I am an editor viewing an older version', async () => {
    await reopen(page, h.wf, SEND, { v: pinned });
    await expectReadOnly('older version');
  });

  await test.step('I am an editor who followed a run link', async () => {
    await openIde(page, h.id, run.workflowId, jobIdOf(run.workflowId, SEND), {
      as_run: run.runId,
    });
    await expectReadOnly('as a past run');
  });
});

// @S16
// Scenario: Connecting a credential from the IDE assigns it to the job
//   Given I am an editor and job "Send to DHIS2" has no credential
//   When I click "Connect" next to the adaptor in the IDE header
//   Then the adaptor configuration modal opens
//   When I choose to create a new credential
//   Then the credential modal opens over the IDE
//   And for an OAuth credential the flow "flow-oauth-credential-authorize" starts from that modal
//   When I save the new credential
//   Then "Send to DHIS2" uses the new credential and the adaptor configuration modal is shown again
// Same as shared-adaptor-credential-config S01 ("Connect") and S11, on the
// IDE's adaptor box. The OAuth flow is its own.
test('@S16', PASSING_OLD, async ({ page }) => {
  const { id, wf } = givenIntake();
  cleanups.push(() => removeCredentialsNamed(ME, ['DHIS2 test']));
  adaptorConfig.jobUses(wf.steps[SEND], DHIS2);
  await openAs(page, wf, SEND);

  await adaptorConfig.S01(page, adaptorBox(page), 'Connect');
  await adaptorConfig.S11(
    page,
    adaptorBox(page),
    { projectId: id, jobId: wf.steps[SEND], projectName: 'Malawi HIV' },
    () => saveWorkflow(page)
  );
  await expect(closeIdeButton(page)).toBeVisible();
});

// ---------------------------------------------------------------------------
// Get help while writing
// ---------------------------------------------------------------------------

// @S10
// Scenario: Adaptor docs for the job's adaptor version, with examples editors can add
//   Given job "Send to DHIS2" uses "@openfn/language-dhis2@latest" and latest is "5.0.1"
//   When I open the IDE on it
//   Then the docs panel shows "@openfn/language-dhis2 (5.0.1)" with its operations sorted by name
//   And external links to docs.openfn.org and the adaptor source
//   When I am an editor and click "ADD" on an example with my cursor on line 4
//   Then the example is inserted below line 4 and the cursor moves past it
// "latest" is whatever the instance's adaptor catalogue says it is.
// Still pending, old: "ADD" puts the example at the end of the code, as its title says, not at my cursor (unconfirmed: clicking it may lose the cursor)
test('@S10', PENDING, async ({ page }) => {
  const { wf } = givenIntake();
  adaptorConfig.jobUses(wf.steps[SEND], DHIS2);
  const code = ['// one', '// two', '// three', '// four', '// five'];
  setJobBody(wf.steps[SEND], code.join('\n'));
  const latest = storedAdaptor('@openfn/language-dhis2')!.latest_version;
  await openAs(page, wf, SEND);

  await expect(docsTitle(page)).toContainText(
    `@openfn/language-dhis2 (${latest})`,
    EVENTUALLY
  );
  const operations = await docsOperations(page);
  expect(operations.length).toBeGreaterThan(1);
  expect(operations).toEqual([...operations].sort());
  await expect(docsLink(page, 'docs.openfn.org')).toBeVisible();
  await expect(docsLink(page, 'github.com/OpenFn/adaptors')).toBeVisible();

  await cursorToEndOfLine(page, 4);
  const example = await firstExample(page);
  await example.add.click();

  const expected = [...code.slice(0, 4), example.code, '', ...code.slice(4)];
  await expect
    .poll(async () => flat(await codeText(page)))
    .toBe(flat(expected.join('\n')));
  expect(await cursorLine(page)).toBeGreaterThan(
    4 + example.code.split('\n').length
  );
});

// @S11
// Scenario: Metadata from the job's credential, browsable and suggested while typing
//   Given job "Send to DHIS2" is saved with a project credential for a DHIS2 instance
//   When I open the "Metadata" tab in the IDE
//   Then I see "Loading metadata..." and then the datasource's entities with the time they were generated
//   When I am an editor and press Ctrl+Space inside a string in the code
//   Then suggestions from that metadata appear first
// Stand-in: no DHIS2 instance is reachable, so the page's metadata request is
// answered by the test, as the metadata service would answer it.
// Still pending, old: Ctrl+Space in the code shows "No suggestions." on the e2e instance, even after the types load (unconfirmed: may be the test browser)
test('@S11', PENDING, async ({ page }) => {
  const { id, wf } = givenIntake();
  const credentialId = givenCredential(id, 'DHIS2 prod');
  adaptorConfig.jobUses(wf.steps[SEND], DHIS2, { projectId: id, credentialId });
  const metadata = await standInMetadata(page);
  await openAs(page, wf, SEND);
  await expect.poll(() => metadata.asked()).toBeGreaterThan(0);

  await headerToggle(page, 'Metadata').click();
  await expect(docsPanel(page).getByText('Loading metadata...')).toBeVisible();
  metadata.answer();

  await expect(metadataEntity(page, 'orgUnits')).toBeVisible();
  await expect(metadataGeneratedAt(page)).toBeVisible();
  await metadataEntity(page, 'orgUnits').click();
  await expect(docsPanel(page).getByText('Ngelehun CHC')).toBeVisible();

  await expect(loadingTypes(page)).toHaveCount(0, EVENTUALLY);
  await replaceCode(page, "create('', {});");
  await page.keyboard.press('Home');
  for (let i = 0; i < "create('".length; i++)
    await page.keyboard.press('ArrowRight');
  await page.keyboard.press('Control+Space');

  await expect(suggestions(page).first()).toBeVisible();
  await expect(suggestions(page).first()).toHaveText(FROM_STAND_IN);
});

// @S12
// Scenario: Code suggestions for the job's adaptor
//   Given job "Send to DHIS2" uses "@openfn/language-dhis2@5.0.1"
//   When I open the IDE on it
//   Then I see "Loading types" until the adaptor's type definitions load
//   And typing "create(" suggests the dhis2 operation's signature
//   When I change the job's adaptor to "@openfn/language-http@6.0.0"
//   Then suggestions switch to the http adaptor
// The adaptors' latest versions; the downloads are held so "Loading types"
// can be seen.
// Still pending, old: the code editor offers no suggestions or signature help on the e2e instance, even after the types load (unconfirmed: may be the test browser)
test('@S12', PENDING, async ({ page }) => {
  const { wf } = givenIntake();
  adaptorConfig.jobUses(wf.steps[SEND], DHIS2);
  const release = await holdAdaptorDownloads(page);
  await openAs(page, wf, SEND);

  await expect(loadingTypes(page)).toBeVisible();
  release();
  await expect(loadingTypes(page)).toHaveCount(0, EVENTUALLY);

  const hintFor = async (call: string) => {
    await replaceCode(page, call);
    await page.keyboard.press('ControlOrMeta+Shift+Space');
    await expect(signatureHelp(page)).toBeVisible();
    return signatureHelp(page).innerText();
  };
  expect(await hintFor('create(')).toContain('resourceType');

  await changeAdaptorTo(page, 'http');
  await expect(loadingTypes(page)).toHaveCount(0, EVENTUALLY);

  expect(await hintFor('request(')).toContain('method');
});

// @S13
// Scenario: The docs panel can be closed, reopened from the header and turned
//   Given the IDE is open with the docs panel showing
//   When I click "Close docs panel"
//   Then the docs panel is hidden and the header "Docs" and "Metadata" buttons are not highlighted
//   When I click "Metadata" in the header
//   Then the panel reopens on the "Metadata" tab
//   When I click "Toggle panel orientation"
//   Then the docs panel moves below the code
// Still pending, old: after "Toggle panel orientation" the docs stay beside the code here, though a lone probe saw them move below (unconfirmed)
test('@S13', PENDING, async ({ page }) => {
  const { wf } = givenIntake();
  await openAs(page, wf, SEND);
  await expect(docsTab(page, 'Docs')).toBeVisible();
  expect(await docsBelowCode(page)).toBe(false);

  await closeDocsButton(page).click();

  await expect(docsTab(page, 'Docs')).toBeHidden();
  await expect
    .poll(() => toggledOn(page, headerToggle(page, 'Docs')))
    .toBe(false);
  await expect
    .poll(() => toggledOn(page, headerToggle(page, 'Metadata')))
    .toBe(false);

  await headerToggle(page, 'Metadata').click();
  await expect(docsTab(page, 'Metadata')).toBeVisible();
  await expect.poll(() => tabShowing(docsTab(page, 'Metadata'))).toBe(true);

  await orientationButton(page).click();
  await expect.poll(() => docsBelowCode(page), EVENTUALLY).toBe(true);
});

// @S20 @variant:ai-assistant-enabled
// Scenario: The AI assistant works on the job open in the IDE
//   Given the IDE is open on "Send to DHIS2" and the AI assistant panel is open
//   Then the assistant's context is job "Send to DHIS2" with its code and adaptor
//   And a suggested change can be previewed as a diff over the code and closed with "Close diff preview"
test('@S20', PENDING, () => {
  test.skip(true, 'needs an AI assistant service configured on the instance');
});

// ---------------------------------------------------------------------------
// Use runs beside the code
// ---------------------------------------------------------------------------

// @S14
// Scenario: Run history beside the code
//   Given the IDE is open with no run loaded
//   When I click "History" or press Ctrl+H
//   Then the right panel lists the workflow's recent work orders
//   When I pick run "R"
//   Then the URL run becomes "R" and the run viewer shows "R"
//   When I close "R"'s run chip
//   Then the URL has no run and the right panel closes
// Ctrl+H first, then "History" once the panel has closed.
test('@S14', PASSING_OLD, async ({ page }) => {
  const { id, run } = givenRun();
  await signInAs(page, ME);
  await openIde(page, id, run.workflowId, jobIdOf(run.workflowId, 'Fetch'));

  await page.keyboard.press('ControlOrMeta+h');
  await expect(historyWorkOrder(page, run.workOrderId)).toBeVisible(EVENTUALLY);

  await pickHistoryRun(page, run.workOrderId, run.runId);
  await expect.poll(() => editorQuery(page).run).toBe(run.runId);
  await expect(runChip(page, run.runId)).toBeVisible();

  await closeRunChip(page);
  await expect.poll(() => editorQuery(page).run).toBeUndefined();
  await expect(runChip(page, run.runId)).toHaveCount(0);
  await expect(historyWorkOrder(page, run.workOrderId)).toHaveCount(0);

  await historyButton(page).click();
  await expect(historyWorkOrder(page, run.workOrderId)).toBeVisible(EVENTUALLY);
});

// @S15
// Scenario: Running from the IDE opens the run panel first, also by keyboard
//   Given I am an editor with the IDE open and no right panel showing
//   When I press Ctrl+Enter
//   Then the run panel opens and no run is started
//   And the canvas header's run button is disabled while the IDE is open
//   When I pick an input and press Ctrl+Enter again
//   Then a run starts and the IDE follows it in the run viewer
test('@S15', PASSING_OLD, async ({ page }) => {
  const { wf } = givenIntake();
  await openAs(page, wf, SEND);

  await page.keyboard.press('ControlOrMeta+Enter');

  await expect(inputChoice(page, 'Empty')).toBeVisible();
  await page.waitForTimeout(2000);
  expect(runRetry.runsOfWorkflow(wf.id)).toHaveLength(0);
  await expect(runRetry.runButton(header(page))).toBeDisabled();

  await inputChoice(page, 'Empty').click();
  await page.keyboard.press('ControlOrMeta+Enter');

  await expect.poll(() => runRetry.runsOfWorkflow(wf.id).length).toBe(1);
  const [started] = runRetry.runsOfWorkflow(wf.id);
  await expect.poll(() => editorQuery(page).run).toBe(started.id);
  await expect(runChip(page, started.id)).toBeVisible();
});

// @S17
// Scenario: Following a run preselects the step's input so it can be retried
//   Given run "R" failed at "Transform" and I am an editor
//   When I open the IDE on "Transform" following "R"
//   Then the input "R" gave "Transform" is selected without my choosing it
//   And the run button reads "Retry"
// "Retry" is only offered when the chosen input is the one the step had.
test('@S17', PASSING_OLD, async ({ page }) => {
  const { id, run } = givenRun(
    { [ME]: 'editor' },
    {
      steps: [
        { name: 'Fetch', output: { patients: 3 } },
        { name: 'Transform', exit: 'fail', errorType: 'RuntimeError' },
      ],
      state: 'failed',
    }
  );
  await signInAs(page, ME);

  await openIde(
    page,
    id,
    run.workflowId,
    jobIdOf(run.workflowId, 'Transform'),
    {
      run: run.runId,
    }
  );

  await expect(runRetry.runButton(ideHeader(page))).toHaveText(
    /Retry/,
    EVENTUALLY
  );
});

// @S18
// Scenario: A job that was not part of the loaded run cannot be run against it
//   Given the IDE is following finished run "R", which did not execute "Load"
//   When I pick "Load" in the job selector
//   Then the run chip shows a warning with "Load was not part of this run. Pick another job or deselect the run."
//   And "Run" is disabled with "Selected job was not part of this run"
// Still pending, old: hovering the warning run chip shows no tooltip; the chip does not pass the tooltip's hover handlers on
test('@S18', PENDING, async ({ page }) => {
  const { id, run } = givenRun(
    { [ME]: 'editor' },
    { steps: [{ name: 'Fetch' }, { name: 'Transform' }], jobs: ['Load'] }
  );
  await signInAs(page, ME);
  await openIde(page, id, run.workflowId, jobIdOf(run.workflowId, 'Fetch'), {
    run: run.runId,
  });
  await expect(runChip(page, run.runId)).toBeVisible(EVENTUALLY);

  await pickJob(page, 'Load');

  await page.mouse.move(0, 0);
  await runChip(page, run.runId).hover();
  await expect(
    page.getByRole('tooltip').filter({
      hasText:
        'Load was not part of this run. Pick another job or deselect the run.',
    })
  ).toBeVisible();
  await runRetry.S10(
    page,
    ideHeader(page),
    'Selected job was not part of this run'
  );
});

// @S19
// Scenario: A step inspect link lands in the IDE with the run loaded
//   When the flow "flow-open-run-in-editor" follows a step's inspect link for run "R" and job "Send to DHIS2"
//   Then the IDE is open on "Send to DHIS2"
//   And the right panel shows "R" in the run viewer with the log tab
// The link is followed from History.
test('@S19', PASSING_OLD, async ({ page }) => {
  const { id, run } = givenRun(
    { [ME]: 'editor' },
    { steps: [{ name: 'Fetch' }, { name: SEND }] }
  );
  await signInAs(page, ME);
  await openHistory(page, id);
  await expandWorkOrder(page, run.workOrderId);
  const href = await inspectStepLink(page, run.steps[SEND]).getAttribute(
    'href'
  );

  await open(page, href!);

  await ideReady(page);
  await expect(jobSelector(page)).toHaveText(new RegExp(SEND));
  await expect(runChip(page, run.runId)).toBeVisible(EVENTUALLY);
  await expect.poll(() => tabShowing(runTab(page, 'Logs'))).toBe(true);
});

// @S22
// Scenario: The run panel warns when the run executed a different version
//   Given the IDE is on version 7 and following run "R", which ran on version 3
//   Then the run panel shows "This run took place on version 3."
// Without experimental features, which load the run's own version instead.
test('@S22', PASSING_OLD, async ({ page }) => {
  setPreferences(ME, { experimental_features: false });
  const { id, by, run } = givenRun();
  renameStepOnNode(run.workflowId, 'Load', 'Load v2', by);
  await signInAs(page, ME);

  await openIde(page, id, run.workflowId, jobIdOf(run.workflowId, 'Fetch'), {
    run: run.runId,
  });

  await expect(versionWarning(page)).toHaveText(
    `This run took place on version ${run.version}.`,
    EVENTUALLY
  );
});

// ---------------------------------------------------------------------------
// shared-adaptor-credential-config: the IDE header's adaptor box. Page S16
// runs shared S01 and S11. These are the rest its annotation names for the
// IDE: S03, S07, S17, S18. The others run on the step inspector
// (workflow-editor-inspectors).
// ---------------------------------------------------------------------------

test.describe('shared-adaptor-credential-config', () => {
  const name = (id: string) =>
    `shared-adaptor-credential-config@${id} on workflow-editor-ide`;

  test(name('S03'), PASSING_OLD, async ({ page }) => {
    const { id, wf } = givenIntake();
    adaptorConfig.jobUses(wf.steps.Fetch, DHIS2);
    givenCredential(id, 'DHIS2 prod');
    seedKeychain(id, { name: 'Per facility', path: '$.facility_id' }, OWNER);
    await openAs(page, wf, 'Fetch');

    await adaptorConfig.S03(
      page,
      adaptorBox(page),
      { projectId: id, jobId: wf.steps.Fetch },
      () => saveWorkflow(page)
    );
  });

  // The adaptor catalogue is instance-wide
  test(name('S07'), PASSING_OLD_SERIAL, async ({ page }) => {
    cleanups.push(adaptorConfig.withAdaptorVersions());
    const { wf } = givenIntake();
    adaptorConfig.jobUses(wf.steps.Fetch, DHIS2);
    await openAs(page, wf, 'Fetch');

    await adaptorConfig.S07(page, adaptorBox(page));
  });

  // Still pending, old: after Escape closes the adaptor picker, the IDE header's adaptor box is gone (unconfirmed)
  test(name('S17'), PENDING, async ({ page }) => {
    await givenStepOnDhis2(page);
    await adaptorConfig.S17(page, adaptorBox(page));
    await expect(closeIdeButton(page)).toBeVisible();
  });

  test(name('S18'), PASSING_OLD, async ({ page }) => {
    await givenStepOnDhis2(page, 'viewer');
    await adaptorConfig.S18(page, adaptorBox(page));
  });
});

// ---------------------------------------------------------------------------
// shared-run-retry-controls: the IDE header's run control (S04 to S06, S08 to
// S10, S13). S07 runs on workflow-editor-canvas, which opens the IDE for its
// second half; S01 to S03, S11 and S12 run there too.
// ---------------------------------------------------------------------------

test.describe('shared-run-retry-controls', () => {
  const name = (id: string) =>
    `shared-run-retry-controls@${id} on workflow-editor-ide`;

  // When I open the IDE on step <step> of the run's workflow, following it
  const followIn = (
    page: Page,
    id: string,
    run: { workflowId: string; runId: string },
    step: string
  ) =>
    openIde(page, id, run.workflowId, jobIdOf(run.workflowId, step), {
      run: run.runId,
    });

  // Given I wipe the input, or not
  test(name('S04'), PASSING_OLD, async ({ page }) => {
    const { id, run } = givenRun();
    await signInAs(page, ME);
    await followIn(page, id, run, 'Fetch');

    await runRetry.S04(page, ideHeader(page), async () => {
      runRetry.wipeInput(run.inputId);
      await followIn(page, id, run, 'Fetch');
    });
  });

  // Still pending, old: "Run (New Work Order)" from the IDE runs with an empty input, not the input the retry used (unconfirmed)
  test(name('S05'), PENDING, async ({ page }) => {
    const { id, run } = givenRun(
      { [ME]: 'editor' },
      { steps: [{ name: 'Fetch', output: { patients: 3 } }, { name: 'Load' }] }
    );
    // A retry carries over the steps upstream on the workflow's paths
    connectRunWorkflow(run.workflowId, id, ['Fetch', 'Load']);
    await signInAs(page, ME);
    await followIn(page, id, run, 'Load');

    await runRetry.S05(
      page,
      ideHeader(page),
      { ...run, upstream: [run.steps.Fetch] },
      () => followIn(page, id, run, 'Load')
    );
  });

  test(name('S06'), PASSING_OLD, async ({ page }) => {
    const { id, run } = givenRun();
    await signInAs(page, ME);
    await followIn(page, id, run, 'Fetch');
    await expect(runRetry.runButton(ideHeader(page))).toHaveText(/Retry/);

    await runRetry.S06(page, run.workflowId, () => focusCode(page));
  });

  // Stand-in: a step with a blank name, written into the shared document
  test(name('S08'), PASSING_OLD, async ({ page }) => {
    const { wf } = givenIntake();
    const sock = await watchEditorSocket(page);
    await openAs(page, wf, 'Fetch');
    await openRunPanel(page);
    await sock.sendDocChange(blankStepName(wf.steps[SEND]));

    await runRetry.S08(page, ideHeader(page), wf.id);
  });

  test(name('S09'), PASSING_OLD, async ({ page }) => {
    setPreferences(ME, { experimental_features: true });
    const { wf, by } = givenIntake({ [ME]: 'editor' }, { enabled: false });
    goLiveOnNode(wf.id, by);
    await openAs(page, wf, 'Fetch');
    await openRunPanel(page);

    await runRetry.S09(page, ideHeader(page), wf.id);
  });

  // Examples, one step each; the pinned row comes after the others, since
  // its new version is saved outside the editor. The deleted row is its own
  // test.
  test(name('S10'), PASSING_OLD, async ({ page }) => {
    const why = runRetry.given.S10;
    const h = givenIntake({ [ME]: 'viewer' });
    const sock = await watchEditorSocket(page);
    await openAs(page, h.wf, 'Fetch');

    await test.step('I am a viewer', () =>
      runRetry.S10(page, ideHeader(page), why.viewer));

    changeRoleOnNode(h.id, ME, 'editor', { quietly: true });
    await test.step('the editor is disconnected', async () => {
      await reopen(page, h.wf, 'Fetch');
      sock.drop();
      await runRetry.S10(page, ideHeader(page), why.disconnected);
      sock.reconnect();
    });

    const pinned = storedWorkflow(h.wf.id).lock_version;
    renameStepOnNode(h.wf.id, SEND, 'Send v2', h.by);
    await test.step('I am viewing a pinned version', async () => {
      await reopen(page, h.wf, 'Fetch', { v: pinned });
      await runRetry.S10(page, ideHeader(page), why.pinned);
    });
  });

  // Still pending, old: an open editor leaves for the workflow list when its workflow is deleted, so no reason is shown
  test(`${name('S10')}, deleted`, PENDING, async ({ page }) => {
    const { wf } = givenIntake();
    await openAs(page, wf, 'Fetch');
    deleteWorkflowOnNode(wf.id, OWNER);
    await runRetry.S10(page, ideHeader(page), runRetry.given.S10.deleted);
  });

  // Still pending, old: the run button's text still holds "Processing" after the run has finished (unconfirmed: may be hidden text)
  test(name('S13'), PENDING, async ({ page }) => {
    const { wf } = givenIntake();
    // The e2e worker finishes a run at once; a slow first step keeps it
    // processing long enough to see
    exec(`update jobs set body = $b$fn(state => new Promise(r =>
      setTimeout(() => r(state), 10000)));$b$
      where id = '${wf.steps.Fetch}'`);
    await openAs(page, wf, 'Fetch');
    await openRunPanel(page);

    await runRetry.S13(page, ideHeader(page), wf.id);
  });
});
