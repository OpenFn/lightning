// Where today's profile page (HEEx) and the design-system one differ, for the
// MFA, GitHub and delete account parts. Everything that knows how either
// version is built lives here, so a redesign of /profile only changes this
// file.
import { expect, type Locator, type Page } from '@playwright/test';

import { field, pushEvent, type watchLiveView } from '../steps';

import { dialog } from './credentials-index';

export { dialog };

// The "Enable multi-factor authentication" switch
export const mfaSwitch = (page: Page) =>
  page.getByRole('switch', { name: 'Enable multi-factor authentication' });

// "Setup another device instead". Today it is a link that opens setup in
// place.
export const setupAnotherDevice = (page: Page) =>
  page
    .getByRole('button', { name: 'Setup another device instead' })
    .or(page.getByRole('link', { name: 'Setup another device instead' }));

// The QR code an authenticator app scans. Today it is an unlabelled SVG
// drawn under "Scan the QR code"; it has no role or name to find it by.
export const qrCode = (page: Page) =>
  page
    .getByRole('img', { name: /QR code/i })
    .or(
      page
        .getByRole('heading', { name: 'Scan the QR code' })
        .locator('xpath=following::*[local-name()="svg"][1]')
    );

// When I click "this secret key" — returns the secret it shows, and closes it
export async function secretKey(page: Page) {
  await page
    .getByRole('link', { name: 'this secret key' })
    .or(page.getByRole('button', { name: 'this secret key' }))
    .click();
  const shown = await dialog(page, 'Your two-factor secret');
  const secret = (await shown.getByRole('code').innerText()).trim();
  // Escape is unreliable here: pressed during the open transition, the dialog
  // stays up and blocks the form.
  await shown
    .getByRole('button', { name: /^close$/i })
    .first()
    .click();
  await expect(shown).toHaveCount(0);
  return secret;
}

// When I enter <code> in "Verify the code from the app" and click "Save".
// Today the page has several "Save" buttons and none is tied to the code's
// form by anything visible, so Enter submits it.
export async function saveCode(page: Page, code: string) {
  const input = field(page, 'Verify the code from the app');
  await input.fill(code);
  await input.press('Enter');
}

// The "Connect" or "Reconnect" GitHub link. Today an expired token's link is
// named by its tooltip ("Your token has expired"), so find it by its text.
export const githubLink = (page: Page, verb: 'Connect' | 'Reconnect') =>
  page
    .getByRole('link')
    .or(page.getByRole('button'))
    .filter({ hasText: `${verb} your GitHub Account` });

// Then <link> tells me "<hint>": today as the link's label (a tooltip on
// hover), on a rebuild perhaps as a tooltip that opens on hover
export async function expectHint(page: Page, link: Locator, hint: string) {
  await link.hover();
  await expect(
    page
      .getByRole('tooltip')
      .filter({ hasText: hint })
      .or(link.and(page.getByLabel(hint, { exact: true })))
      .first()
  ).toBeVisible();
}

// When I click <link> — answers for GitHub with a stand-in page and returns
// the address GitHub was asked for. Today the link opens a new tab.
export async function followToGithub(page: Page, link: Locator) {
  await page
    .context()
    .route('https://github.com/**', route =>
      route.fulfill({ body: 'GitHub stand-in', contentType: 'text/html' })
    );
  const tab = page
    .context()
    .waitForEvent('page', { timeout: 5000 })
    .catch(() => page);
  await link.click();
  const at = await tab;
  await at.waitForURL(/^https:\/\/github\.com\//);
  return new URL(at.url());
}

// Whether this is the design-system page rather than today's HEEx one
const isDesignSystem = async (page: Page) =>
  (await page.locator('[data-react-name="ProfilePage"]').count()) > 0;

// When the delete account dialog's confirm arrives with <email>, past the
// dialog's own check of the email. Today the dialog is a LiveView component
// with its own "delete" event; the design system sends "delete_account" to
// the page.
export async function sendDeletion(
  page: Page,
  lv: ReturnType<typeof watchLiveView>,
  email: string
) {
  if (await isDesignSystem(page))
    await pushEvent(page, lv, 'delete_account', { email });
  else
    await pushEvent(
      page,
      lv,
      'delete',
      { user: { scheduled_deletion_email: email } },
      '#scheduled_deletion_form'
    );
}
