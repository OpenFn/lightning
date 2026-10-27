// Where today's first setup form (HEEx) and the design-system one differ.
// Everything that knows how either version is built lives here, so a
// redesign of /first_setup only changes this file.
import type { Page } from '@playwright/test';

import { pushEvent, type watchLiveView } from '../steps';

type LiveView = ReturnType<typeof watchLiveView>;

// Whether this is the design-system page rather than today's HEEx one
const isDesignSystem = async (page: Page) =>
  (await page.locator('[data-react-name="FirstSetupPage"]').count()) > 0;

export type SetupValues = {
  firstName: string;
  lastName: string;
  email: string;
  password: string;
  passwordConfirmation: string;
};

// When the form's save arrives with these values, as a tampered client would
// send it, past the form's own checks. Today the form sends "save" with
// form-shaped params; the design system sends "save" with camelCase values.
export async function sendSave(page: Page, lv: LiveView, values: SetupValues) {
  if (await isDesignSystem(page))
    await pushEvent(page, lv, 'save', { ...values });
  else
    await pushEvent(page, lv, 'save', {
      superuser_registration: {
        first_name: values.firstName,
        last_name: values.lastName,
        email: values.email,
        password: values.password,
        password_confirmation: values.passwordConfirmation,
      },
    });
}

// When a live navigation takes me to <path>: the page's LiveView moves there
// over its socket, as a link inside the app would, with no full page load.
export async function liveNavigate(page: Page, path: string) {
  await page.locator('[data-phx-main]').evaluate(
    (el, js) =>
      (
        window as unknown as {
          liveSocket: { execJS(el: Element, js: string): void };
        }
      ).liveSocket.execJS(el, js),
    JSON.stringify([['navigate', { href: path, replace: false }]])
  );
}
