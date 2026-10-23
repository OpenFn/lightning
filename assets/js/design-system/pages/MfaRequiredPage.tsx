import { MfaRequiredPage as DesignSystemMfaRequiredPage } from '@openfn/ui';

import { designSystemPage } from '../page';

/** ProjectLive.MFARequired sends no props. */
export type Props = Record<string, never>;

/**
 * The design system's "MFA Required for Project" page, fed by
 * ProjectLive.MFARequired. It shows nothing from the server and has no
 * actions; its links lead to /profile, another LiveView, so they redirect.
 */
export const MfaRequiredPage = designSystemPage(
  'MfaRequiredPage',
  DesignSystemMfaRequiredPage,
  ['/mfa_required'],
  (_props: Props) => ({})
);
