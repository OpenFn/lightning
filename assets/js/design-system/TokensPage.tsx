import { ToastProvider } from '@openfn/ui/components/Toast.tsx';
import DesignSystemTokensPage from '@openfn/ui/pages/profile/TokensPage.tsx';
import type { ApiToken } from '@openfn/ui/types/tokens.ts';
import { RequestError } from '@openfn/ui/utils/errors.ts';

/**
 * The design system's personal access tokens page, fed by TokensLive.Index.
 *
 * Mounted via `phx-hook="ReactComponent"`, so props arrive as the element's
 * raw kebab-case `data-*` attributes and are always strings. The LiveView
 * owns the data; the page's actions become LiveView events.
 */

interface TokensPageProps {
  'data-tokens': string;
  'data-new-token'?: string;
  'data-token-id'?: string;
  pushEvent: (
    name: string,
    payload?: Record<string, unknown>
  ) => Promise<unknown>;
  navigate: (path: string) => void;
}

export const TokensPage = ({
  'data-tokens': tokens,
  'data-new-token': newToken,
  'data-token-id': tokenId,
  pushEvent,
  navigate,
}: TokensPageProps) => {
  // The LiveView replies with { error } when an action fails.
  const send = async (name: string, payload: Record<string, unknown> = {}) => {
    const reply = (await pushEvent(name, payload)) as
      | { error?: string }
      | undefined;
    if (reply?.error) throw new RequestError(reply.error);
  };

  return (
    <ToastProvider>
      <DesignSystemTokensPage
        tokens={JSON.parse(tokens) as ApiToken[]}
        newToken={newToken ?? null}
        tokenId={tokenId ?? null}
        onGenerate={() => send('generate_new_token')}
        onDelete={id => send('delete_token', { id })}
        onClose={() => navigate('/profile/tokens')}
      />
    </ToastProvider>
  );
};
