/**
 * SelectedDataclipView Component Tests
 *
 * Tests for the dataclip detail view that appears when a user selects
 * a dataclip from the list. Tests cover:
 * - Rendering dataclip information (name, type, date)
 * - Name editing with Enter/Escape keyboard shortcuts
 * - Validation that skips API call when name unchanged
 * - Error handling for API failures
 * - Edit permissions and disabled states
 * - Next cron run warning banner
 */

import { render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { describe, expect, test, vi, beforeEach } from 'vitest';

import type { Dataclip } from '../../../../js/collaborative-editor/api/dataclips';
import { SelectedDataclipView } from '../../../../js/collaborative-editor/components/manual-run/SelectedDataclipView';

// Mock DataclipViewer component
vi.mock('../../../../js/react/components/DataclipViewer', () => ({
  DataclipViewer: ({ dataclipId }: { dataclipId: string }) => (
    <div data-testid="dataclip-viewer">Viewer for {dataclipId}</div>
  ),
}));

const mockDataclip: Dataclip = {
  id: 'dataclip-123',
  name: 'Test Dataclip',
  type: 'http_request',
  body: { data: 'test' },
  inserted_at: '2024-01-15T10:30:00Z',
  updated_at: '2024-01-15T10:30:00Z',
  project_id: 'project-1',
  wiped_at: null,
  step_id: null,
  request: null,
};

describe('SelectedDataclipView', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  describe('Basic Rendering', () => {
    test('renders dataclip name and metadata', () => {
      const onUnselect = vi.fn();
      const onNameChange = vi.fn();

      render(
        <SelectedDataclipView
          dataclip={mockDataclip}
          onUnselect={onUnselect}
          onNameChange={onNameChange}
          canEdit={true}
          isNextCronRun={false}
        />
      );

      expect(screen.getByText('Test Dataclip')).toBeInTheDocument();
      expect(screen.getByText('http request')).toBeInTheDocument();

      // Calculate expected date string for the current locale
      const expectedDate = new Date(
        '2024-01-15T10:30:00Z'
      ).toLocaleDateString();
      expect(screen.getByText(expectedDate)).toBeInTheDocument();
    });

    test("renders 'Unnamed' when dataclip has no name", () => {
      const dataclip = { ...mockDataclip, name: null };
      const onUnselect = vi.fn();
      const onNameChange = vi.fn();

      render(
        <SelectedDataclipView
          dataclip={dataclip}
          onUnselect={onUnselect}
          onNameChange={onNameChange}
          canEdit={true}
          isNextCronRun={false}
        />
      );

      expect(screen.getByText('Unnamed')).toBeInTheDocument();
    });

    test('renders dataclip viewer with correct ID', () => {
      const onUnselect = vi.fn();
      const onNameChange = vi.fn();

      render(
        <SelectedDataclipView
          dataclip={mockDataclip}
          onUnselect={onUnselect}
          onNameChange={onNameChange}
          canEdit={true}
          isNextCronRun={false}
        />
      );

      expect(screen.getByTestId('dataclip-viewer')).toHaveTextContent(
        'Viewer for dataclip-123'
      );
    });

    test('renders close button', () => {
      const onUnselect = vi.fn();
      const onNameChange = vi.fn();

      render(
        <SelectedDataclipView
          dataclip={mockDataclip}
          onUnselect={onUnselect}
          onNameChange={onNameChange}
          canEdit={true}
          isNextCronRun={false}
        />
      );

      const closeButtons = screen.getAllByRole('button');
      const xButton = closeButtons.find(
        btn =>
          btn.querySelector('svg[data-slot="icon"]') &&
          btn.className.includes('ml-4')
      );
      expect(xButton).toBeDefined();
    });

    test('shows next cron run warning when isNextCronRun is true', () => {
      const onUnselect = vi.fn();
      const onNameChange = vi.fn();

      render(
        <SelectedDataclipView
          dataclip={mockDataclip}
          onUnselect={onUnselect}
          onNameChange={onNameChange}
          canEdit={true}
          isNextCronRun={true}
        />
      );

      expect(
        screen.getByText('Default Next Input for Cron')
      ).toBeInTheDocument();
      expect(
        screen.getByText(/This workflow has a "cron" trigger/)
      ).toBeInTheDocument();
    });

    test('does not show next cron run warning when isNextCronRun is false', () => {
      const onUnselect = vi.fn();
      const onNameChange = vi.fn();

      render(
        <SelectedDataclipView
          dataclip={mockDataclip}
          onUnselect={onUnselect}
          onNameChange={onNameChange}
          canEdit={true}
          isNextCronRun={false}
        />
      );

      expect(
        screen.queryByText('Default Next Input for Cron')
      ).not.toBeInTheDocument();
    });
  });

  describe('Edit Permissions', () => {
    test('shows edit button when canEdit is true', () => {
      const onUnselect = vi.fn();
      const onNameChange = vi.fn();

      render(
        <SelectedDataclipView
          dataclip={mockDataclip}
          onUnselect={onUnselect}
          onNameChange={onNameChange}
          canEdit={true}
          isNextCronRun={false}
        />
      );

      const editButtons = screen.getAllByRole('button');
      const pencilButton = editButtons.find(btn =>
        btn.querySelector('svg path[d*="16.862"]')
      );
      expect(pencilButton).toBeDefined();
    });

    test('does not show edit button when canEdit is false', () => {
      const onUnselect = vi.fn();
      const onNameChange = vi.fn();

      render(
        <SelectedDataclipView
          dataclip={mockDataclip}
          onUnselect={onUnselect}
          onNameChange={onNameChange}
          canEdit={false}
          isNextCronRun={false}
        />
      );

      const editButtons = screen.getAllByRole('button');
      const pencilButton = editButtons.find(btn =>
        btn.querySelector('svg path[d*="16.862"]')
      );
      expect(pencilButton).toBeUndefined();
    });
  });

  describe('Name Editing', () => {
    test('enters edit mode when pencil icon clicked', async () => {
      const user = userEvent.setup();
      const onUnselect = vi.fn();
      const onNameChange = vi.fn();

      render(
        <SelectedDataclipView
          dataclip={mockDataclip}
          onUnselect={onUnselect}
          onNameChange={onNameChange}
          canEdit={true}
          isNextCronRun={false}
        />
      );

      // Find edit button (pencil icon, first button)
      const buttons = screen.getAllByRole('button');
      const pencilButton = buttons[0];

      await user.click(pencilButton);

      expect(screen.getByPlaceholderText('Dataclip name')).toBeInTheDocument();
      expect(screen.getByDisplayValue('Test Dataclip')).toBeInTheDocument();
    });

    test('shows save and cancel buttons in edit mode', async () => {
      const user = userEvent.setup();
      const onUnselect = vi.fn();
      const onNameChange = vi.fn();

      render(
        <SelectedDataclipView
          dataclip={mockDataclip}
          onUnselect={onUnselect}
          onNameChange={onNameChange}
          canEdit={true}
          isNextCronRun={false}
        />
      );

      const editButtons = screen.getAllByRole('button');
      const pencilButton = editButtons[0];

      await user.click(pencilButton!);

      const allButtons = screen.getAllByRole('button');
      const checkButton = allButtons[0]; // Check button (first in edit mode)
      const xButton = allButtons[1]; // Cancel button (second in edit mode)

      expect(checkButton).toBeInTheDocument();
      expect(xButton).toBeInTheDocument();
    });

    test('updates input value when typing', async () => {
      const user = userEvent.setup();
      const onUnselect = vi.fn();
      const onNameChange = vi.fn();

      render(
        <SelectedDataclipView
          dataclip={mockDataclip}
          onUnselect={onUnselect}
          onNameChange={onNameChange}
          canEdit={true}
          isNextCronRun={false}
        />
      );

      const editButtons = screen.getAllByRole('button');
      const pencilButton = editButtons[0];

      await user.click(pencilButton!);

      const input = screen.getByPlaceholderText('Dataclip name');
      await user.clear(input);
      await user.type(input, 'New Name');

      expect(input).toHaveValue('New Name');
    });

    test('calls onNameChange when save button clicked with new name', async () => {
      const user = userEvent.setup();
      const onUnselect = vi.fn();
      const onNameChange = vi.fn().mockResolvedValue(undefined);

      render(
        <SelectedDataclipView
          dataclip={mockDataclip}
          onUnselect={onUnselect}
          onNameChange={onNameChange}
          canEdit={true}
          isNextCronRun={false}
        />
      );

      const editButtons = screen.getAllByRole('button');
      const pencilButton = editButtons[0];

      await user.click(pencilButton!);

      const input = screen.getByPlaceholderText('Dataclip name');
      await user.clear(input);
      await user.type(input, 'Updated Name');

      const allButtons = screen.getAllByRole('button');
      const checkButton = allButtons[0]; // Check button (first in edit mode)

      await user.click(checkButton!);

      await waitFor(() => {
        expect(onNameChange).toHaveBeenCalledWith(
          'dataclip-123',
          'Updated Name'
        );
      });
    });

    test('exits edit mode after successful save', async () => {
      const user = userEvent.setup();
      const onUnselect = vi.fn();
      const onNameChange = vi.fn().mockResolvedValue(undefined);

      render(
        <SelectedDataclipView
          dataclip={mockDataclip}
          onUnselect={onUnselect}
          onNameChange={onNameChange}
          canEdit={true}
          isNextCronRun={false}
        />
      );

      const editButtons = screen.getAllByRole('button');
      const pencilButton = editButtons[0];

      await user.click(pencilButton!);

      const input = screen.getByPlaceholderText('Dataclip name');
      await user.clear(input);
      await user.type(input, 'Updated Name');

      const allButtons = screen.getAllByRole('button');
      const checkButton = allButtons[0]; // Check button (first in edit mode)

      await user.click(checkButton!);

      await waitFor(() => {
        expect(
          screen.queryByPlaceholderText('Dataclip name')
        ).not.toBeInTheDocument();
      });
    });

    test('does NOT call onNameChange when name is unchanged', async () => {
      const user = userEvent.setup();
      const onUnselect = vi.fn();
      const onNameChange = vi.fn().mockResolvedValue(undefined);

      render(
        <SelectedDataclipView
          dataclip={mockDataclip}
          onUnselect={onUnselect}
          onNameChange={onNameChange}
          canEdit={true}
          isNextCronRun={false}
        />
      );

      const editButtons = screen.getAllByRole('button');
      const pencilButton = editButtons[0];

      await user.click(pencilButton!);

      const allButtons = screen.getAllByRole('button');
      const checkButton = allButtons[0]; // Check button (first in edit mode)

      await user.click(checkButton!);

      await waitFor(() => {
        expect(
          screen.queryByPlaceholderText('Dataclip name')
        ).not.toBeInTheDocument();
      });

      expect(onNameChange).not.toHaveBeenCalled();
    });

    test('does NOT call onNameChange when only whitespace changes', async () => {
      const user = userEvent.setup();
      const onUnselect = vi.fn();
      const onNameChange = vi.fn().mockResolvedValue(undefined);

      render(
        <SelectedDataclipView
          dataclip={mockDataclip}
          onUnselect={onUnselect}
          onNameChange={onNameChange}
          canEdit={true}
          isNextCronRun={false}
        />
      );

      const editButtons = screen.getAllByRole('button');
      const pencilButton = editButtons[0];

      await user.click(pencilButton!);

      const input = screen.getByPlaceholderText('Dataclip name');
      await user.type(input, '   ');

      const allButtons = screen.getAllByRole('button');
      const checkButton = allButtons[0]; // Check button (first in edit mode)

      await user.click(checkButton!);

      await waitFor(() => {
        expect(
          screen.queryByPlaceholderText('Dataclip name')
        ).not.toBeInTheDocument();
      });

      expect(onNameChange).not.toHaveBeenCalled();
    });

    test('cancels edit when cancel button clicked', async () => {
      const user = userEvent.setup();
      const onUnselect = vi.fn();
      const onNameChange = vi.fn();

      render(
        <SelectedDataclipView
          dataclip={mockDataclip}
          onUnselect={onUnselect}
          onNameChange={onNameChange}
          canEdit={true}
          isNextCronRun={false}
        />
      );

      const editButtons = screen.getAllByRole('button');
      const pencilButton = editButtons[0];

      await user.click(pencilButton!);

      const input = screen.getByPlaceholderText('Dataclip name');
      await user.clear(input);
      await user.type(input, 'Changed Name');

      const allButtons = screen.getAllByRole('button');
      const xButton = allButtons[1]; // Cancel button (second in edit mode)

      await user.click(xButton!);

      await waitFor(() => {
        expect(
          screen.queryByPlaceholderText('Dataclip name')
        ).not.toBeInTheDocument();
      });

      expect(onNameChange).not.toHaveBeenCalled();
      expect(screen.getByText('Test Dataclip')).toBeInTheDocument();
    });

    test('shows error message when save fails', async () => {
      const user = userEvent.setup();
      const onUnselect = vi.fn();
      const onNameChange = vi
        .fn()
        .mockRejectedValue(new Error('Network error'));

      render(
        <SelectedDataclipView
          dataclip={mockDataclip}
          onUnselect={onUnselect}
          onNameChange={onNameChange}
          canEdit={true}
          isNextCronRun={false}
        />
      );

      const editButtons = screen.getAllByRole('button');
      const pencilButton = editButtons[0];

      await user.click(pencilButton!);

      const input = screen.getByPlaceholderText('Dataclip name');
      await user.clear(input);
      await user.type(input, 'New Name');

      const allButtons = screen.getAllByRole('button');
      const checkButton = allButtons[0]; // Check button (first in edit mode)

      await user.click(checkButton!);

      await waitFor(() => {
        expect(screen.getByText('Network error')).toBeInTheDocument();
      });

      expect(screen.getByPlaceholderText('Dataclip name')).toBeInTheDocument();
    });

    test('shows generic error message when non-Error thrown', async () => {
      const user = userEvent.setup();
      const onUnselect = vi.fn();
      const onNameChange = vi.fn().mockRejectedValue('Unknown failure');

      render(
        <SelectedDataclipView
          dataclip={mockDataclip}
          onUnselect={onUnselect}
          onNameChange={onNameChange}
          canEdit={true}
          isNextCronRun={false}
        />
      );

      const editButtons = screen.getAllByRole('button');
      const pencilButton = editButtons[0];

      await user.click(pencilButton!);

      const input = screen.getByPlaceholderText('Dataclip name');
      await user.clear(input);
      await user.type(input, 'New Name');

      const allButtons = screen.getAllByRole('button');
      const checkButton = allButtons[0]; // Check button (first in edit mode)

      await user.click(checkButton!);

      await waitFor(() => {
        expect(screen.getByText('Failed to save name')).toBeInTheDocument();
      });
    });

    test('disables buttons while saving', async () => {
      const user = userEvent.setup();
      const onUnselect = vi.fn();
      let resolveNameChange: () => void;
      const nameChangePromise = new Promise<void>(resolve => {
        resolveNameChange = resolve;
      });
      const onNameChange = vi.fn().mockReturnValue(nameChangePromise);

      render(
        <SelectedDataclipView
          dataclip={mockDataclip}
          onUnselect={onUnselect}
          onNameChange={onNameChange}
          canEdit={true}
          isNextCronRun={false}
        />
      );

      const editButtons = screen.getAllByRole('button');
      const pencilButton = editButtons[0];

      await user.click(pencilButton!);

      const input = screen.getByPlaceholderText('Dataclip name');
      await user.clear(input);
      await user.type(input, 'New Name');

      const allButtons = screen.getAllByRole('button');
      const checkButton = allButtons[0]; // Check button (first in edit mode)

      await user.click(checkButton!);

      await waitFor(() => {
        expect(checkButton).toBeDisabled();
      });

      const xButton = allButtons[1]; // Cancel button (second in edit mode)
      expect(xButton).toBeDisabled();

      resolveNameChange!();
    });
  });

  describe('Keyboard Shortcuts', () => {
    test('saves name when Enter key pressed', async () => {
      const user = userEvent.setup();
      const onUnselect = vi.fn();
      const onNameChange = vi.fn().mockResolvedValue(undefined);

      render(
        <SelectedDataclipView
          dataclip={mockDataclip}
          onUnselect={onUnselect}
          onNameChange={onNameChange}
          canEdit={true}
          isNextCronRun={false}
        />
      );

      const editButtons = screen.getAllByRole('button');
      const pencilButton = editButtons[0];

      await user.click(pencilButton!);

      const input = screen.getByPlaceholderText('Dataclip name');
      await user.clear(input);
      await user.type(input, 'Keyboard Name');
      await user.keyboard('{Enter}');

      await waitFor(() => {
        expect(onNameChange).toHaveBeenCalledWith(
          'dataclip-123',
          'Keyboard Name'
        );
      });
    });

    test('does NOT save when Enter pressed with unchanged name', async () => {
      const user = userEvent.setup();
      const onUnselect = vi.fn();
      const onNameChange = vi.fn().mockResolvedValue(undefined);

      render(
        <SelectedDataclipView
          dataclip={mockDataclip}
          onUnselect={onUnselect}
          onNameChange={onNameChange}
          canEdit={true}
          isNextCronRun={false}
        />
      );

      const editButtons = screen.getAllByRole('button');
      const pencilButton = editButtons[0];

      await user.click(pencilButton!);

      const input = screen.getByPlaceholderText('Dataclip name');
      await user.keyboard('{Enter}');

      await waitFor(() => {
        expect(
          screen.queryByPlaceholderText('Dataclip name')
        ).not.toBeInTheDocument();
      });

      expect(onNameChange).not.toHaveBeenCalled();
    });

    test('cancels edit when Escape key pressed', async () => {
      const user = userEvent.setup();
      const onUnselect = vi.fn();
      const onNameChange = vi.fn();

      render(
        <SelectedDataclipView
          dataclip={mockDataclip}
          onUnselect={onUnselect}
          onNameChange={onNameChange}
          canEdit={true}
          isNextCronRun={false}
        />
      );

      const editButtons = screen.getAllByRole('button');
      const pencilButton = editButtons[0];

      await user.click(pencilButton!);

      const input = screen.getByPlaceholderText('Dataclip name');
      await user.clear(input);
      await user.type(input, 'Changed Name');
      await user.keyboard('{Escape}');

      await waitFor(() => {
        expect(
          screen.queryByPlaceholderText('Dataclip name')
        ).not.toBeInTheDocument();
      });

      expect(onNameChange).not.toHaveBeenCalled();
      expect(screen.getByText('Test Dataclip')).toBeInTheDocument();
    });

    test('does not save when Enter pressed while saving', async () => {
      const user = userEvent.setup();
      const onUnselect = vi.fn();
      let resolveNameChange: () => void;
      const nameChangePromise = new Promise<void>(resolve => {
        resolveNameChange = resolve;
      });
      const onNameChange = vi.fn().mockReturnValue(nameChangePromise);

      render(
        <SelectedDataclipView
          dataclip={mockDataclip}
          onUnselect={onUnselect}
          onNameChange={onNameChange}
          canEdit={true}
          isNextCronRun={false}
        />
      );

      const editButtons = screen.getAllByRole('button');
      const pencilButton = editButtons[0];

      await user.click(pencilButton!);

      const input = screen.getByPlaceholderText('Dataclip name');
      await user.clear(input);
      await user.type(input, 'New Name');
      await user.keyboard('{Enter}');

      await waitFor(() => {
        expect(onNameChange).toHaveBeenCalledTimes(1);
      });

      await user.keyboard('{Enter}');

      expect(onNameChange).toHaveBeenCalledTimes(1);

      resolveNameChange!();
    });
  });

  describe('Unselect Behavior', () => {
    test('calls onUnselect when close button clicked', async () => {
      const user = userEvent.setup();
      const onUnselect = vi.fn();
      const onNameChange = vi.fn();

      render(
        <SelectedDataclipView
          dataclip={mockDataclip}
          onUnselect={onUnselect}
          onNameChange={onNameChange}
          canEdit={true}
          isNextCronRun={false}
        />
      );

      const closeButtons = screen.getAllByRole('button');
      const xButton = closeButtons[1]; // Close button (last button)

      await user.click(xButton!);

      expect(onUnselect).toHaveBeenCalledOnce();
    });
  });

  describe('Empty Name Handling', () => {
    test('saves null when input is cleared', async () => {
      const user = userEvent.setup();
      const onUnselect = vi.fn();
      const onNameChange = vi.fn().mockResolvedValue(undefined);

      render(
        <SelectedDataclipView
          dataclip={mockDataclip}
          onUnselect={onUnselect}
          onNameChange={onNameChange}
          canEdit={true}
          isNextCronRun={false}
        />
      );

      const editButtons = screen.getAllByRole('button');
      const pencilButton = editButtons[0];

      await user.click(pencilButton!);

      const input = screen.getByPlaceholderText('Dataclip name');
      await user.clear(input);

      const allButtons = screen.getAllByRole('button');
      const checkButton = allButtons[0]; // Check button (first in edit mode)

      await user.click(checkButton!);

      await waitFor(() => {
        expect(onNameChange).toHaveBeenCalledWith('dataclip-123', null);
      });
    });

    test('initializes input with empty string for unnamed dataclip', async () => {
      const user = userEvent.setup();
      const dataclip = { ...mockDataclip, name: null };
      const onUnselect = vi.fn();
      const onNameChange = vi.fn();

      render(
        <SelectedDataclipView
          dataclip={dataclip}
          onUnselect={onUnselect}
          onNameChange={onNameChange}
          canEdit={true}
          isNextCronRun={false}
        />
      );

      const editButtons = screen.getAllByRole('button');
      const pencilButton = editButtons[0];

      await user.click(pencilButton!);

      const input = screen.getByPlaceholderText('Dataclip name');
      expect(input).toHaveValue('');
    });
  });
});
