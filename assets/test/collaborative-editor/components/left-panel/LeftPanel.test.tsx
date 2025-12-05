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

vi.mock(
  '../../../../js/collaborative-editor/components/left-panel/YAMLImportPanel',
  () => ({
    YAMLImportPanel: vi.fn(({ onBack }) => (
      <div data-testid="yaml-import-panel">
        <button onClick={onBack} data-testid="mock-back-button">
          Back
        </button>
      </div>
    )),
  })
);

describe('LeftPanel', () => {
  let mockOnMethodChange: ReturnType<typeof vi.fn>;
  let mockOnImport: ReturnType<typeof vi.fn>;
  let mockOnSave: ReturnType<typeof vi.fn>;

  beforeEach(() => {
    mockOnMethodChange = vi.fn();
    mockOnImport = vi.fn();
    mockOnSave = vi.fn().mockResolvedValue(undefined);
  });

  describe('rendering based on method', () => {
    it('renders TemplatePanel when method is "template"', () => {
      render(
        <LeftPanel
          method="template"
          onMethodChange={mockOnMethodChange}
          onImport={mockOnImport}
          onSave={mockOnSave}
        />
      );

      expect(screen.getByTestId('template-panel')).toBeInTheDocument();
      expect(screen.queryByTestId('yaml-import-panel')).not.toBeInTheDocument();
    });

    it('renders YAMLImportPanel when method is "import"', () => {
      render(
        <LeftPanel
          method="import"
          onMethodChange={mockOnMethodChange}
          onImport={mockOnImport}
          onSave={mockOnSave}
        />
      );

      expect(screen.getByTestId('yaml-import-panel')).toBeInTheDocument();
      expect(screen.queryByTestId('template-panel')).not.toBeInTheDocument();
    });

    it('renders AI placeholder when method is "ai"', () => {
      render(
        <LeftPanel
          method="ai"
          onMethodChange={mockOnMethodChange}
          onImport={mockOnImport}
          onSave={mockOnSave}
        />
      );

      expect(
        screen.getByText('AI workflow creation coming soon...')
      ).toBeInTheDocument();
      expect(screen.queryByTestId('template-panel')).not.toBeInTheDocument();
      expect(screen.queryByTestId('yaml-import-panel')).not.toBeInTheDocument();
    });

    it('renders nothing when method is null', () => {
      const { container } = render(
        <LeftPanel
          method={null}
          onMethodChange={mockOnMethodChange}
          onImport={mockOnImport}
          onSave={mockOnSave}
        />
      );

      expect(container.firstChild).toBeNull();
    });
  });

  describe('method switching', () => {
    it('calls onMethodChange with "import" when TemplatePanel import is clicked', () => {
      render(
        <LeftPanel
          method="template"
          onMethodChange={mockOnMethodChange}
          onImport={mockOnImport}
          onSave={mockOnSave}
        />
      );

      screen.getByTestId('mock-import-button').click();

      expect(mockOnMethodChange).toHaveBeenCalledWith('import');
    });

    it('calls onMethodChange with "template" when YAMLImportPanel back is clicked', () => {
      render(
        <LeftPanel
          method="import"
          onMethodChange={mockOnMethodChange}
          onImport={mockOnImport}
          onSave={mockOnSave}
        />
      );

      screen.getByTestId('mock-back-button').click();

      expect(mockOnMethodChange).toHaveBeenCalledWith('template');
    });
  });

  describe('panel container', () => {
    it('has full width and height classes', () => {
      const { container } = render(
        <LeftPanel
          method="template"
          onMethodChange={mockOnMethodChange}
          onImport={mockOnImport}
          onSave={mockOnSave}
        />
      );

      const panel = container.firstChild as HTMLElement;
      expect(panel).toHaveClass('w-full', 'h-full');
    });
  });
});
