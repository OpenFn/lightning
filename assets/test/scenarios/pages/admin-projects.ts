// Where today's projects admin page (HEEx) and the design-system one differ.
// Everything that knows how either version is built lives here, so a redesign
// of /settings/projects only changes this file.
import { expect, type Page } from '@playwright/test';

import { clickable, pushEvent, type watchLiveView } from '../steps';

// The row "Actions" menu and the filter's clear button are drawn the same way
// as on the users admin page, in both versions. Split them out if one page
// changes.
export { clearFilterButton, menuAction, openActions } from './admin-users';

// The "New Project" control. Today's page wraps a button in the link, so the
// name finds both; either one opens the form.
export const newProjectButton = (page: Page) =>
  clickable(page, 'New Project').first();

// Whether this is the design-system page rather than today's HEEx one
const isDesignSystem = async (page: Page) =>
  (await page.locator('[data-react-name="AdminProjectsPage"]').count()) > 0;

export type MemberRole = '' | 'owner' | 'admin' | 'editor' | 'viewer';

// The member table's column for each role
const COLUMN: Record<MemberRole, string> = {
  '': 'NO ACCESS',
  owner: 'OWNER',
  admin: 'ADMIN',
  editor: 'EDITOR',
  viewer: 'VIEWER',
};

// When I set "<email>" to <role> in the project form ('' is "No access").
// Today's radios have no accessible name, so the radio is the one in the
// role's column of that user's row.
export async function setRole(page: Page, email: string, role: MemberRole) {
  const headers = (await page.getByRole('columnheader').allInnerTexts()).map(
    h => h.trim().toUpperCase()
  );
  const column = headers.indexOf(COLUMN[role]);
  expect(column, `a "${COLUMN[role]}" column`).toBeGreaterThanOrEqual(0);
  const radio = page
    .getByRole('row')
    .filter({ hasText: email })
    .getByRole('cell')
    .nth(column)
    .getByRole('radio');
  await radio.check();
  await expect(radio).toBeChecked();
}

// When the project form's save arrives with <rawName> and no members, as a
// tampered client would send it, past the form's own check. Today the form
// is a LiveView component with its own "save" event; the design system sends
// "save_project" to the page.
export async function sendSaveWithoutMembers(
  page: Page,
  lv: ReturnType<typeof watchLiveView>,
  rawName: string
) {
  if (await isDesignSystem(page))
    await pushEvent(page, lv, 'save_project', { rawName, roles: {} });
  else
    await pushEvent(
      page,
      lv,
      'save',
      { project: { raw_name: rawName, project_users: {} } },
      '#project-form'
    );
}

// When the deletion dialog's confirm arrives with <typed> as the name, past
// the dialog's own check. Today the dialog is a LiveView component with its
// own "delete" event; the design system sends "delete_project" to the page.
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
