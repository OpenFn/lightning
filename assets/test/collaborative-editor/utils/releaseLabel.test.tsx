/**
 * releaseActionLabel Tests
 *
 * One label set shared by the version dropdown and the Recent History markers,
 * so the two surfaces read identically.
 */

import { render, screen } from '@testing-library/react';
import { describe, expect, test } from 'vitest';

import { releaseActionLabel } from '../../../js/collaborative-editor/utils/releaseLabel';

function renderLabel(version: Parameters<typeof releaseActionLabel>[0]) {
  render(<span data-testid="label">{releaseActionLabel(version)}</span>);

  return screen.getByTestId('label');
}

describe('releaseActionLabel', () => {
  test('a restore names the version it put back', () => {
    const label = renderLabel({
      kind: 'restore',
      version_number: 4,
      source_project: null,
      restored_from_version_number: 2,
    });

    expect(label).toHaveTextContent('Restored v2');
  });

  test('a promote names the sandbox it came from', () => {
    const label = renderLabel({
      kind: 'promote',
      version_number: 3,
      source_project: 'fixing-the-mapping',
      restored_from_version_number: null,
    });

    expect(label).toHaveTextContent('Promoted sandbox fixing-the-mapping');
  });

  test('the first release is the initial go-live', () => {
    const label = renderLabel({
      kind: 'go_live',
      version_number: 1,
      source_project: null,
      restored_from_version_number: null,
    });

    expect(label).toHaveTextContent('Initial go-live');
  });

  test('a later go-live is published from draft', () => {
    const label = renderLabel({
      kind: 'go_live',
      version_number: 2,
      source_project: null,
      restored_from_version_number: null,
    });

    expect(label).toHaveTextContent('Published from draft');
  });
});
