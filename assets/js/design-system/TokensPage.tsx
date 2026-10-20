import { ToastProvider } from '@openfn/ui/components/Toast.tsx';
import DesignSystemTokensPage from '@openfn/ui/pages/profile/TokensPage.tsx';
import type { ApiToken } from '@openfn/ui/types/tokens.ts';

/**
 * The design system's personal access tokens page, fed by TokensLive.Index.
 *
 * Mounted via `phx-hook="ReactComponent"`, so props arrive as the element's
 * raw kebab-case `data-*` attributes and are always strings.
 *
 * Display only: Generate and Delete don't reach the LiveView yet.
 */

interface TokensPageProps {
  'data-tokens': string;
}

const doNothing = () => Promise.resolve();

export const TokensPage = ({ 'data-tokens': tokens }: TokensPageProps) => (
  <ToastProvider>
    <DesignSystemTokensPage
      tokens={JSON.parse(tokens) as ApiToken[]}
      newToken={null}
      tokenId={null}
      onGenerate={doNothing}
      onDelete={doNothing}
      onClose={() => {}}
    />
  </ToastProvider>
);
