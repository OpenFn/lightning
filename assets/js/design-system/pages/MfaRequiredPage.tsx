import DesignSystemMfaRequiredPage from '@openfn/ui/pages/projects/MfaRequiredPage.tsx';

import { designSystemPage } from '../page';

/**
 * The design system's "MFA Required for Project" page, fed by
 * ProjectLive.MFARequired. It shows nothing from the server and has no
 * actions; its links lead to /profile, another LiveView, so they redirect.
 */
export const MfaRequiredPage = designSystemPage(
  'MfaRequiredPage',
  DesignSystemMfaRequiredPage,
  ['/mfa_required'],
  () => ({})
);
