import { toast } from 'sonner';
import { describe, it, expect, beforeEach, vi } from 'vitest';

import { notifications } from '../../../js/collaborative-editor/lib/notifications';

// Mock Sonner
vi.mock('sonner', () => ({
  toast: {
    info: vi.fn(),
    error: vi.fn(),
    success: vi.fn(),
    warning: vi.fn(),
    dismiss: vi.fn(),
  },
}));

describe('notifications', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  describe('info', () => {
    it('calls toast.info with correct title and description', () => {
      notifications.info({
        title: 'Test Title',
        description: 'Test Description',
      });

      expect(toast.info).toHaveBeenCalledWith(
        'Test Title',
        expect.objectContaining({
          description: 'Test Description',
        })
      );
    });

    it('applies blue color scheme styling with !important', () => {
      notifications.info({ title: 'Test' });

      expect(toast.info).toHaveBeenCalledWith(
        'Test',
        expect.objectContaining({
          classNames: {
            toast: '!bg-blue-50 !border-l-4 !border-l-blue-500',
            title: '!text-blue-900 !font-semibold',
            description: '!text-blue-700 !text-sm',
            icon: '!text-blue-500',
          },
        })
      );
    });

    it('sets 2 second duration for info messages', () => {
      notifications.info({ title: 'Test' });

      expect(toast.info).toHaveBeenCalledWith(
        'Test',
        expect.objectContaining({
          duration: 2000,
        })
      );
    });

    it('allows duration override', () => {
      notifications.info({ title: 'Test', duration: 5000 });

      expect(toast.info).toHaveBeenCalledWith(
        'Test',
        expect.objectContaining({
          duration: 5000,
        })
      );
    });

    it('passes through additional Sonner options', () => {
      notifications.info({
        title: 'Test',
        action: {
          label: 'Undo',
          onClick: () => {},
        },
      });

      expect(toast.info).toHaveBeenCalledWith(
        'Test',
        expect.objectContaining({
          action: expect.objectContaining({
            label: 'Undo',
          }),
        })
      );
    });
  });

  describe('alert', () => {
    it('calls toast.error with correct title and description', () => {
      notifications.alert({
        title: 'Error Title',
        description: 'Error Description',
      });

      expect(toast.error).toHaveBeenCalledWith(
        'Error Title',
        expect.objectContaining({
          description: 'Error Description',
        })
      );
    });

    it('applies red color scheme styling with !important', () => {
      notifications.alert({ title: 'Error' });

      expect(toast.error).toHaveBeenCalledWith(
        'Error',
        expect.objectContaining({
          classNames: {
            toast: '!bg-red-50 !border-l-4 !border-l-red-500',
            title: '!text-red-900 !font-semibold',
            description: '!text-red-700 !text-sm',
            icon: '!text-red-500',
          },
        })
      );
    });

    it('sets 4 second duration for alert messages', () => {
      notifications.alert({ title: 'Error' });

      expect(toast.error).toHaveBeenCalledWith(
        'Error',
        expect.objectContaining({
          duration: 4000,
        })
      );
    });
  });

  describe('success', () => {
    it('calls toast.success with green color scheme and !important', () => {
      notifications.success({ title: 'Success' });

      expect(toast.success).toHaveBeenCalledWith(
        'Success',
        expect.objectContaining({
          classNames: {
            toast: '!bg-green-50 !border-l-4 !border-l-green-500',
            title: '!text-green-900 !font-semibold',
            description: '!text-green-700 !text-sm',
            icon: '!text-green-500',
          },
        })
      );
    });

    it('sets 2 second duration', () => {
      notifications.success({ title: 'Success' });

      expect(toast.success).toHaveBeenCalledWith(
        'Success',
        expect.objectContaining({
          duration: 2000,
        })
      );
    });
  });

  describe('warning', () => {
    it('calls toast.warning with amber color scheme and !important', () => {
      notifications.warning({ title: 'Warning' });

      expect(toast.warning).toHaveBeenCalledWith(
        'Warning',
        expect.objectContaining({
          classNames: {
            toast: '!bg-amber-50 !border-l-4 !border-l-amber-500',
            title: '!text-amber-900 !font-semibold',
            description: '!text-amber-700 !text-sm',
            icon: '!text-amber-500',
          },
        })
      );
    });

    it('sets 3 second duration', () => {
      notifications.warning({ title: 'Warning' });

      expect(toast.warning).toHaveBeenCalledWith(
        'Warning',
        expect.objectContaining({
          duration: 3000,
        })
      );
    });
  });

  describe('dismiss', () => {
    it('calls toast.dismiss with no arguments to dismiss all', () => {
      notifications.dismiss();

      expect(toast.dismiss).toHaveBeenCalledWith(undefined);
    });

    it('calls toast.dismiss with toast ID to dismiss specific toast', () => {
      const toastId = 'toast-123';
      notifications.dismiss(toastId);

      expect(toast.dismiss).toHaveBeenCalledWith(toastId);
    });
  });
});
