import {
  BackupCodesPage as DesignSystemBackupCodesPage,
  type BackupCodesPageProps,
} from '@openfn/ui';

import { designSystemPage } from '../page';

/** What BackupCodesLive.Index puts in `data-props`. */
export type Props = Omit<BackupCodesPageProps, 'onRegenerate' | 'onPrint'>;

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
