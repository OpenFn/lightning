import {
  type ApiToken,
  TokensPage as DesignSystemTokensPage,
} from '@openfn/ui';
import { useState } from 'react';

import { designSystemPage } from '../page';

/** What TokensLive.Index puts in `data-props`. */
export interface Props {
  tokens: ApiToken[];
  /** The token whose delete modal is open; otherwise null. */
  tokenId: string | null;
}

/** The design system's personal access tokens page, fed by TokensLive.Index. */
export const TokensPage = designSystemPage(
  'TokensPage',
  DesignSystemTokensPage,
  ['/profile/tokens', '/profile/tokens/:id/delete'],
  ({ tokens, tokenId }: Props, { request, send, navigate }) => {
    // The new token arrives once, in the reply, never in props. As before,
    // the banner goes when the delete modal opens or closes.
    const [newToken, setNewToken] = useState<string | null>(null);
    const [shownFor, setShownFor] = useState(tokenId);
    if (tokenId !== shownFor) {
      setShownFor(tokenId);
      setNewToken(null);
    }

    return {
      tokens,
      tokenId,
      newToken,
      onGenerate: async () => {
        const { token } = await request<{ token: string }>(
          'generate_new_token'
        );
        setNewToken(token);
      },
      onDelete: (id: string) => send('delete_token', { id }),
      // After a delete the LiveView has already patched back to the list,
      // keeping its flash; patching again here would clear it.
      onClose: () => {
        if (window.location.pathname !== '/profile/tokens')
          navigate('/profile/tokens');
      },
    };
  }
);
