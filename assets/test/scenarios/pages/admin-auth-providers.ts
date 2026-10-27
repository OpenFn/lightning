// Where today's SSO provider page (HEEx) and the design-system one differ.
// Everything that knows how either version is built lives here, so a
// redesign of /settings/authentication only changes this file.
import type { Page } from '@playwright/test';

import { pushEvent, type watchLiveView } from '../steps';

type LiveView = ReturnType<typeof watchLiveView>;

// Whether this is the design-system page rather than today's HEEx one
const isDesignSystem = async (page: Page) =>
  (await page.locator('[data-react-name="AdminAuthProvidersPage"]').count()) >
  0;

export type ProviderValues = {
  name: string;
  discoveryUrl: string;
  clientId: string;
  clientSecret: string;
  redirectHost: string;
};

// When the provider form's save arrives with these values, as a tampered
// client would send it, past the form's own checks. Today the form is a
// LiveView component with its own "save" event and form-shaped params; the
// design system sends "save_provider" to the page.
export async function sendSave(
  page: Page,
  lv: LiveView,
  values: ProviderValues
) {
  if (await isDesignSystem(page))
    await pushEvent(page, lv, 'save_provider', {
      ...values,
      allowUnverifiedEmail: false,
    });
  else
    await pushEvent(
      page,
      lv,
      'save',
      {
        auth_provider: {
          name: values.name,
          discovery_url: values.discoveryUrl,
          client_id: values.clientId,
          client_secret: values.clientSecret,
          redirect_host: values.redirectHost,
          allow_unverified_email: 'false',
        },
      },
      '#auth-provider-form'
    );
}
