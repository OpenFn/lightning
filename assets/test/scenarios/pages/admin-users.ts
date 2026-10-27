// Where today's users admin page (HEEx) and the design-system one differ.
// Everything that knows how either version is built lives here, so a redesign
// of /settings/users only changes this file.
import { expect, type Locator, type Page } from '@playwright/test';

import { pushEvent, type watchLiveView } from '../steps';

// Whether this is the design-system page rather than today's HEEx one
const isDesignSystem = async (page: Page) =>
  (await page.locator('#admin-users-page').count()) > 0;

// When I open the "Actions" menu for "<email>" — returns the open menu
export async function openActions(page: Page, email: string) {
  await page
    .getByRole('row')
    .filter({ hasText: email })
    .getByRole('button', { name: 'Actions' })
    .click();
  const menu = page.getByRole('menu');
  await expect(menu).toBeVisible();
  return menu;
}

// An item of an open "Actions" menu: today a link, on the design system a
// menu item
export const menuAction = (menu: Locator, name: string) =>
  menu
    .getByRole('link', { name, exact: true })
    .or(menu.getByRole('menuitem', { name, exact: true }));

// Then I see <name> in the menu, but it does nothing: today plain text, on the
// design system a disabled menu item
export async function expectInert(menu: Locator, name: string) {
  await expect(menu.getByText(name, { exact: true })).toBeVisible();
  const action = menuAction(menu, name);
  if (await action.count()) await expect(action).toBeDisabled();
  await expect(menu.getByRole('link', { name, exact: true })).toHaveCount(0);
}

// The filter box's clear button. Today it is an icon link with no name; the
// id is the only thing that tells it apart. Only today's page renders it.
export const clearFilterButton = (page: Page) =>
  page
    .getByRole('button', { name: 'Clear search' })
    .or(page.locator('#clear_filter_button'));

// Whether a table cell shows its tick. The tick is an icon with no text or
// accessible name in either version, so "something is drawn in the cell" is
// all a test can ask.
export const tick = (cell: Locator) => cell.locator('*').first();

// When the deletion dialog's confirm arrives with <email>, as a tampered
// client would send it, past the dialog's own check of the email. Today the
// dialog is a LiveView component with its own "delete" event; the design
// system sends "delete_user" to the page.
export async function sendDeletion(
  page: Page,
  lv: ReturnType<typeof watchLiveView>,
  email: string
) {
  if (await isDesignSystem(page))
    await pushEvent(page, lv, 'delete_user', { email });
  else
    await pushEvent(
      page,
      lv,
      'delete',
      { user: { scheduled_deletion_email: email } },
      '#scheduled_deletion_form'
    );
}
