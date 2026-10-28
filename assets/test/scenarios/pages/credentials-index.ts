// Where today's credentials page (HEEx) and the design-system one differ.
// Everything that knows how either version is built lives here, so a redesign
// of /credentials only changes this file. The project settings Credentials
// tab shows the same list and dialogs, so it can use these too.
import { expect, type Dialog, type Locator, type Page } from '@playwright/test';

import {
  expectTooltip,
  field,
  pushEvent,
  sendingValues,
  submit,
  submittingExtraField,
  type watchLiveView,
} from '../steps';

const escape = (text: string) => text.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

const caseless = (text: string) => new RegExp(`^\\s*${escape(text)}\\s*$`, 'i');

// The open dialog titled <title> (any case), once it shows. Ask its title
// whether it is open: the design system's dialog wrapper is 0x0. Today's
// title holds the dialog's "close" button, so its name ends in "close".
export async function dialog(page: Page, title: string | RegExp) {
  const name =
    typeof title === 'string'
      ? new RegExp(`^\\s*${escape(title)}(\\s+close)?\\s*$`, 'i')
      : title;
  await expect(
    page.getByRole('dialog').getByRole('heading', { name })
  ).toBeVisible();
  return page
    .getByRole('dialog')
    .filter({ has: page.getByRole('heading', { name }) });
}

// When I choose "Add new" then <item> ("Credential" or "OAuth client")
// On project settings today's menu sits in a header hidden from assistive
// tech, so hidden elements are searched too and the visible one is used.
export async function addNew(page: Page, item: 'Credential' | 'OAuth client') {
  await page
    .getByRole('button', { name: 'Add new', includeHidden: true })
    .filter({ visible: true })
    .click();
  // Today's "OAuth Client" item also reads "Advanced" (a badge)
  await page
    .getByRole('menuitem', {
      name: new RegExp(`^${item}`, 'i'),
      includeHidden: true,
    })
    .filter({ visible: true })
    .click();
}

// The row of the credential or OAuth client named <name>
export const row = (page: Page, name: string) =>
  page
    .getByRole('row')
    .filter({ has: page.getByRole('cell').getByText(name, { exact: true }) });

// Credential <of> lists environment <name>. Today the row shows a count with
// the names in its label; the design system shows them in a tooltip on the
// count.
export async function expectEnvironment(page: Page, of: Locator, name: string) {
  if (await isDesignSystem(page))
    await expectTooltip(page, of.getByText(/^\d+$/), name);
  else await expect(of).toHaveAccessibleName(new RegExp(escape(name)));
}

// The actions <row> offers, from its "Actions" menu; empty when it has none
export async function actionsOf(page: Page, of: Locator) {
  const button = of.getByRole('button', { name: 'Actions' });
  if (!(await button.count())) return [];
  await button.click();
  // Today's menu fades in after the click
  await expect(menuItems(page).first()).toBeVisible();
  const items = await menuItems(page).allInnerTexts();
  await page.keyboard.press('Escape');
  return items.map(i => i.trim());
}

// Today's menu items are links without an href, so they have no role; the
// design system's are menu items
const menuItems = (page: Page) =>
  page
    .getByRole('menu')
    .locator('[role="menuitem"], a')
    .filter({ visible: true });

// When I choose <action> ("Edit", "Delete", "Transfer", "Revoke transfer",
// "Cancel deletion", "Delete now") from <row>'s "Actions" menu
export async function rowAction(page: Page, of: Locator, action: string) {
  await of.getByRole('button', { name: 'Actions' }).click();
  await menuItems(page)
    .filter({ hasText: caseless(action) })
    .click();
}

// When I start a new credential of type <type> ("Raw JSON", an adaptor such
// as "dhis2", or an OAuth client's name) and continue to its form
export async function startCredential(page: Page, type: string) {
  await addNew(page, 'Credential');
  const picker = await dialog(page, 'Add a credential');
  await typeOption(picker, type).check();
  await picker.getByRole('button', { name: 'Configure credential' }).click();
  return dialog(page, /^\s*Create .* credential(\s+close)?\s*$/i);
}

// The type picker's option <type>, any case
export const typeOption = (picker: Locator, type: string) =>
  picker.getByRole('radio', { name: caseless(type) });

// When I give the project <name> access in the open form
export async function addProject(form: Locator, name: string) {
  await form
    .getByRole('combobox')
    .filter({
      has: form.page().getByRole('option', { name: /^Grant projects access/ }),
    })
    .selectOption({ label: name });
  await expect(projectChip(form, name)).toBeVisible();
}

// The chip of project <name> in the open form's project picker
export const projectChip = (form: Locator, name: string) =>
  removeProjectButton(form, name).locator('xpath=..');

// Today the button is named "Remove" inside the chip; the design system names
// it "Remove <name>"
const removeProjectButton = (form: Locator, name: string) =>
  form
    .getByRole('button', { name: `Remove ${name}`, exact: true })
    .or(
      form
        .locator('span', { hasText: name })
        .getByRole('button', { name: 'Remove', exact: true })
    )
    .first();

