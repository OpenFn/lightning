// Scenarios from annotations/flows/flow-editor-credentials-broadcast.md: a
// credential saved in one editor reaching a colleague's open editor.
//
// Who's who: "I" am editor@openfn.org, an admin on "Malawi HIV" (a keychain
// credential takes an admin). super@openfn.org stands in for
// "amara@example.org", an editor (a viewer in S02) with "Intake" open in a
// browser of her own. owner@openfn.org owns the project and saves its
// workflows through Lightning. Every project is seeded by the test and
// removed again afterwards, with the credentials made in it. "Intake" is a
// webhook trigger leading to "Fetch", then "Load", both on DHIS2.
//
// Tab A's own save, attach and reopen is shared-adaptor-credential-config
// S11 (and S14 for keychains); this flow checks the other tab.
import { expect, test, type Browser, type Page } from '@playwright/test';

import {
  enterBody,
  saveCredential,
  startCredential,
} from './pages/credentials-index';
import { openSettings } from './pages/project-settings';
import {
  editorToast,
  openEditor,
  saveButton,
  watchEditorSocket,
} from './pages/workflow-editor';
import { adaptorBox, panelQuery } from './pages/workflow-editor-inspectors';
import * as adaptorConfig from './shared/adaptor-credential-config';
import {
  field,
  otherSession,
  removeCredentialsNamed,
  removeWorkflowData,
  seedCredential,
  seedEditorWorkflow,
  seedWorkspace,
  signInAs,
  type EditorWorkflow,
} from './steps';

const ME = 'editor@openfn.org';
const OWNER = 'owner@openfn.org';
const AMARA = 'super@openfn.org';

type Role = 'owner' | 'admin' | 'editor' | 'viewer';

const DHIS2 = '@openfn/language-dhis2@latest';

// Scenarios that don't pass on the old app, and why; the rest pass there
const STILL_PENDING: Record<string, string> = {};
const tags = (key: string) => ({
  tag: [key in STILL_PENDING ? '@pending' : '@passing-old'],
});

// A page that has to react to something happening elsewhere gets this long
const EVENTUALLY = { timeout: 15000 };
// How long a page is watched for a change that should not come
const QUIET = 3000;

let cleanups: (() => void)[] = [];
test.beforeEach(() => {
  cleanups = [];
});
test.afterEach(() => {
  for (const cleanup of cleanups.reverse()) cleanup();
});

// Given project "Malawi HIV", where I am an admin and Amara is <amara>, has
// workflow "Intake" with both steps on DHIS2
function givenIntake(amara: Role = 'editor') {
  const w = seedWorkspace(
    {
      name: 'Malawi HIV',
      members: { [OWNER]: 'owner', [ME]: 'admin', [AMARA]: amara },
    },
    OWNER
  );
  cleanups.push(w.remove);
  const id = w.id('Malawi HIV');
  cleanups.push(() => removeWorkflowData(id));
  const wf = seedEditorWorkflow(id, OWNER);
  for (const step of ['Fetch', 'Load'])
    adaptorConfig.jobUses(wf.steps[step], DHIS2);
  return wf;
}

// The editor query that opens step <step>'s inspector
const stepOf = (wf: EditorWorkflow, step: string) =>
  panelQuery({ job: wf.steps[step] });

// Given <email> has <wf> open with step <step>'s inspector, in <page> or a
// browser of their own
async function opens(
  page: Page,
  email: string,
  wf: EditorWorkflow,
  step: string
) {
  await signInAs(page, email);
  await openEditor(page, wf.projectId, wf.id, stepOf(wf, step));
  return page;
}
const amaraOpens = async (
  browser: Browser,
  wf: EditorWorkflow,
  step = 'Fetch'
) => opens(await otherSession(browser, AMARA), AMARA, wf, step);

// The credentials made through the pages in this test, removed afterwards
const madeByMe = (...names: string[]) =>
  cleanups.push(() => removeCredentialsNamed(ME, names));

