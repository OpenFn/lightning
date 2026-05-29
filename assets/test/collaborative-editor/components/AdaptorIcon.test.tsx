/**
 * Tests for AdaptorIcon component
 *
 * Verifies that icon URLs are read from the AdaptorStore (icon_urls.square)
 * with the existing first-letter placeholder fallback when no URL is present
 * or the adaptor is not in the store.
 */

import { render, screen } from '@testing-library/react';
import { describe, expect, it } from 'vitest';

import { AdaptorIcon } from '../../../js/collaborative-editor/components/AdaptorIcon';
import {
  StoreContext,
  type StoreContextValue,
} from '../../../js/collaborative-editor/contexts/StoreProvider';
import { createAdaptorStore } from '../../../js/collaborative-editor/stores/createAdaptorStore';
import type { Adaptor } from '../../../js/collaborative-editor/types/adaptor';

function renderWithAdaptors(ui: React.ReactElement, adaptors: Adaptor[]) {
  const adaptorStore = createAdaptorStore();
  adaptorStore.setAdaptors(adaptors);

  const stores = {
    adaptorStore,
    credentialStore: {} as StoreContextValue['credentialStore'],
    metadataStore: {} as StoreContextValue['metadataStore'],
    awarenessStore: {} as StoreContextValue['awarenessStore'],
    workflowStore: {} as StoreContextValue['workflowStore'],
    sessionContextStore: {} as StoreContextValue['sessionContextStore'],
    historyStore: {} as StoreContextValue['historyStore'],
    uiStore: {} as StoreContextValue['uiStore'],
    editorPreferencesStore: {} as StoreContextValue['editorPreferencesStore'],
    aiAssistantStore: {} as StoreContextValue['aiAssistantStore'],
  } satisfies StoreContextValue;

  return render(
    <StoreContext.Provider value={stores}>{ui}</StoreContext.Provider>
  );
}

describe('AdaptorIcon', () => {
  it('renders icon_urls.square as an <img> when populated in the store', () => {
    const url = '/adaptor-icons/salesforce/square-abc.png';
    renderWithAdaptors(
      <AdaptorIcon name="@openfn/language-salesforce@2.0.0" />,
      [
        {
          name: '@openfn/language-salesforce',
          versions: [{ version: '2.0.0' }],
          repo: 'https://example.com',
          latest: '2.0.0',
          icon_urls: { square: url, rectangle: null },
        },
      ]
    );

    const img = screen.getByAltText('salesforce');
    expect(img.tagName).toBe('IMG');
    expect(img.getAttribute('src')).toContain(url);
  });

  it('renders the first-letter placeholder when icon_urls.square is null', () => {
    renderWithAdaptors(
      <AdaptorIcon name="@openfn/language-salesforce@2.0.0" />,
      [
        {
          name: '@openfn/language-salesforce',
          versions: [{ version: '2.0.0' }],
          repo: 'https://example.com',
          latest: '2.0.0',
          icon_urls: { square: null, rectangle: '/some-rectangle.png' },
        },
      ]
    );

    expect(screen.queryByRole('img')).toBeNull();
    expect(screen.getByText('S')).toBeInTheDocument();
  });

  it('renders the first-letter placeholder when the adaptor is not in the store', () => {
    renderWithAdaptors(<AdaptorIcon name="@openfn/language-http@1.0.0" />, []);

    expect(screen.queryByRole('img')).toBeNull();
    expect(screen.getByText('H')).toBeInTheDocument();
  });
});
