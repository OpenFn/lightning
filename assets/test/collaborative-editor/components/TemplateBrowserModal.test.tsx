/**
 * TemplateBrowserModal - presentational rendering
 *
 * `TemplateBrowserModal` is props-driven with no store/context, so it's
 * rendered directly. Filtering itself (name/description/tag matching) is
 * covered by `utils/filterTemplates.test.ts`; this file only asserts the
 * component's own rendering decisions: panel sizing, the "no results" message's
 * visibility conditions, which template the preview pane points at, disabled
 * state while saving, and the loading state.
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
  const flush = async () => {
    await act(async () => {
      await new Promise(resolve => setTimeout(resolve, 0));
    });
  };
  await flush();

  // The modal is fully props-driven, so state the parent owns — `searchQuery`
  // above all — only changes via a re-render from outside.
  const updateProps = async (next: Partial<TemplateBrowserModalProps>) => {
    view.rerender(<TemplateBrowserModal {...props} {...next} />);
    await flush();
  };

  return { ...view, updateProps };
}

describe('TemplateBrowserModal', () => {
  describe('panel sizing', () => {
    // The old responsive 1/2/3-column grid went away with the master-detail
    // layout: the list is always a single column beside the preview pane, so
    // the panel width no longer varies with template count.
    test.each<number>([0, 3, 7])(
      'panel is a fixed width regardless of template count (%i)',
      async count => {
        await renderModal({ templates: makeBaseTemplates(count) });

        // Headless UI renders the dialog into a portal appended to
        // document.body, so it lives outside render()'s `container`.
        const panel = document.querySelector('.shadow-2xl');

        expect(panel?.className).toContain('max-w-5xl');
      }
    );
  });

  describe('"no results" message', () => {
    test('shows the message when no user template matches', async () => {
      const templates = [
        ...makeBaseTemplates(2),
        makeUserTemplate({ name: 'User Item' }),
      ];
      await renderModal({ templates, searchQuery: 'zzznomatch' });

      expect(
        screen.getByText('No saved templates match your search.')
      ).toBeInTheDocument();
    });

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

  describe('preview selection', () => {
    test('previews the first template on open so the pane is never empty', async () => {
      const templates = [
        makeBaseTemplate({ name: 'Alpha' }),
        makeUserTemplate({ name: 'Beta' }),
      ];
      await renderModal({ templates });

      expect(screen.getByRole('button', { name: 'Alpha' })).toHaveAttribute(
        'aria-pressed',
        'true'
      );
      expect(screen.getByRole('button', { name: 'Beta' })).toHaveAttribute(
        'aria-pressed',
        'false'
      );
    });

    test('clicking a card previews it instead of creating a workflow', async () => {
      const user = userEvent.setup();
      const onSelect = vi.fn();
      const templates = [
        makeBaseTemplate({ name: 'Alpha' }),
        makeUserTemplate({ name: 'Beta' }),
      ];
      await renderModal({ templates, onSelect });

      await user.click(screen.getByRole('button', { name: 'Beta' }));

      expect(screen.getByRole('button', { name: 'Beta' })).toHaveAttribute(
        'aria-pressed',
        'true'
      );
      // The whole point of the preview: browsing is free of side effects.
      expect(onSelect).not.toHaveBeenCalled();
    });

    test('"Create" creates from the previewed template', async () => {
      const user = userEvent.setup();
      const onSelect = vi.fn();
      const templates = [
        makeBaseTemplate({ name: 'Alpha' }),
        makeUserTemplate({ name: 'Beta' }),
      ];
      await renderModal({ templates, onSelect });

      await user.click(screen.getByRole('button', { name: 'Beta' }));
      await user.click(screen.getByRole('button', { name: 'Create' }));

      expect(onSelect).toHaveBeenCalledExactlyOnceWith(templates[1]);
    });

    test('re-points the preview when a search hides the previewed template', async () => {
      const user = userEvent.setup();
      const onSelect = vi.fn();
      const templates = [
        makeBaseTemplate({ name: 'Alpha' }),
        makeUserTemplate({ name: 'Beta' }),
      ];
      const { updateProps } = await renderModal({ templates, onSelect });

      await user.click(screen.getByRole('button', { name: 'Beta' }));
      await updateProps({ searchQuery: 'zzznomatch' });

      expect(
        screen.queryByRole('button', { name: 'Beta' })
      ).not.toBeInTheDocument();
      expect(screen.getByRole('button', { name: 'Alpha' })).toHaveAttribute(
        'aria-pressed',
        'true'
      );

      // The real hazard: creating from a template the list no longer shows.
      await user.click(screen.getByRole('button', { name: 'Create' }));
      expect(onSelect).toHaveBeenCalledExactlyOnceWith(templates[0]);
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

    test('disables the create button while isSaving is true', async () => {
      const templates = [makeBaseTemplate({ name: 'Alpha' })];
      await renderModal({ templates, isSaving: true });

      expect(
        screen.getByRole('button', { name: 'Creating...' })
      ).toBeDisabled();
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