// @S01
// Scenario Outline: A credential saved in one editor appears in a colleague's open editor
//   Given "amara@example.org" and I both have workflow "Intake" open in the editor
//   And "amara@example.org" has "Configure connection" open for step "Fetch"
//   When I <action> from "Configure connection" on step "Load"
//   Then "amara@example.org" eventually sees <name> in her credential list under <group>
//   Examples:
//     | save a new DHIS2 credential "DHIS2 test"          | "DHIS2 test"  | the matching credentials |
//     | save a new keychain credential "Per country"      | "Per country" | "Keychain Credentials"   |
//     | rename my credential "DHIS2 prod" to "DHIS2 live" | "DHIS2 live"  | the matching credentials |
// "DHIS2 prod" is mine, shared with the project, so the keychain row has a
// matching credential to show first and Amara turns to the others.
test('@S01', tags('S01'), async ({ page, browser }) => {
  test.slow(); // three rows, each with two editors
  const examples: [
    string,
    (box: ReturnType<typeof adaptorBox>) => Promise<void>,
    string,
    string,
  ][] = [
    [
      'a new DHIS2 credential',
      box => adaptorConfig.saveDhis2FromStep(page, box, 'DHIS2 test'),
      'DHIS2 test',
      'matching',
    ],
    [
      'a new keychain credential',
      box =>
        adaptorConfig.saveKeychainFromStep(
          page,
          box,
          'Per country',
          '$.country'
        ),
      'Per country',
      'Keychain Credentials',
    ],
    [
      'a renamed credential',
      box =>
        adaptorConfig.renameFromStep(page, box, 'DHIS2 prod', 'DHIS2 live'),
      'DHIS2 live',
      'matching',
    ],
  ];
  madeByMe('DHIS2 test');
  for (const [what, act, name, group] of examples)
    await test.step(what, async () => {
      const wf = givenIntake();
      const prod = seedCredential(ME, {
        name: 'DHIS2 prod',
        schema: 'dhis2',
        bodies: {
          main: {
            username: 'admin',
            password: 'district',
            hostUrl: 'https://play.dhis2.example.org',
          },
        },
        projects: [wf.projectId],
      });
      cleanups.push(prod.remove);
      const amara = await amaraOpens(browser, wf);
      await adaptorConfig.openConfigure(amara, adaptorBox(amara));
      expect(await adaptorConfig.listedUnder(amara, group)).not.toContain(name);
      await opens(page, ME, wf, 'Load');

      await act(adaptorBox(page));

      await expect
        .soft(async () =>
          expect(await adaptorConfig.listedUnder(amara, group)).toContain(name)
        )
        .toPass(EVENTUALLY);
      await amara.context().close();
      // Names are unique per owner, and the next row seeds its own
      prod.remove();
    });
});

// @S02
// Scenario: A viewer's open editor receives the list too
//   Given "amara@example.org" is a viewer with "Intake" open
//   When I save a new DHIS2 credential "DHIS2 test" from step "Fetch" and it is attached
//   Then "amara@example.org" eventually sees "Fetch" show "DHIS2 test"
// Saving and attaching is shared-adaptor-credential-config S11.
test('@S02', tags('S02'), async ({ page, browser }) => {
  const wf = givenIntake('viewer');
  madeByMe('DHIS2 test');
  const amara = await amaraOpens(browser, wf);
  await expect(adaptorBox(amara)).not.toContainText('DHIS2 test');
  await opens(page, ME, wf, 'Fetch');

  await adaptorConfig.S11(
    page,
    adaptorBox(page),
    {
      projectId: wf.projectId,
      jobId: wf.steps.Fetch,
      projectName: 'Malawi HIV',
    },
    async () => {
      await saveButton(page).click();
      await expect(editorToast(page, 'Workflow saved')).toBeVisible();
    }
  );

  await expect(adaptorBox(amara)).toContainText('DHIS2 test', EVENTUALLY);
});

// @S03
// Scenario: An editor that reconnects picks up credentials added on the credentials page
//   Given I have "Intake" open in the editor
//   And in another tab I create project credential "Salesforce prod" on the credentials page
//   Then my editor's credential list does not yet include "Salesforce prod"
//   When my editor's connection drops and reconnects
//   Then my credential list includes "Salesforce prod"
// "Salesforce prod" is a raw JSON credential, listed under "Generic
// Credentials" for a DHIS2 step.
test('@S03', tags('S03'), async ({ page }) => {
  const wf = givenIntake();
  madeByMe('Salesforce prod');
  const sock = await watchEditorSocket(page);
  await opens(page, ME, wf, 'Fetch');

  const settings = await page.context().newPage();
  await openSettings(settings, wf.projectId, 'Credentials');
  const form = await startCredential(settings, 'Raw JSON');
  await field(form, 'Credential Name').fill('Salesforce prod');
  await enterBody(form, '{"apiKey": "abc123"}');
  await saveCredential(form);
  await settings.close();

  await page.waitForTimeout(QUIET);
  await adaptorConfig.openConfigure(page, adaptorBox(page));
  expect(
    await adaptorConfig.listedUnder(page, 'Generic Credentials')
  ).not.toContain('Salesforce prod');
  await adaptorConfig.closeConfigure(page);

  sock.drop();
  await page.waitForTimeout(1000);
  sock.reconnect();

  await adaptorConfig.openConfigure(page, adaptorBox(page));
  await expect(async () =>
    expect(
      await adaptorConfig.listedUnder(page, 'Generic Credentials')
    ).toContain('Salesforce prod')
  ).toPass(EVENTUALLY);
});