// When I remove project <name> in the open form — resolves to the warning I
// was asked to confirm, if any. Today the browser asks; the design system
// asks in a "Revoke project access" dialog, which hides the form while open.
export async function removeProject(form: Locator, name: string) {
  const page = form.page();
  let asked: string | undefined;
  const accept = (d: Dialog) => {
    asked = d.message();
    void d.accept();
  };
  page.once('dialog', accept);
  await removeProjectButton(form, name).click();
  const title = /revoke project access/i;
  const revoke = page
    .getByRole('dialog')
    .filter({ has: page.getByRole('heading', { name: title }) });
  // The design system's dialog wrapper is 0x0: ask its title whether it shows
  const shows = (d: Locator) => d.getByRole('heading').first().isVisible();
  await expect
    .poll(
      async () =>
        asked !== undefined ||
        (await shows(revoke)) ||
        ((await shows(form)) &&
          !(await removeProjectButton(form, name).count()))
    )
    .toBe(true);
  page.off('dialog', accept);
  if (asked !== undefined || !(await shows(revoke))) return asked;
  const question = await revoke.innerText();
  await revoke.getByRole('button', { name: /revoke access/i }).click();
  return question;
}

// The tab of environment <name> in the open form. Today they are plain buttons.
export const environmentTab = (form: Locator, name: string) =>
  form
    .getByRole('tab', { name, exact: true })
    .or(form.getByRole('button', { name, exact: true }))
    .first();

// The add environment button. Today it is an icon with its name on a wrapper,
// so it is found by the id both versions give it.
export const addEnvironmentButton = (form: Locator) =>
  form.locator('#add-environment-button');

// What the add environment button says it does (today on its wrapper)
export const addEnvironmentLabel = (form: Locator, text: string) =>
  form.getByLabel(text, { exact: true }).first();

// When I open environment <name>, once the form shows it. Today the delete
// button names the open environment only after the server answers the click.
export async function openEnvironment(form: Locator, name: string) {
  await environmentTab(form, name).click();
  await expect(field(form, 'Environment name')).toHaveValue(name);
}

// When I rename the open environment to <name>
export async function renameEnvironment(form: Locator, name: string) {
  const input = field(form, 'Environment name');
  await input.fill(name);
  await input.blur();
}

// When I delete the open environment and confirm. Today the browser asks; the
// design system asks in a "Delete environment" dialog.
export async function deleteEnvironment(form: Locator) {
  const page = form.page();
  page.once('dialog', d => void d.accept());
  await form.getByRole('button', { name: 'Delete environment' }).click();
  if (await isDesignSystem(page))
    await (await dialog(page, 'Delete environment'))
      .getByRole('button', { name: 'Delete', exact: true })
      .click();
}

// When I enter <json> as the open environment's raw body
export const enterBody = (form: Locator, json: string) =>
  field(form, 'Credential Body').fill(json);

// When I save the credential form
export const saveCredential = (form: Locator) =>
  submit(form, 'Save Credential');

// The transfer form's email box. Today it has no label, only a placeholder.
export const receiverEmail = (form: Locator) =>
  form.getByPlaceholder('email@example.com');

// When I type <scopes> (comma separated) into the OAuth client field <label>
// one by one, waiting for each to become a chip
export async function addScopes(
  form: Locator,
  label: string,
  scopes: string[]
) {
  for (const scope of scopes) {
    const input = field(form, label);
    await input.fill(`${scope},`);
    // Today's chip also holds a hidden "Remove"
    await expect(
      form.getByText(new RegExp(`^\\s*${escape(scope)}(\\s*Remove)?\\s*$`))
    ).toBeVisible();
  }
}

// The OAuth client form's "Make client global" checkbox
export const globalCheckbox = (form: Locator) =>
  form.getByRole('checkbox', { name: /^Make client global/ });

// The scope checkbox <scope> on an OAuth credential's form
export const scopeCheckbox = (form: Locator, scope: string) =>
  form.getByRole('checkbox', { name: scope, exact: true });

// When I click <control> as a tampered client would, naming credential or
// OAuth client <id> instead of the one the page meant. Both versions send
// the item as `id`. Call it before the page opens; it returns the click step.
export const namingAnother = (page: Page, id: string) =>
  sendingValues(page, { id });

// When I save the OAuth client form as a tampered client would, with
// "global" set to true. Call it before the page opens; it returns the click
// step.
export const sendingGlobal = (page: Page) =>
  submittingExtraField(page, 'global', 'true');

// The projects the open form offers to share with
export const projectOptions = (form: Locator) =>
  form
    .getByRole('combobox')
    .filter({
      has: form.page().getByRole('option', { name: /^Grant projects access/ }),
    })
    .getByRole('option')
    .allInnerTexts()
    .then(names => names.map(n => n.trim()));

// Whether this is a design-system page rather than today's HEEx one (the
// project settings Credentials tab shows the same list)
const isDesignSystem = async (page: Page) =>
  (await page
    .locator(
      '[data-react-name="CredentialsIndexPage"], [data-react-name="ProjectSettingsPage"]'
    )
    .count()) > 0;

// When a "delete now" for credential <id> reaches the server although the
// page offers none: today's deletion modal takes "delete" with the id, the
// design-system page "delete_credential" with the id and now: true
export async function forceDeleteNow(
  page: Page,
  lv: ReturnType<typeof watchLiveView>,
  id: string
) {
  if (await isDesignSystem(page))
    await pushEvent(page, lv, 'delete_credential', { id, now: true });
  else await pushEvent(page, lv, 'delete', { id }, `#delete-credential-${id}`);
}
