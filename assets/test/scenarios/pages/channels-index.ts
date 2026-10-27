// Where today's channels page (HEEx) and the design-system one differ.
// Everything that knows how either version is built lives here, so a redesign
// of /projects/:id/channels only changes this file.
import { expect, type Dialog, type Locator, type Page } from '@playwright/test';

import { modal, modalTitle, pushEvent, type watchLiveView } from '../steps';

type LiveView = ReturnType<typeof watchLiveView>;

// Whether this is the design-system page rather than today's HEEx one
const isDesignSystem = async (page: Page) =>
  (await page.locator('[data-react-name="ChannelsIndexPage"]').count()) > 0;

// The row of the channel named <name>
export const channelRow = (page: Page, name: string) =>
  page.getByRole('row').filter({ has: page.getByText(name, { exact: true }) });

// The cell of <row> under the column headed <header>
export async function channelCell(page: Page, row: Locator, header: string) {
  const headers = (await page.getByRole('columnheader').allInnerTexts()).map(
    h => h.trim()
  );
  const column = headers.indexOf(header);
  expect(column, `a "${header}" column`).toBeGreaterThanOrEqual(0);
  return row.getByRole('cell').nth(column);
}

// A totals card, found by its title: the closest wrapper of the title that
// also holds a number. Today the number sits beside the title's own wrapper.
export const totalCard = (page: Page, title: string) =>
  page
    .locator('*', {
      has: page.getByRole('heading', { name: new RegExp(`^${title}$`, 'i') }),
    })
    .filter({ hasText: /\d/ })
    .last();

// The "New Channel" control. Today's page wraps the button in a link; the
// button is what both versions name.
export const newChannelButton = (page: Page) =>
  page.getByRole('button', { name: /^New Channel$/i });

// What takes the pointer for the disabled "New Channel" button: the wrapper
// around it, in both versions
export const newChannelTipTarget = (page: Page) =>
  newChannelButton(page).locator('xpath=..');

// A channel's "Edit" control. Today's page wraps the button in a link; the
// button is what both versions name.
export const editButton = (row: Locator) =>
  row.getByRole('button', { name: 'Edit', exact: true });

export const deleteButton = (row: Locator) =>
  row.getByRole('button', { name: 'Delete', exact: true });

// The proxy URL that copies on click, inside <within> (a row or the form).
// Today it is a div with a label but no role, so it has to be found by its
// copy hook; the design system draws it as a button.
export const proxyUrlCopy = (within: Locator) =>
  within
    .getByRole('button', { name: 'Copy proxy URL' })
    .or(within.locator('[phx-hook="Copy"][aria-label="Copy proxy URL"]'));

// A channel's on/off switch. Neither version gives it a name while the
// channel is on, so it is the switch in the channel's row.
export const channelSwitch = (row: Locator) => row.getByRole('switch');

// The form's destination credential select. Today's has no label, so it is
// the form's only select.
export const credentialSelect = (form: Locator) => form.getByRole('combobox');

// When I click "Delete" on <row> and confirm — resolves to what I was asked.
// Today the browser asks; the design system asks in a "Delete channel" dialog.
export async function deleteAndConfirm(page: Page, row: Locator) {
  let asked: string | undefined;
  const accept = (d: Dialog) => {
    asked = d.message();
    void d.accept();
  };
  page.once('dialog', accept);
  await deleteButton(row).click();
  const title = modalTitle(page, 'Delete channel');
  await expect
    .poll(async () => asked !== undefined || (await title.isVisible()))
    .toBe(true);
  if (asked !== undefined) return asked;
  page.off('dialog', accept);
  const dialog = modal(page, 'Delete channel');
  const question = await dialog.innerText();
  await dialog.getByRole('button', { name: 'Delete', exact: true }).click();
  return question;
}

// When the page receives a switch of channel <id> to <enabled>, as a tampered
// client would send it. Both versions send the same event.
export const sendToggle = (
  page: Page,
  lv: LiveView,
  id: string,
  enabled: boolean
) =>
  pushEvent(page, lv, 'toggle_channel_state', {
    channel_state: String(enabled),
    value_key: id,
  });

// When the page receives a delete of channel <id>, as a tampered client would
// send it. Both versions send the same event.
export const sendDelete = (page: Page, lv: LiveView, id: string) =>
  pushEvent(page, lv, 'delete_channel', { id });

export type ChannelSave = {
  name: string;
  destinationUrl: string;
  destinationCredentialId?: string;
  clientAuthMethodIds?: string[];
};

// When the open channel form's save arrives with these values, as a tampered
// client would send it, past the form's own lists. Today the form is a
// LiveView component with its own "save" event and form-shaped params; the
// design system sends "save_channel" to the page. <editing> is the channel
// being edited, or undefined on the new channel form.
export async function sendSave(
  page: Page,
  lv: LiveView,
  values: ChannelSave,
  editing?: string
) {
  const ids = values.clientAuthMethodIds ?? [];
  if (await isDesignSystem(page))
    await pushEvent(page, lv, 'save_channel', {
      name: values.name,
      enabled: true,
      destinationUrl: values.destinationUrl,
      destinationCredentialId: values.destinationCredentialId ?? '',
      clientAuthMethodIds: ids,
    });
  else
    await pushEvent(
      page,
      lv,
      'save',
      {
        channel: {
          name: values.name,
          enabled: 'true',
          destination_url: values.destinationUrl,
          destination_credential_id: values.destinationCredentialId ?? '',
          client_auth_methods: Object.fromEntries(ids.map(id => [id, 'true'])),
        },
      },
      `#channel-form-${editing ?? 'new'}`
    );
}
