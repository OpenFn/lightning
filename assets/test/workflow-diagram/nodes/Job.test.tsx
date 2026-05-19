/**
 * Job Node Component Tests
 *
 * Verifies that job nodes read their adaptor icons from the AdaptorStore
 * via useAdaptorIconUrl, with graceful string-label fallback when the URL
 * is null OR no StoreProvider is mounted (LiveView workflow-editor path).
 */

import { render } from '@testing-library/react';
import { ReactFlowProvider } from '@xyflow/react';
import { describe, expect, test } from 'vitest';

import {
  StoreContext,
  type StoreContextValue,
} from '../../../js/collaborative-editor/contexts/StoreProvider';
import { createAdaptorStore } from '../../../js/collaborative-editor/stores/createAdaptorStore';
import type { Adaptor } from '../../../js/collaborative-editor/types/adaptor';
import JobNode from '../../../js/workflow-diagram/nodes/Job';

function renderJob(adaptor: string, adaptors: Adaptor[] | null) {
  const data = { name: 'My Job', adaptor };

  const tree = (
    <ReactFlowProvider>
      <JobNode id="job-1" data={data} selected={false} />
    </ReactFlowProvider>
  );

  if (adaptors === null) {
    return render(tree);
  }

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
    <StoreContext.Provider value={stores}>{tree}</StoreContext.Provider>
  );
}

describe('JobNode - adaptor icon', () => {
  test('renders an <img> with icon_urls.square when the adaptor is seeded', () => {
    const url = '/adaptor-icons/http/square-deadbeef.png';
    const { container } = renderJob('@openfn/language-http@1.0.0', [
      {
        name: '@openfn/language-http',
        versions: [{ version: '1.0.0' }],
        repo: 'https://example.com',
        latest: '1.0.0',
        icon_urls: { square: url, rectangle: null },
      },
    ]);

    const img = container.querySelector('img');
    expect(img).not.toBeNull();
    expect(img?.getAttribute('src')).toContain(url);
    expect(img?.getAttribute('alt')).toBe('http');
  });

  test('falls back to the adaptor string label when icon_urls.square is null', () => {
    const { container } = renderJob('@openfn/language-http@1.0.0', [
      {
        name: '@openfn/language-http',
        versions: [{ version: '1.0.0' }],
        repo: 'https://example.com',
        latest: '1.0.0',
        icon_urls: { square: null, rectangle: '/rect.png' },
      },
    ]);

    expect(container.querySelector('img')).toBeNull();
    expect(container.textContent).toContain('http');
  });

  test('does not throw and falls back to label when no StoreProvider is mounted', () => {
    const { container } = renderJob('@openfn/language-http@1.0.0', null);

    expect(container.querySelector('img')).toBeNull();
    expect(container.textContent).toContain('http');
  });
});
