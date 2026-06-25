/**
 * LandingScreen Component Tests
 *
 * LandingScreen is a pure presentational component — no store context needed.
 * Tests cover: button enabled/disabled state, keyboard submission, AI variant
 * visibility, and card click stubs.
 */

import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { describe, expect, test, vi } from 'vitest';

import { LandingScreen } from '../../../js/collaborative-editor/components/LandingScreen';

// =============================================================================
// HELPERS
// =============================================================================

function renderLandingScreen(props: {
  aiAssistantEnabled?: boolean;
  onBuildWithAI?: (prompt: string) => void;
  onBuildFromScratch?: () => void;
  onBrowseTemplates?: () => void;
  onImportYAML?: () => void;
}) {
  const defaults = {
    aiAssistantEnabled: true,
    onBuildWithAI: vi.fn(),
    onBuildFromScratch: vi.fn(),
    onBrowseTemplates: vi.fn(),
    onImportYAML: vi.fn(),
  };
  return render(<LandingScreen {...defaults} {...props} />);
}

// =============================================================================
// BUILD WITH AI BUTTON: ENABLED / DISABLED STATE
// =============================================================================

describe('LandingScreen - Build with AI button state', () => {
  test('button is disabled when input is empty', () => {
    renderLandingScreen({ aiAssistantEnabled: true });

    expect(screen.getByTestId('build-with-ai-button')).toBeDisabled();
  });

  test('button stays disabled when input contains only whitespace, then becomes enabled on valid text', async () => {
    const user = userEvent.setup();
    renderLandingScreen({ aiAssistantEnabled: true });

    const input = screen.getByTestId('build-with-ai-input');
    const button = screen.getByTestId('build-with-ai-button');

    await user.type(input, '   ');
    expect(button).toBeDisabled();

    await user.clear(input);
    await user.type(input, 'hello');
    expect(button).not.toBeDisabled();
  });
});

// =============================================================================
// BUTTON CLICK SUBMISSION
// =============================================================================

describe('LandingScreen - Button click submission', () => {
  test('clicking Build it button submits the prompt', async () => {
    const user = userEvent.setup();
    const onBuildWithAI = vi.fn();
    renderLandingScreen({ onBuildWithAI });

    await user.type(
      screen.getByTestId('build-with-ai-input'),
      'my workflow prompt'
    );
    await user.click(screen.getByTestId('build-with-ai-button'));

    expect(onBuildWithAI).toHaveBeenCalledOnce();
    expect(onBuildWithAI).toHaveBeenCalledWith('my workflow prompt');
  });
});

// =============================================================================
// KEYBOARD SUBMISSION
// =============================================================================

describe('LandingScreen - Keyboard submission', () => {
  test('Enter key submits with the typed prompt', async () => {
    const user = userEvent.setup();
    const onBuildWithAI = vi.fn();
    renderLandingScreen({ aiAssistantEnabled: true, onBuildWithAI });

    const input = screen.getByTestId('build-with-ai-input');
    await user.type(input, 'my workflow');
    await user.keyboard('{Enter}');

    expect(onBuildWithAI).toHaveBeenCalledTimes(1);
    expect(onBuildWithAI).toHaveBeenCalledWith('my workflow');
  });

  test('Shift+Enter and Alt+Enter do not submit', async () => {
    const user = userEvent.setup();
    const onBuildWithAI = vi.fn();
    renderLandingScreen({ aiAssistantEnabled: true, onBuildWithAI });

    const input = screen.getByTestId('build-with-ai-input');
    await user.type(input, 'my workflow');

    await user.keyboard('{Shift>}{Enter}{/Shift}');
    expect(onBuildWithAI).not.toHaveBeenCalled();

    await user.keyboard('{Alt>}{Enter}{/Alt}');
    expect(onBuildWithAI).not.toHaveBeenCalled();
  });
});

// =============================================================================
// AI ASSISTANT VISIBILITY VARIANTS
// =============================================================================

describe('LandingScreen - AI assistant visibility', () => {
  test('shows build-with-ai-input, both cards, and yaml link when AI is enabled', () => {
    renderLandingScreen({ aiAssistantEnabled: true });

    expect(screen.getByTestId('build-with-ai-input')).toBeInTheDocument();
    expect(screen.getByTestId('build-from-scratch-card')).toBeInTheDocument();
    expect(screen.getByTestId('browse-templates-card')).toBeInTheDocument();
    expect(screen.getByTestId('import-yaml-link')).toBeInTheDocument();
  });

  test('shows "Recommended" badge when AI is enabled', () => {
    renderLandingScreen({ aiAssistantEnabled: true });
    expect(screen.getByText('Recommended')).toBeInTheDocument();
  });

  test('does not show "Recommended" badge when AI is disabled', () => {
    renderLandingScreen({ aiAssistantEnabled: false });
    expect(screen.queryByText('Recommended')).not.toBeInTheDocument();
  });

  test('omits build-with-ai-input but still shows both cards and yaml link when AI is disabled', () => {
    renderLandingScreen({ aiAssistantEnabled: false });

    expect(screen.queryByTestId('build-with-ai-input')).not.toBeInTheDocument();
    expect(screen.getByTestId('build-from-scratch-card')).toBeInTheDocument();
    expect(screen.getByTestId('browse-templates-card')).toBeInTheDocument();
    expect(screen.getByTestId('import-yaml-link')).toBeInTheDocument();
  });
});

// =============================================================================
// CARD CLICK STUBS
// =============================================================================

describe('LandingScreen - Card click handlers', () => {
  test('clicking cards and yaml link calls respective handlers', async () => {
    const user = userEvent.setup();
    const onBuildFromScratch = vi.fn();
    const onBrowseTemplates = vi.fn();
    const onImportYAML = vi.fn();
    renderLandingScreen({
      onBuildFromScratch,
      onBrowseTemplates,
      onImportYAML,
    });

    await user.click(screen.getByTestId('build-from-scratch-card'));
    expect(onBuildFromScratch).toHaveBeenCalledTimes(1);

    await user.click(screen.getByTestId('browse-templates-card'));
    expect(onBrowseTemplates).toHaveBeenCalledTimes(1);

    await user.click(screen.getByTestId('import-yaml-link'));
    expect(onImportYAML).toHaveBeenCalledTimes(1);
  });
});
