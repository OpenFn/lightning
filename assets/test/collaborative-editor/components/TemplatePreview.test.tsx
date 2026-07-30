/**
 * TemplatePreview - static template graph rendering
 *
 * The YAML→state conversion itself is covered by `test/yaml/util.test.ts`;
 * this file asserts the component's own behavior: rendering the parsed
 * template's nodes through the shared workflow-diagram primitives, and the
 * graceful fallback when a template's code can't be parsed.
 */

import { render, screen } from '@testing-library/react';
import { describe, expect, test } from 'vitest';

import { TemplatePreview } from '#/collaborative-editor/components/TemplatePreview';
import { BASE_TEMPLATES } from '#/collaborative-editor/constants/baseTemplates';

describe('TemplatePreview', () => {
  test('renders the template graph with job and trigger nodes', async () => {
    const template = BASE_TEMPLATES[0]!; // Event-based workflow

    render(<TemplatePreview template={template} />);

    // Job node, rendered by the shared workflow-diagram Job node type
    expect(await screen.findByText('Transform data')).toBeInTheDocument();
    // Trigger node
    expect(screen.getByText(/webhook/i)).toBeInTheDocument();
  });

  test('shows a fallback when the template code cannot be parsed', () => {
    const template = {
      ...BASE_TEMPLATES[0]!,
      id: 'broken-template',
      code: 'edges:\n  nope->missing:\n    target_job: missing\n',
    };

    render(<TemplatePreview template={template} />);

    expect(
      screen.getByText('Preview unavailable for this template.')
    ).toBeInTheDocument();
  });
});
