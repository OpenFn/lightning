// Where today's project settings page (HEEx) and the design-system one
// differ. Everything that knows how either version is built lives here, so a
// redesign of /projects/:id/settings only changes this file. The Credentials
// tab shows the credentials list, so pages/credentials-index.ts covers that
// tab's rows and dialogs.
import { expect, type Locator, type Page } from '@playwright/test';

import { toast } from '../shared/flash-messages';
import {
  field,
  open,
  pushEvent,
  submit,
  submittingExtraField,
  type watchLiveView,
} from '../steps';

// Each tab's label and the fragment that opens it
export const TABS = {
  Setup: 'project',
  Credentials: 'credentials',
  Collections: 'collections',
  'Webhook Security': 'webhook_security',
  Collaboration: 'collaboration',
  Security: 'security',
  'Sync to GitHub': 'vcs',
  'Data Storage': 'data-storage',
  'History Exports': 'history-exports',
} as const;

export type TabLabel = keyof typeof TABS;

// A tab by its whole label ("Security" is not "Webhook Security"). Both
// versions give tabs the tab role.
export const tab = (page: Page, label: TabLabel) =>
  page.getByRole('tab', { name: label, exact: true });

export const expectSelected = (page: Page, label: TabLabel) =>
  expect(tab(page, label)).toHaveAttribute('aria-selected', 'true');

export const settingsPath = (projectId: string, label?: TabLabel) =>
  `/projects/${projectId}/settings${label ? `#${TABS[label]}` : ''}`;

export const deletePath = (projectId: string) =>
  `/projects/${projectId}/settings/delete`;

// When I open project <projectId>'s settings on tab <label>
export async function openSettings(
  page: Page,
  projectId: string,
  label?: TabLabel
) {
  await open(page, settingsPath(projectId, label));
  await expectSelected(page, label ?? 'Setup');
}

// When I click tab <label> — waits for its panel
export async function chooseTab(page: Page, label: TabLabel) {
  await tab(page, label).click();
  await expectSelected(page, label);
  await expect(panel(page, label).first()).toBeVisible();
}

// The panel tab <label> shows. Hidden panels have hidden headings, so nothing
// a user sees names one; both versions give each panel the id
// "<fragment>-panel". The design-system page draws Sync to GitHub's
// new-connection form beside its panel rather than in it, so that tab's
// panel is both (one element wherever the form isn't shown).
export const panel = (page: Page, label: TabLabel) =>
  page.locator(
    label === 'Sync to GitHub'
      ? '[role="tabpanel"]#vcs-panel, #project-settings-vcs-hosted'
      : `[role="tabpanel"]#${TABS[label]}-panel`
  );

// What <tab> shows, spaces collapsed. Sync to GitHub's panel can be two
// elements on the design-system page (see panel()), so its text is read
// whole rather than asserted on one element.
export const shownIn = async (tab: Locator) =>
  (await tab.allTextContents()).join(' ').replace(/\s+/g, ' ');

// When the Sync to GitHub tab has finished checking the saved connection.
// Today's tab asks GitHub and then says "Your repository is properly
// configured."; the design-system page doesn't check, so this waits for the
// repository it shows.
export async function connectionChecked(page: Page) {
  const tab = panel(page, 'Sync to GitHub');
  if (await isDesignSystem(page))
    await expect.poll(() => shownIn(tab)).toContain('Repository:');
  else
    await expect
      .poll(() => shownIn(tab))
      .toContain('Your repository is properly configured.');
}

// When I change a data storage setting: picks the retention policy that
// isn't chosen yet, which today's page answers with a server render
export async function changeDataStorageSetting(page: Page) {
  await panel(page, 'Data Storage')
    .getByRole('radio', { checked: false })
    .first()
    .check();
}

