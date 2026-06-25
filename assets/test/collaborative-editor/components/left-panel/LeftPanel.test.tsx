/**
 * LeftPanel Component Tests
 *
 * Tests the LeftPanel component including:
 * - Rendering based on method prop
 * - Method switching callbacks
 * - Null method handling
 */

import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen } from '@testing-library/react';
import { LeftPanel } from '../../../../js/collaborative-editor/components/left-panel';

// Mock child components to isolate LeftPanel tests
vi.mock(
  '../../../../js/collaborative-editor/components/left-panel/TemplatePanel',
  () => ({
    TemplatePanel: vi.fn(({ onImportClick }) => (
      <div data-testid="template-panel">
        <button onClick={onImportClick} data-testid="mock-import-button">
          Import
        </button>
      </div>
    )),
  })
);

describe('LeftPanel', () => {
  let mockOnMethodChange: ReturnType<typeof vi.fn>;

  beforeEach(() => {
    mockOnMethodChange = vi.fn();
  });

  describe('rendering based on method', () => {
    it('renders TemplatePanel when method is "template"', () => {
      render(
        <LeftPanel method="template" onMethodChange={mockOnMethodChange} />
      );

      expect(screen.getByTestId('template-panel')).toBeInTheDocument();
    });

    it('renders AI placeholder when method is "ai"', () => {
      render(<LeftPanel method="ai" onMethodChange={mockOnMethodChange} />);

      expect(
        screen.getByText('AI workflow creation coming soon...')
      ).toBeInTheDocument();
      expect(screen.queryByTestId('template-panel')).not.toBeInTheDocument();
    });

    it('renders nothing for "import" method (modal handles it)', () => {
      render(<LeftPanel method="import" onMethodChange={mockOnMethodChange} />);

      expect(screen.queryByTestId('template-panel')).not.toBeInTheDocument();
      expect(
        screen.queryByText('AI workflow creation coming soon...')
      ).not.toBeInTheDocument();
    });

    it('renders nothing when method is null', () => {
      const { container } = render(
        <LeftPanel method={null} onMethodChange={mockOnMethodChange} />
      );

      expect(container.firstChild).toBeNull();
    });
  });

  describe('method switching', () => {
    it('calls onMethodChange with "import" when TemplatePanel import is clicked', () => {
      render(
        <LeftPanel method="template" onMethodChange={mockOnMethodChange} />
      );

      screen.getByTestId('mock-import-button').click();

      expect(mockOnMethodChange).toHaveBeenCalledWith('import');
    });
  });

  describe('panel container', () => {
    it('has full width and height classes', () => {
      const { container } = render(
        <LeftPanel method="template" onMethodChange={mockOnMethodChange} />
      );

      const panel = container.firstChild as HTMLElement;
      expect(panel).toHaveClass('w-full', 'h-full');
    });
  });
});
