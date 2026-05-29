/**
 * MiniMapNode Component Tests
 *
 * Verifies that the minimap renders job icons sourced from the AdaptorStore
 * via useAdaptorIconUrl, with the rect-only placeholder fallback when the
 * URL is null. Trigger rendering must remain untouched.
 */

import { render } from '@testing-library/react';
import type { MiniMapNodeProps } from '@xyflow/react';
import { describe, expect, test } from 'vitest';

import {
  StoreContext,
  type StoreContextValue,
} from '../../../js/collaborative-editor/contexts/StoreProvider';
import { createAdaptorStore } from '../../../js/collaborative-editor/stores/createAdaptorStore';
import type { Adaptor } from '../../../js/collaborative-editor/types/adaptor';
import MiniMapNode from '../../../js/workflow-diagram/components/MiniMapNode';

type Job = { id: string; adaptor?: string };
type Trigger = { id: string; type: 'webhook' | 'cron' | 'kafka' };

function renderInSvg(
  nodeProps: MiniMapNodeProps,
  jobs: Job[],
  triggers: Trigger[],
  adaptors: Adaptor[]
) {
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
    <StoreContext.Provider value={stores}>
      <svg>
        <MiniMapNode {...nodeProps} jobs={jobs} triggers={triggers} />
      </svg>
    </StoreContext.Provider>
  );
}

describe('MiniMapNode - job icon', () => {
  const baseNodeProps: MiniMapNodeProps = {
    x: 0,
    y: 0,
    width: 120,
    height: 120,
    selected: false,
    borderRadius: 0,
    className: '',
    shapeRendering: 'auto',
  };

  test('renders an <image href> when the adaptor is seeded with icon_urls.square', () => {
    const url = '/adaptor-icons/http/square-1.png';
    const { container } = renderInSvg(
      { ...baseNodeProps, id: 'job-1' },
      [{ id: 'job-1', adaptor: '@openfn/language-http@1.0.0' }],
      [],
      [
        {
          name: '@openfn/language-http',
          versions: [{ version: '1.0.0' }],
          repo: 'https://example.com',
          latest: '1.0.0',
          icon_urls: { square: url, rectangle: null },
        },
      ]
    );

    const image = container.querySelector('image');
    expect(image).not.toBeNull();
    expect(image!.getAttribute('href')).toBe(url);
  });

  test('renders no <image> when icon_urls.square is null', () => {
    const { container } = renderInSvg(
      { ...baseNodeProps, id: 'job-1' },
      [{ id: 'job-1', adaptor: '@openfn/language-http@1.0.0' }],
      [],
      [
        {
          name: '@openfn/language-http',
          versions: [{ version: '1.0.0' }],
          repo: 'https://example.com',
          latest: '1.0.0',
          icon_urls: { square: null, rectangle: null },
        },
      ]
    );

    expect(container.querySelector('image')).toBeNull();
    expect(container.querySelector('rect')).not.toBeNull();
  });

  test('webhook trigger still renders the GlobeAltIcon (regression guard)', () => {
    const { container } = renderInSvg(
      { ...baseNodeProps, id: 'trigger-1' },
      [],
      [{ id: 'trigger-1', type: 'webhook' }],
      []
    );

    // GlobeAltIcon renders an svg inside a foreignObject for triggers
    expect(container.querySelector('foreignObject svg')).not.toBeNull();
  });
});