// The note a member gets on a tab their role can't change
export const roleNotice = (within: Page | Locator) =>
  within.getByText(/Role based permissions: You cannot modify this project's/);

// The sandbox banner sentences, by kind
export const SANDBOX_BANNER = {
  local:
    'Changes you make here only apply to this sandbox and do not sync to the parent project on merge.',
  editable: 'Changes you make here will sync to the parent project on merge.',
  inherited: /These settings are inherited from the parent project/,
};

// Any sandbox banner within <within>
export const sandboxBanner = (within: Page | Locator) =>
  within
    .getByText(SANDBOX_BANNER.local)
    .or(within.getByText(SANDBOX_BANNER.editable))
    .or(within.getByText(SANDBOX_BANNER.inherited));

// The Setup tab's identity form (name, environment, description)
export const identityForm = (page: Page) =>
  panel(page, 'Setup')
    .locator('form')
    .filter({ hasText: 'Project description' });

// The Setup tab's concurrency form
export const concurrencyForm = (page: Page) =>
  panel(page, 'Setup')
    .locator('form')
    .filter({ hasText: 'Disable parallel execution' });

// The "Disable parallel execution" switch. Today's switch has no accessible
// name (the words sit beside it); it is the form's only switch.
export const concurrencySwitch = (page: Page) =>
  concurrencyForm(page).getByRole('switch');

// Whether this is the design-system page rather than today's HEEx one
const isDesignSystem = async (page: Page) =>
  (await page.locator('[data-react-name="ProjectSettingsPage"]').count()) > 0;

const camel = (key: string) =>
  key.replace(/_([a-z])/g, (_, c: string) => c.toUpperCase());

// When the Setup tab's identity save reaches the server with <name> and these
// <extra> fields, past what the form sends. Today the form sends "save" with
// the fields under "project"; the design-system page sends "save_identity"
// with its values (the extra fields go under both spellings).
export async function sendIdentitySave(
  page: Page,
  lv: ReturnType<typeof watchLiveView>,
  name: string,
  extra: Record<string, unknown> = {}
) {
  if (await isDesignSystem(page))
    await pushEvent(page, lv, 'save_identity', {
      rawName: name,
      ...extra,
      ...Object.fromEntries(
        Object.entries(extra).map(([k, v]) => [camel(k), v])
      ),
    });
  else
    await pushEvent(page, lv, 'save', {
      project: { raw_name: name, ...extra },
    });
}

// When a sandbox deletion confirmed with <typed> reaches the server, past the
// dialog's own check. Today the sandbox dialog sends "confirm-delete"; the
// design-system page sends "delete_project" for a project and a sandbox.
export async function sendSandboxDeletion(
  page: Page,
  lv: ReturnType<typeof watchLiveView>,
  typed: string
) {
  if (await isDesignSystem(page))
    await pushEvent(page, lv, 'delete_project', { nameConfirmation: typed });
  else
    await pushEvent(page, lv, 'confirm-delete', { confirm: { name: typed } });
}

// When a project deletion confirmed with <typed> reaches the server, past the
// dialog's own check. Today the dialog is a LiveView component with its own
// "delete" event; the design system sends "delete_project" to the page.
export async function sendProjectDeletion(
  page: Page,
  lv: ReturnType<typeof watchLiveView>,
  typed: string
) {
  if (await isDesignSystem(page))
    await pushEvent(page, lv, 'delete_project', { nameConfirmation: typed });
  else
    await pushEvent(
      page,
      lv,
      'delete',
      { project: { name_confirmation: typed } },
      '#scheduled_deletion_form'
    );
}

// Wait for <dialog> to show. Ask its heading: the design system's dialog
// wrapper is 0x0, so the dialog itself never reads as visible.
export const expectOpen = (dialog: Locator) =>
  expect(dialog.getByRole('heading').first()).toBeVisible();

// The open sandbox deletion dialog. Today's title is "Delete sandbox" with
// its close button inside; the design system's names the sandbox.
export async function sandboxDeletionDialog(page: Page) {
  const title = page.getByRole('heading', { name: /delete sandbox/i });
  const dialog = page.getByRole('dialog').filter({ has: title });
  await expectOpen(dialog);
  return dialog;
}

// The dialog's "Sandbox name" box. Today's has no label, only the name as its
// placeholder, and is the dialog's one text box.
export const sandboxNameField = (dialog: Locator) =>
  field(dialog, 'Sandbox name').or(dialog.getByRole('textbox'));

// The dialog's close button: "close" today, "Close" or "Cancel" elsewhere
export const closeButton = (dialog: Locator) =>
  dialog.getByRole('button', { name: /^(close|cancel)$/i }).first();

// The Security tab's "Require MFA?" switch. Today's switch is named by the
// words beside it, which also say whether MFA is required now.
export const mfaSwitch = (page: Page) =>
  panel(page, 'Security').getByRole('switch', { name: /Require MFA/ });

// When a change to the MFA requirement reaches the server, past the switch.
// Today the switch sends "toggle-mfa", which flips the stored value; the
// design-system page sends "set_requires_mfa" with the value it wants.
export async function sendMfaChange(
  page: Page,
  lv: ReturnType<typeof watchLiveView>,
  on: boolean
) {
  if (await isDesignSystem(page))
    await pushEvent(page, lv, 'set_requires_mfa', { on });
  else await pushEvent(page, lv, 'toggle-mfa', {});
}

// The Webhook Security tab's row for auth method <name>
export const authMethodRow = (page: Page, name: string) =>
  panel(page, 'Webhook Security')
    .getByRole('row')
    .filter({ has: page.getByText(name, { exact: true }) });

// The Webhook Security tab's "New auth method" button. Today's section
// header hides its button from assistive tech (an aria-hidden wrapper), so
// hidden elements are searched too.
export const newAuthMethod = (page: Page) =>
  panel(page, 'Webhook Security').getByRole('button', {
    name: 'New auth method',
    exact: true,
    includeHidden: true,
  });

// The open auth method dialog (create, view, delete or linked usage). Today's
// create and view dialogs carry their title in the body, not as the
// dialog's name, so the dialog is found by what it shows.
export const authMethodDialog = (page: Page, shows: string | RegExp) =>
  page.getByRole('dialog').filter({ hasText: shows });

// When I try to confirm <dialog> with "DELETE" mistyped, nothing is
// deleted. Today pressing <button> says "Please type DELETE to confirm"; the
// design system keeps <button> off until the text matches.
export async function expectMismatchRefused(dialog: Locator, button: string) {
  if (await isDesignSystem(dialog.page()))
    await expect(dialog.getByRole('button', { name: button })).toBeDisabled();
  else {
    await submit(dialog, button);
    await expect(dialog).toContainText('Please type DELETE to confirm');
  }
}

// When I choose auth type <type> in the new auth method dialog. Today the
// type is a step of its own, left with "Next", and its radios are visually
// hidden under their card, so the check goes through the card.
export async function chooseAuthType(
  page: Page,
  type: 'Basic HTTP Authentication' | 'API Key Authentication'
) {
  const dialog = authMethodDialog(page, type);
  await dialog
    .getByRole('radio', { name: new RegExp(type) })
    .check({ force: true });
  const next = dialog.getByRole('button', { name: 'Next', exact: true });
  if (await next.isVisible()) await next.click();
  await expect(field(page, 'Auth method name')).toBeVisible();
}

export type AuthMethodRequest = 'create' | 'rename' | 'delete' | 'usage';

const AUTH_METHOD_MODALS: Record<AuthMethodRequest, string> = {
  create: 'new_webhook_auth_method',
  rename: 'edit_webhook_auth_method',
  delete: 'delete_webhook_auth_method',
  usage: 'linked_usage_for_webhook_auth_method',
};

// When an auth method request of <kind> for method <id> reaches the server,
// past the page's buttons. Today every change starts by asking the server
// for its dialog ("show_modal"), which is where it is refused; the
// design-system page opens its dialogs itself and sends the change
// ("create_webhook_auth_method", "rename_webhook_auth_method",
// "delete_webhook_auth_method"). The design system has no request for the
// linked usage list, so "usage" sends nothing there.
export async function sendAuthMethodRequest(
  page: Page,
  lv: ReturnType<typeof watchLiveView>,
  kind: AuthMethodRequest,
  id?: string
) {
  if (!(await isDesignSystem(page)))
    return pushEvent(page, lv, 'show_modal', {
      target: AUTH_METHOD_MODALS[kind],
      ...(id && { id }),
    });
  if (kind === 'create')
    await pushEvent(page, lv, 'create_webhook_auth_method', {
      name: 'crafted-method',
      authType: 'api',
    });
  if (kind === 'rename')
    await pushEvent(page, lv, 'rename_webhook_auth_method', {
      id,
      name: 'crafted-name',
    });
  if (kind === 'delete')
    await pushEvent(page, lv, 'delete_webhook_auth_method', { id });
}

// The Collaboration tab's row for the member whose name or email is <who>
export const collaboratorRow = (page: Page, who: string) =>
  panel(page, 'Collaboration')
    .getByRole('row')
    .filter({ has: page.getByText(who, { exact: true }) });

// Today's button reads "Add Collaborator(s)"
// Today's section header hides it from assistive tech (see newAuthMethod)
export const addCollaboratorsButton = (page: Page) =>
  panel(page, 'Collaboration').getByRole('button', {
    name: /add collaborator/i,
    includeHidden: true,
  });

// A member's failure alert and digest, by column: today's selects carry no
// name of their own
export const failureAlertOf = (row: Locator) => row.getByRole('cell').nth(2);
export const digestOf = (row: Locator) => row.getByRole('cell').nth(3);

export const removeCollaboratorButton = (row: Locator) =>
  row.getByRole('button', { name: /remove collaborator/i });

// The open "Remove <name>" confirmation. Today's title is padded with
// whitespace, so the text isn't anchored.
export const removeDialog = (page: Page) =>
  page.getByRole('dialog').filter({ hasText: /^\s*Remove / });

// The add form, and the invite form it hands over to
export const addCollaboratorsDialog = (page: Page) =>
  page.getByRole('dialog').filter({ hasText: /add new collaborator/i });
export const inviteDialog = (page: Page) =>
  page.getByRole('dialog').filter({ hasText: /invite new user/i });

// Row <i>'s email box in the add or invite form. Today's add form names
// them by placeholder only; the invite form's have no name at all.
export const collaboratorEmail = (dialog: Locator, i = 0) =>
  dialog
    .getByRole('textbox', { name: /email/i })
    .or(dialog.getByPlaceholder('email@example.com'))
    .or(dialog.locator('input[type="email"]'))
    .nth(i);

// Row <i>'s role select: the only select on each row
export const collaboratorRole = (dialog: Locator, i = 0) =>
  dialog.getByRole('combobox').nth(i);

// When I fill row <i> of the add form
export async function fillCollaborator(
  dialog: Locator,
  i: number,
  email: string,
  role: 'Viewer' | 'Editor' | 'Admin'
) {
  await collaboratorEmail(dialog, i).fill(email);
  await collaboratorRole(dialog, i).selectOption({ label: role });
}

export const addAnotherRow = (dialog: Locator) =>
  dialog.getByRole('button', {
    name: /add (additional|another) collaborator/i,
  });

// Row <i>'s remove control. Today's is an unnamed icon button.
export async function dropRow(page: Page, dialog: Locator, i: number) {
  if (await isDesignSystem(page))
    await dialog
      .getByRole('button', { name: /remove row/i })
      .nth(i)
      .click();
  else
    await dialog
      .locator('button[name$="[collaborators_drop][]"]')
      .nth(i)
      .click();
}

// The first and last name boxes of the invite form's row <i>
export const inviteName = (
  dialog: Locator,
  part: 'First Name' | 'Last Name',
  i = 0
) =>
  dialog
    .getByRole('textbox', { name: part })
    .or(dialog.getByPlaceholder(part))
    .nth(i);

export const supportAccessSwitch = (page: Page) =>
  panel(page, 'Collaboration').getByLabel('Grant support access');

// When I flip the support access switch. Today's checkbox is visually
// hidden under the drawn switch, which takes the click.
export const toggleSupportAccess = (page: Page) =>
  supportAccessSwitch(page).click({ force: true });

export type CollaboratorRequest = 'open-add' | 'remove' | 'alert' | 'digest';

// When a collaborator request of <kind> for membership <id> reaches the
// server, past the page's controls. Today "Add" asks the server for its form
// ("toggle_collaborators_modal"); the design-system page opens it itself and
// has no such request, so "open-add" sends nothing there. Today's alert and
// digest selects send the membership as "project_user_id"; the
// design-system page sends "id".
export async function sendCollaboratorRequest(
  page: Page,
  lv: ReturnType<typeof watchLiveView>,
  kind: CollaboratorRequest,
  id = ''
) {
  const ds = await isDesignSystem(page);
  const member = ds ? { id } : { project_user_id: id };
  if (kind === 'open-add' && !ds)
    await pushEvent(page, lv, 'toggle_collaborators_modal', {});
  if (kind === 'remove')
    await pushEvent(
      page,
      lv,
      ds ? 'remove_collaborator' : 'remove_project_user',
      member
    );
  if (kind === 'alert')
    await pushEvent(page, lv, 'set_failure_alert', {
      ...member,
      ...(ds ? { on: true } : { failure_alert: 'true' }),
    });
  if (kind === 'digest')
    await pushEvent(page, lv, 'set_digest', { ...member, digest: 'daily' });
}

// The History Exports tab's row for the export requested by <who>
export const exportRow = (page: Page, who: string) =>
  panel(page, 'History Exports').getByRole('row').filter({ hasText: who });

// When I submit the add form for <email> with a role the form doesn't
// offer: the select is given that option, so the form shows the answer.
export async function submitAddWithRole(
  page: Page,
  email: string,
  role: string
) {
  const dialog = addCollaboratorsDialog(page);
  await collaboratorEmail(dialog).fill(email);
  const select = collaboratorRole(dialog);
  await select.evaluate((el, value) => {
    const option = document.createElement('option');
    option.value = option.text = value;
    el.appendChild(option);
  }, role);
  await select.selectOption(role);
  await dialog
    .locator('form')
    .evaluate(form => (form as HTMLFormElement).requestSubmit());
}

// The Credentials tab's "Add new" option <item>, once the menu is open.
// Today's options are menu items named by their text ("OAuth Client" also
// reads "Advanced"), in a header hidden from assistive tech.
export async function addNewOption(
  page: Page,
  item: 'Credential' | 'Keychain' | 'OAuth client'
) {
  const menu = panel(page, 'Credentials');
  // The design system's menu opens outside the tab panel
  const option = page
    .getByRole('menuitem', {
      name: new RegExp(`^${item}`, 'i'),
      includeHidden: true,
    })
    .filter({ visible: true });
  if (!(await option.isVisible()))
    await menu
      .getByRole('button', { name: 'Add new', includeHidden: true })
      .click();
  await expect(option).toBeVisible();
  return option;
}

// Whether an "Add new" option can be chosen. Today a disabled option is a
// greyed menu item that sends nothing; the design system marks it
// aria-disabled.
export async function optionDisabled(option: Locator) {
  if ((await option.getAttribute('aria-disabled')) === 'true') return true;
  if ((await option.getAttribute('data-disabled')) !== null) return true;
  // The design system's class names "data-disabled:cursor-not-allowed" on
  // every option, so only the bare class counts
  return /(^|\s)cursor-not-allowed(\s|$)/.test(
    (await option.getAttribute('class')) ?? ''
  );
}

// When I choose "Add new" then "Keychain" — returns its form
export async function addKeychain(page: Page) {
  await (await addNewOption(page, 'Keychain')).click();
  const form = keychainForm(page, /create keychain credential/i);
  await expectOpen(form);
  return form;
}

// The open keychain form titled <title>
export const keychainForm = (page: Page, title: string | RegExp) =>
  page.getByRole('dialog').filter({
    has: page.getByRole('heading', { name: title }),
  });

// When I fill the keychain form; a field left out is left as it is
export async function fillKeychain(
  form: Locator,
  values: { name?: string; path?: string; defaultCredential?: string }
) {
  if (values.name !== undefined) await field(form, 'Name').fill(values.name);
  if (values.path !== undefined)
    await field(form, 'JSONPath Expression').fill(values.path);
  if (values.defaultCredential !== undefined)
    await defaultCredentialPicker(form).selectOption({
      label: values.defaultCredential,
    });
}

// When the keychain form checks what I typed. Today it checks as I leave a
// field, and turns "Create" off; the design system checks when I press
// "Create" (the server's answer).
export async function checkKeychain(form: Locator) {
  if (await isDesignSystem(form.page())) await keychainSaveButton(form).click();
  else await field(form, 'JSONPath Expression').blur();
}

// Once the page is open: the keychain form's save will carry default
// credential <id> whatever the picker says. Returns the submit step. Today's
// form sends "default_credential_id", the design system's
// "defaultCredentialId"; the page reloads so the request can be rewritten.
export async function craftingDefaultCredential(page: Page, id: string) {
  const name = (await isDesignSystem(page))
    ? 'defaultCredentialId'
    : 'default_credential_id';
  const crafted = await submittingExtraField(page, name, id);
  await page.reload();
  return crafted;
}

// The keychain form's default credential picker
export const defaultCredentialPicker = (form: Locator) =>
  field(form, 'Default Credential');

// The keychain form's save button: "Create" for a new one, "Save changes"
// for an edit (today "Save Changes")
export const keychainSaveButton = (form: Locator) =>
  form.getByRole('button', { name: /^(Create|Save changes)$/i });

// I am told <text> after a request sent past the page. Today it is a flash;
// the design-system page answers the request itself, and nothing on the page
// sent this one, so the answer is read.
export async function expectRefusal(
  page: Page,
  lv: ReturnType<typeof watchLiveView>,
  text: RegExp
) {
  if (await isDesignSystem(page))
    expect(JSON.stringify(lv.replies().at(-1))).toMatch(text);
  else await expect(toast(page, text)).toBeVisible();
}

// When a request to open the new <target> form ("new_credential",
// "new_keychain_credential", "new_oauth_client") reaches the server, past
// the disabled menu. Today the menu asks the credential list to open it
// ("show_modal"); the design system opens its forms itself, so the request
// is the save: a credential named "Crafted".
export async function sendNewCredentialRequest(
  page: Page,
  lv: ReturnType<typeof watchLiveView>,
  target: 'new_credential' | 'new_keychain_credential' | 'new_oauth_client'
) {
  if (!(await isDesignSystem(page)))
    return pushEvent(
      page,
      lv,
      'show_modal',
      { target },
      '#credentials-index-component'
    );
  const save = {
    new_credential: 'create_credential',
    new_keychain_credential: 'create_keychain_credential',
    new_oauth_client: 'create_oauth_client',
  }[target];
  await pushEvent(page, lv, save, { name: 'Crafted', path: '$.id' });
}

// When a change to keychain <id> reaches the server, past the page's
// buttons. Today an edit starts by asking for the form
// ("edit_keychain_credential"), which is where it is refused; the design
// system opens the form itself and sends the save, here a rename to
// "Crafted".
export async function sendKeychainEdit(
  page: Page,
  lv: ReturnType<typeof watchLiveView>,
  id: string
) {
  if (await isDesignSystem(page))
    await pushEvent(page, lv, 'update_keychain_credential', {
      id,
      name: 'Crafted',
    });
  else
    await pushEvent(
      page,
      lv,
      'edit_keychain_credential',
      { id },
      '#credentials-index-component'
    );
}

// When a request to edit credential <id> reaches the server, past the
// page's buttons. Today it asks for the form ("edit_credential"); the design
// system sends the save, here a rename to "Crafted".
export async function sendCredentialEdit(
  page: Page,
  lv: ReturnType<typeof watchLiveView>,
  id: string
) {
  if (await isDesignSystem(page))
    await pushEvent(page, lv, 'update_credential', { id, name: 'Crafted' });
  else
    await pushEvent(
      page,
      lv,
      'edit_credential',
      { id },
      '#credentials-index-component'
    );
}

// The Collections tab's "Create collection" button. Today's section header
// hides it from assistive tech (an aria-hidden wrapper), so nothing by role
// finds it; both versions give it this id.
export const createCollectionButton = (page: Page) =>
  panel(page, 'Collections').locator('#open-create-collection-modal-button');

// The text the open collection preview shows, with drawn lines joined up.
// Today it is a read-only Monaco, which draws a long line as several; the
// design-system page shows a plain block.
export async function previewText(dialog: Locator) {
  const lines = await dialog
    .locator('.monaco-editor .view-line')
    .allInnerTexts();
  const text = lines.length
    ? lines.join('')
    : (await dialog.locator('pre').allInnerTexts()).join('');
  return text.replace(/\u00a0/g, ' ');
}

// When I click <edit> on a collection's row, and on the design system save
// the form as it opened. Today the click asks the server for the form, so a
// collection deleted since the page loaded is reported then; the design
// system opens the form itself and the server hears of it on save.
export async function editCollection(page: Page, edit: Locator) {
  await edit.click();
  if (await isDesignSystem(page))
    await submit(page.getByRole('dialog', { name: 'Edit Collection' }), 'Save');
}

export type CollectionRequest = 'new' | 'edit' | 'delete' | 'preview';

// When a collection request of <kind> for <collection> reaches the server,
// past the tab's buttons. Today every change starts by asking the component
// for its form ("toggle_action", by name), which is where it is refused; the
// design-system page opens its forms itself and sends the change by id, here
// a create or rename to "crafted".
export async function sendCollectionRequest(
  page: Page,
  lv: ReturnType<typeof watchLiveView>,
  kind: CollectionRequest,
  collection: { id: string; name: string } = { id: '', name: '' }
) {
  if (await isDesignSystem(page)) {
    const { id } = collection;
    const [event, value] = {
      new: ['create_collection', { rawName: 'crafted' }],
      edit: ['rename_collection', { id, rawName: 'crafted' }],
      delete: ['delete_collection', { id }],
      preview: ['preview_collection', { id }],
    }[kind] as [string, Record<string, unknown>];
    return pushEvent(page, lv, event, value);
  }
  const { name } = collection;
  if (kind === 'preview')
    return pushEvent(
      page,
      lv,
      'preview_collection',
      { collection: name },
      '#collections'
    );
  await pushEvent(
    page,
    lv,
    'toggle_action',
    { action: kind, ...(kind !== 'new' && { collection: name }) },
    '#collections'
  );
}

// The Data Storage tab's period selects. Today's selects have no label (the
// heading above is plain text) and no id, so they're found by field name; the
// design system's are named.
const periodSelect = (page: Page, name: string, field: string) => {
  const tab = panel(page, 'Data Storage');
  return tab
    .getByRole('combobox', { name })
    .or(tab.locator(`select[name="project[${field}]"]`));
};
export const historySelect = (page: Page) =>
  periodSelect(page, 'History Retention Period', 'history_retention_period');
export const ioSelect = (page: Page) =>
  periodSelect(
    page,
    'Input/Output Data Retention Period',
    'dataclip_retention_period'
  );

// Before saving a form that today checks each change on the server: wait
// for that check's message <text>. The design system checks on save.
export async function formChecked(form: Locator, text: string) {
  if (!(await isDesignSystem(form.page())))
    await expect(form.getByText(text)).toBeVisible();
}

// The period a select shows ("7 Days", or the "Select Period" prompt), and
// the periods it offers. Both versions draw a native select.
export const shownPeriod = (select: Locator) =>
  select.evaluate(el => (el as HTMLSelectElement).selectedOptions[0]?.text);
export const offeredPeriods = async (select: Locator) =>
  (await select.locator('option').allInnerTexts())
    .map(t => t.trim())
    .filter(t => t !== 'Select Period');

// When I choose period <label> ("7 Days") in <select>
export const choosePeriod = (select: Locator, label: string) =>
  select.selectOption({ label });

export type DataStorageSave = {
  history: number | null;
  io: number | null;
  policy: 'retain_all' | 'erase_all';
};

// When a data storage save with these values, and these <extra> fields,
// reaches the server past the form. Today the form sends
// "save_retention_settings" with the fields under "project"; the
// design-system page sends "save_data_storage" with its values (the extra
// fields go under both spellings).
export async function sendDataStorageSave(
  page: Page,
  lv: ReturnType<typeof watchLiveView>,
  { history, io, policy }: DataStorageSave,
  extra: Record<string, unknown> = {}
) {
  if (await isDesignSystem(page))
    return pushEvent(page, lv, 'save_data_storage', {
      historyRetentionPeriod: history,
      dataclipRetentionPeriod: io,
      retentionPolicy: policy,
      ...extra,
      ...Object.fromEntries(
        Object.entries(extra).map(([k, v]) => [camel(k), v])
      ),
    });
  await pushEvent(page, lv, 'save_retention_settings', {
    project: {
      history_retention_period: history ?? '',
      dataclip_retention_period: io ?? '',
      retention_policy: policy,
      ...extra,
    },
  });
}

// The Sync to GitHub tab's three pickers. Today each is a button that opens
// a listbox, and the label points at the listbox, so nothing names the
// button; both are found through the listbox's id. A rebuild that draws a
// select or combobox named by its label is found by that.
const GITHUB_PICKERS = {
  'GitHub Installation': 'select-installations-input',
  Repository: 'select-repos-input',
  Branch: 'select-branches-input',
} as const;
export type GithubPicker = keyof typeof GITHUB_PICKERS;

const pickerList = (page: Page, picker: GithubPicker) =>
  panel(page, 'Sync to GitHub').locator(`ul#${GITHUB_PICKERS[picker]}`);

export const githubPicker = (page: Page, picker: GithubPicker) =>
  pickerList(page, picker)
    .locator('xpath=preceding-sibling::button')
    .or(
      panel(page, 'Sync to GitHub').getByRole('combobox', {
        name: picker,
        exact: true,
      })
    );

// Today's first option is the prompt ("Select a branch"), which stands for
// no choice
const PROMPT = /^Select an? /;

// The choices picker <picker> offers, prompt left out
export async function offeredIn(page: Page, picker: GithubPicker) {
  const today = pickerList(page, picker);
  const options = (await today.count())
    ? today.getByRole('option', { includeHidden: true })
    : panel(page, 'Sync to GitHub').getByRole('option');
  const texts = await options.allInnerTexts();
  return texts.map(t => t.trim()).filter(t => t && !PROMPT.test(t));
}

// What picker <picker> shows as chosen, or '' for nothing
export async function chosenIn(page: Page, picker: GithubPicker) {
  const shown = (await githubPicker(page, picker).innerText()).trim();
  return PROMPT.test(shown) ? '' : shown;
}

// When I choose <option> in picker <picker>; null clears it
export async function chooseIn(
  page: Page,
  picker: GithubPicker,
  option: string | null
) {
  await githubPicker(page, picker).click();
  const today = pickerList(page, picker);
  const list = (await today.count()) ? today : panel(page, 'Sync to GitHub');
  await (
    option === null
      ? list.getByRole('option').first()
      : list.getByRole('option', { name: option, exact: true })
  ).click();
}

// When I choose the installation, repository and branch, waiting for each
// list to load
export async function chooseRepo(
  page: Page,
  installation: string,
  repo: string,
  branch: string
) {
  for (const [picker, option] of [
    ['GitHub Installation', installation],
    ['Repository', repo],
    ['Branch', branch],
  ] as const) {
    await expect(githubPicker(page, picker)).toBeEnabled();
    await expect.poll(() => offeredIn(page, picker)).toContain(option);
    await chooseIn(page, picker, option);
    await expect.poll(() => chosenIn(page, picker)).toBe(option);
  }
}

// The refresh button beside a picker. Today's is an icon with no name; both
// ids are today's, a rebuild is found by an accessible name.
export const refreshButton = (
  page: Page,
  picker: 'GitHub Installation' | 'Branch'
) =>
  page
    .locator(
      picker === 'Branch'
        ? '#refresh-branches-button'
        : '#refresh-installation-button'
    )
    .or(
      panel(page, 'Sync to GitHub').getByRole('button', {
        name: new RegExp(`refresh.*${picker}`, 'i'),
      })
    );

// The "I understand that ..." box within <within> (the tab or the reconnect
// dialog). Today's checkbox has no label: the sentence beside it isn't tied
// to it.
export const acceptBox = (within: Locator) =>
  within
    .getByRole('checkbox', { name: /I understand/ })
    .or(within.locator('input[type="checkbox"][name="connection[accept]"]'));

// The "Path to config" box within <within>. Today's label isn't tied to the
// box, so it is named by its placeholder; found by its field name.
export const configPathBox = (within: Locator) =>
  within
    .getByRole('textbox', { name: /Path to config/ })
    .or(within.locator('input[name="connection[config_path]"]'));

// The "Remove Integration." control: a link today
export const removeIntegration = (page: Page) =>
  panel(page, 'Sync to GitHub')
    .getByRole('link')
    .or(panel(page, 'Sync to GitHub').getByRole('button'))
    .filter({ hasText: /Remove Integration/i });

// The open dialog titled <title>. Today's title holds the close button too,
// so the dialog is found by what it shows.
export const githubDialog = (page: Page, title: string) =>
  page.getByRole('dialog').filter({ hasText: title });

export type GithubRequest =
  | 'save'
  | 'validate'
  | 'reconnect'
  | 'delete-connection'
  | 'initiate-sync';

// The fields a connect form would send
export type GithubForm = {
  installation?: string;
  repo?: string;
  branch?: string;
  direction?: 'export' | 'import';
  configPath?: string;
};

// When a GitHub request of <kind> reaches the server, past the tab's
// controls, with <form> for a connect ("save"), a form change ("validate")
// or a reconnect. Today they go to the GitHub sync component with the fields
// under "connection" (export is "pull", import "deploy"). The design-system
// page takes "remove_github_connection" and "sync_github" itself; connect,
// form changes and reconnect still go to the old component, which it draws
// beside the page only for someone who may connect a repository, so for
// anyone else nothing on the page takes them.
export async function sendGithubRequest(
  page: Page,
  lv: ReturnType<typeof watchLiveView>,
  kind: GithubRequest,
  form: GithubForm = {}
) {
  const fields = {
    github_installation_id: form.installation ?? '',
    repo: form.repo ?? '',
    branch: form.branch ?? '',
    sync_direction: form.direction === 'import' ? 'deploy' : 'pull',
    config_path: form.configPath ?? '',
    accept: 'true',
  };
  let target = '#github-sync-component';
  if (await isDesignSystem(page)) {
    if (kind === 'delete-connection' || kind === 'initiate-sync')
      return pushEvent(
        page,
        lv,
        kind === 'delete-connection'
          ? 'remove_github_connection'
          : 'sync_github',
        {}
      );
    target = '#project-settings-vcs-hosted [data-phx-component]';
    if ((await page.locator(target).count()) === 0) return;
  }
  const value =
    kind === 'reconnect'
      ? {
          connection: {
            sync_direction: fields.sync_direction,
            accept: 'true',
          },
        }
      : kind === 'save' || kind === 'validate'
        ? { connection: fields }
        : {};
  await pushEvent(page, lv, kind, value, target);
}
