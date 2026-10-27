// Where today's admin user form (HEEx) and the design-system one differ.
// Everything that knows how either version is built lives here, so a
// redesign of /settings/users/new and /settings/users/:id only changes this
// file.
import type { Page } from '@playwright/test';

import { pushEvent, type watchLiveView } from '../steps';

type LiveView = ReturnType<typeof watchLiveView>;

// Whether this is the design-system page rather than today's HEEx one
const isDesignSystem = async (page: Page) =>
  (await page.locator('[data-react-name="AdminUserEditPage"]').count()) > 0;

// The "Support User" switch. The design system names it. Today's switch has
// no accessible name: its label text names the hidden checkbox under it, so
// the fallback finds the switch inside that label.
export const supportSwitch = (page: Page) =>
  page
    .getByRole('switch', { name: 'Support User' })
    .or(
      page
        .locator('label')
        .filter({ hasText: 'Support User' })
        .getByRole('switch')
    );

// The "Disabled?" checkbox, labelled by its hint. Today's checkbox renders no
// label text and sits before that hint, unlinked; the design system labels it
// with the hint. Same lookup as disableAccountAsAdmin in steps.ts.
const DISABLED_HINT = 'A disabled user will not be allowed to login.';
export const disabledCheckbox = (page: Page) =>
  page
    .getByRole('checkbox', { name: DISABLED_HINT })
    .or(
      page
        .getByText(DISABLED_HINT)
        .locator('xpath=preceding::input[@type="checkbox"][1]')
    );

export type UserValues = {
  firstName: string;
  lastName: string;
  email: string;
  password: string;
  role: 'user' | 'superuser';
};

// When the form's save arrives with these values, as a tampered client would
// send it, past the form's own checks. Today the form is a LiveView component
// with its own "save" event and form-shaped params; the design system sends
// "save_user" to the page.
export async function sendSave(page: Page, lv: LiveView, values: UserValues) {
  if (await isDesignSystem(page))
    await pushEvent(page, lv, 'save_user', { ...values, supportUser: false });
  else
    await pushEvent(
      page,
      lv,
      'save',
      {
        user: {
          first_name: values.firstName,
          last_name: values.lastName,
          email: values.email,
          password: values.password,
          role: values.role,
          support_user: 'false',
        },
      },
      '#user-form'
    );
}
