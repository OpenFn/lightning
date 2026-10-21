import DesignSystemBackupCodesPage from '@openfn/ui/pages/profile/BackupCodesPage.tsx';
import type { BackupCode } from '@openfn/ui/types/tokens.ts';

import { designSystemPage } from '../page';

/** What BackupCodesLive.Index puts in `data-props`. */
interface Props {
  codes: BackupCode[];
  mfaEnabled: boolean;
}

/** The design system's recovery codes page, fed by BackupCodesLive.Index. */
export const BackupCodesPage = designSystemPage(
  'BackupCodesPage',
  DesignSystemBackupCodesPage,
  ['/profile/auth/backup_codes'],
  (props: Props, { send }) => ({
    ...props,
    onRegenerate: () => send('regenerate-backup-codes'),
    // The printable copy is a controller page; it opens in a new tab as before.
    onPrint: () => {
      window.open('/profile/auth/backup_codes/print', '_blank');
    },
  })
);
