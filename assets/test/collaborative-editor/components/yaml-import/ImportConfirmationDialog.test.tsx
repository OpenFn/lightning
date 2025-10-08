/**
 * ImportConfirmationDialog Component Tests
 *
 * Tests confirmation dialog for collaborative import scenarios
 */

import { describe, expect, test, vi } from 'vitest';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { ImportConfirmationDialog } from '../../../../js/collaborative-editor/components/yaml-import/ImportConfirmationDialog';
import type { AwarenessUser } from '../../../../js/collaborative-editor/types/awareness';

function createMockUser(overrides?: Partial<AwarenessUser>): AwarenessUser {
  return {
    clientId: 1,
    user: {
      id: 'user-1',
      name: 'Test User',
      color: '#ff0000',
    },
    ...overrides,
  };
}

describe('ImportConfirmationDialog', () => {
  describe('Dialog visibility', () => {
    test('does not render when isOpen is false', () => {
      const onConfirm = vi.fn();
      const onCancel = vi.fn();
      const activeUsers = [createMockUser()];

      render(
        <ImportConfirmationDialog
          isOpen={false}
          activeUsers={activeUsers}
          onConfirm={onConfirm}
          onCancel={onCancel}
        />
      );

      expect(screen.queryByText(/Replace Workflow/i)).not.toBeInTheDocument();
    });

    test('renders when isOpen is true', () => {
      const onConfirm = vi.fn();
      const onCancel = vi.fn();
      const activeUsers = [createMockUser()];

      render(
        <ImportConfirmationDialog
          isOpen={true}
          activeUsers={activeUsers}
          onConfirm={onConfirm}
          onCancel={onCancel}
        />
      );

      expect(screen.getByText(/Replace Workflow/i)).toBeInTheDocument();
    });

    test('does not render when no active users', () => {
      const onConfirm = vi.fn();
      const onCancel = vi.fn();

      render(
        <ImportConfirmationDialog
          isOpen={true}
          activeUsers={[]}
          onConfirm={onConfirm}
          onCancel={onCancel}
        />
      );

      expect(screen.queryByText(/Replace Workflow/i)).not.toBeInTheDocument();
    });
  });

  describe('Content display', () => {
    test('shows warning message for single user', () => {
      const onConfirm = vi.fn();
      const onCancel = vi.fn();
      const activeUsers = [createMockUser()];

      render(
        <ImportConfirmationDialog
          isOpen={true}
          activeUsers={activeUsers}
          onConfirm={onConfirm}
          onCancel={onCancel}
        />
      );

      expect(screen.getByText(/1 user is currently editing/i)).toBeInTheDocument();
      expect(screen.getByText(/replace the entire workflow for all users/i)).toBeInTheDocument();
    });

    test('shows warning message for multiple users', () => {
      const onConfirm = vi.fn();
      const onCancel = vi.fn();
      const activeUsers = [
        createMockUser({ clientId: 1, user: { id: '1', name: 'User 1', color: '#ff0000' } }),
        createMockUser({ clientId: 2, user: { id: '2', name: 'User 2', color: '#00ff00' } }),
      ];

      render(
        <ImportConfirmationDialog
          isOpen={true}
          activeUsers={activeUsers}
          onConfirm={onConfirm}
          onCancel={onCancel}
        />
      );

      expect(screen.getByText(/2 users are currently editing/i)).toBeInTheDocument();
    });

    test('displays active users list', () => {
      const onConfirm = vi.fn();
      const onCancel = vi.fn();
      const activeUsers = [
        createMockUser({ clientId: 1, user: { id: '1', name: 'Alice', color: '#ff0000' } }),
        createMockUser({ clientId: 2, user: { id: '2', name: 'Bob', color: '#00ff00' } }),
      ];

      render(
        <ImportConfirmationDialog
          isOpen={true}
          activeUsers={activeUsers}
          onConfirm={onConfirm}
          onCancel={onCancel}
        />
      );

      expect(screen.getByText(/Active users:/i)).toBeInTheDocument();
      expect(screen.getByText('Alice')).toBeInTheDocument();
      expect(screen.getByText('Bob')).toBeInTheDocument();
    });

    test('displays user avatars with colors', async () => {
      const onConfirm = vi.fn();
      const onCancel = vi.fn();
      const activeUsers = [
        createMockUser({ clientId: 1, user: { id: '1', name: 'Alice', color: '#ff0000' } }),
      ];

      render(
        <ImportConfirmationDialog
          isOpen={true}
          activeUsers={activeUsers}
          onConfirm={onConfirm}
          onCancel={onCancel}
        />
      );

      // Wait for dialog to render with transition
      await waitFor(() => {
        expect(screen.getByText('Alice')).toBeInTheDocument();
      });
    });

    test('shows warning icon', async () => {
      const onConfirm = vi.fn();
      const onCancel = vi.fn();
      const activeUsers = [createMockUser()];

      render(
        <ImportConfirmationDialog
          isOpen={true}
          activeUsers={activeUsers}
          onConfirm={onConfirm}
          onCancel={onCancel}
        />
      );

      // Wait for dialog content to render
      await waitFor(() => {
        expect(screen.getByText(/Replace Workflow/i)).toBeInTheDocument();
      });
    });
  });

  describe('User interactions', () => {
    test('calls onConfirm when Import Anyway clicked', () => {
      const onConfirm = vi.fn();
      const onCancel = vi.fn();
      const activeUsers = [createMockUser()];

      render(
        <ImportConfirmationDialog
          isOpen={true}
          activeUsers={activeUsers}
          onConfirm={onConfirm}
          onCancel={onCancel}
        />
      );

      const confirmButton = screen.getByRole('button', { name: /Import Anyway/i });
      fireEvent.click(confirmButton);

      expect(onConfirm).toHaveBeenCalledTimes(1);
      expect(onCancel).not.toHaveBeenCalled();
    });

    test('calls onCancel when Cancel clicked', () => {
      const onConfirm = vi.fn();
      const onCancel = vi.fn();
      const activeUsers = [createMockUser()];

      render(
        <ImportConfirmationDialog
          isOpen={true}
          activeUsers={activeUsers}
          onConfirm={onConfirm}
          onCancel={onCancel}
        />
      );

      const cancelButton = screen.getByRole('button', { name: /^Cancel$/i });
      fireEvent.click(cancelButton);

      expect(onCancel).toHaveBeenCalledTimes(1);
      expect(onConfirm).not.toHaveBeenCalled();
    });
  });

  describe('Button styling', () => {
    test('Import Anyway button has danger styling', () => {
      const onConfirm = vi.fn();
      const onCancel = vi.fn();
      const activeUsers = [createMockUser()];

      render(
        <ImportConfirmationDialog
          isOpen={true}
          activeUsers={activeUsers}
          onConfirm={onConfirm}
          onCancel={onCancel}
        />
      );

      const confirmButton = screen.getByRole('button', { name: /Import Anyway/i });
      expect(confirmButton.className).toContain('bg-red-600');
    });

    test('Cancel button has secondary styling', () => {
      const onConfirm = vi.fn();
      const onCancel = vi.fn();
      const activeUsers = [createMockUser()];

      render(
        <ImportConfirmationDialog
          isOpen={true}
          activeUsers={activeUsers}
          onConfirm={onConfirm}
          onCancel={onCancel}
        />
      );

      const cancelButton = screen.getByRole('button', { name: /^Cancel$/i });
      expect(cancelButton.className).toContain('bg-white');
      expect(cancelButton.className).toContain('ring-gray-300');
    });
  });
});
