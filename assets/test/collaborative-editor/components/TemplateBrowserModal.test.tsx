/**
 * TemplateBrowserModal - presentational rendering
 *
 * `TemplateBrowserModal` is props-driven with no store/context, so it's
 * rendered directly. Filtering itself (name/description/tag matching) is
 * covered by `utils/filterTemplates.test.ts`; this file only asserts the
 * component's own rendering decisions: grid-column sizing, the "no results"
 * message's visibility conditions, disabled state while saving, and the
 * loading state.
 */

import { act, render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { describe, expect, test, vi } from 'vitest';

import {
  TemplateBrowserModal,
  type TemplateBrowserModalProps,
} from '#/collaborative-editor/components/TemplateBrowserModal';
import type {
  BaseTemplate,
  Template,
  WorkflowTemplate,
} from '#/collaborative-editor/types/template';

let idCounter = 0;
function nextId(prefix: string) {
  idCounter += 1;
  return `${prefix}-${idCounter}`;
}

function makeBaseTemplate(overrides: Partial<BaseTemplate> = {}): BaseTemplate {
  return {
    id: nextId('base'),
    name: 'Base Template',
    description: '',
    code: '',
    tags: [],
    isBase: true,
    ...overrides,
  };
}

function makeUserTemplate(
  overrides: Partial<WorkflowTemplate> = {}
): WorkflowTemplate {
  return {
    id: nextId('user'),
    name: 'User Template',
    description: null,
    code: '',
    positions: null,
    tags: [],
    workflow_id: null,
    ...overrides,
  };
}

function makeBaseTemplates(count: number): BaseTemplate[] {
  return Array.from({ length: count }, (_, i) =>
    makeBaseTemplate({ name: `Base ${i}` })
  );
}

async function renderModal(overrides: Partial<TemplateBrowserModalProps> = {}) {
  const props: TemplateBrowserModalProps = {
    isOpen: true,
    onClose: vi.fn(),
    templates: [] as Template[],
    loading: false,
    isSaving: false,
    onSelect: vi.fn(),
    searchQuery: '',
    onSearchChange: vi.fn(),
    ...overrides,
  };
  const view = render(<TemplateBrowserModal {...props} />);
  // Headless UI's enter transition resolves on a later tick; flush it here
  // so it doesn't leak into the next test as an act() warning.
  await act(async () => {
    await new Promise(resolve => setTimeout(resolve, 0));
  });
  return view;
}

describe('TemplateBrowserModal', () => {
  describe('grid-column sizing', () => {
    test.each<[number, string, string]>([
      [0, 'max-w-lg', 'grid-cols-1'],
      [3, 'max-w-lg', 'grid-cols-1'],
      [4, 'max-w-2xl', 'grid-cols-2'],
      [6, 'max-w-2xl', 'grid-cols-2'],
      [7, 'max-w-[784px]', 'grid-cols-3'],
    ])(
      'with %i templates, panel gets "%s" and grid gets "%s"',
      async (count, panelClass, gridClass) => {
        const templates = makeBaseTemplates(count);
        await renderModal({ templates });

        // Headless UI renders the dialog into a portal appended to
        // document.body, so it lives outside render()'s `container`.
        const panel = document.querySelector('.shadow-2xl');
        const grid = document.querySelector('.gap-x-4');

        expect(panel?.className).toContain(panelClass);
        expect(grid?.className).toContain(gridClass);
      }
    );
  });

  describe('"no results" message', () => {
    test.each<[number, string | null]>([
      [1, null],
      [4, 'col-span-2'],
      [7, 'col-span-3'],
    ])(
      'shows the message when nothing matches, with col-span matching cols (baseCount=%i)',
      async (baseCount, expectedColSpan) => {
        const templates = [
          ...makeBaseTemplates(baseCount),
          makeUserTemplate({ name: 'User Item' }),
        ];
        await renderModal({ templates, searchQuery: 'zzznomatch' });

        const message = screen.getByText(
          'No saved templates match your search.'
        );
        if (expectedColSpan) {
          expect(message.className).toContain(expectedColSpan);
        } else {
          expect(message.className).not.toContain('col-span-2');
          expect(message.className).not.toContain('col-span-3');
        }
      }
    );

    test('hides the message when there are no user templates at all', async () => {
      const templates = makeBaseTemplates(2);
      await renderModal({ templates, searchQuery: 'zzznomatch' });

      expect(
        screen.queryByText('No saved templates match your search.')
      ).not.toBeInTheDocument();
    });

    test('hides the message when a user template matches the search', async () => {
      const templates = [
        makeBaseTemplate({ name: 'Base' }),
        makeUserTemplate({ name: 'Findme Template' }),
      ];
      await renderModal({ templates, searchQuery: 'findme' });

      expect(
        screen.queryByText('No saved templates match your search.')
      ).not.toBeInTheDocument();
    });

    test('hides the message when the search query is blank', async () => {
      const templates = [makeUserTemplate({ name: 'Only Template' })];
      await renderModal({ templates, searchQuery: '   ' });

      expect(
        screen.queryByText('No saved templates match your search.')
      ).not.toBeInTheDocument();
    });

    test('hides the message when a base template matches even though no user template does', async () => {
      const templates = [
        makeBaseTemplate({ name: 'Matching Base' }),
        makeUserTemplate({ name: 'Other' }),
      ];
      await renderModal({ templates, searchQuery: 'matching' });

      expect(
        screen.queryByText('No saved templates match your search.')
      ).not.toBeInTheDocument();
    });
  });

  describe('disabled-during-save card state', () => {
    test('disables every template card while isSaving is true', async () => {
      const templates = [
        makeBaseTemplate({ name: 'Alpha' }),
        makeUserTemplate({ name: 'Beta' }),
      ];
      await renderModal({ templates, isSaving: true });

      expect(screen.getByRole('button', { name: 'Alpha' })).toBeDisabled();
      expect(screen.getByRole('button', { name: 'Beta' })).toBeDisabled();
    });

    test('enables cards and calls onSelect with the clicked template when not saving', async () => {
      const user = userEvent.setup();
      const onSelect = vi.fn();
      const templates = [
        makeBaseTemplate({ name: 'Alpha' }),
        makeUserTemplate({ name: 'Beta' }),
      ];
      await renderModal({ templates, onSelect });

      const betaCard = screen.getByRole('button', { name: 'Beta' });
      expect(betaCard).toBeEnabled();

      await user.click(betaCard);

      expect(onSelect).toHaveBeenCalledExactlyOnceWith(templates[1]);
    });
  });

  describe('loading state', () => {
    test('shows a loading message, hides the grid, and disables the search input', async () => {
      const templates = [makeBaseTemplate({ name: 'Alpha' })];
      await renderModal({ templates, loading: true });

      expect(screen.getByText('Loading templates...')).toBeInTheDocument();
      expect(
        screen.queryByRole('button', { name: 'Alpha' })
      ).not.toBeInTheDocument();
      expect(
        screen.getByRole('textbox', { name: 'Search templates' })
      ).toBeDisabled();
    });
  });
});
