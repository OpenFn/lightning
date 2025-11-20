/**
 * YAMLFileDropzone Component Tests
 *
 * Tests file upload validation, drag-and-drop functionality, and error handling
 */

import { describe, expect, test, vi } from 'vitest';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { YAMLFileDropzone } from '../../../../js/collaborative-editor/components/yaml-import/YAMLFileDropzone';

// Mock FileReader
class MockFileReader {
  result: string | ArrayBuffer | null = null;
  onload: ((this: FileReader, ev: ProgressEvent<FileReader>) => any) | null =
    null;
  onerror: ((this: FileReader, ev: ProgressEvent<FileReader>) => any) | null =
    null;

  readAsText(file: Blob) {
    setTimeout(() => {
      this.result = 'name: Test Workflow';
      if (this.onload) {
        this.onload({ target: this } as any);
      }
    }, 0);
  }
}

global.FileReader = MockFileReader as any;

describe('YAMLFileDropzone', () => {
  describe('File validation', () => {
    test('accepts .yaml files', async () => {
      const onUpload = vi.fn();
      render(<YAMLFileDropzone onUpload={onUpload} />);

      const file = new File(['name: Test'], 'test.yaml', { type: 'text/yaml' });
      const input = document.querySelector(
        'input[type="file"]'
      ) as HTMLInputElement;

      fireEvent.change(input, { target: { files: [file] } });

      await waitFor(() => {
        expect(onUpload).toHaveBeenCalledWith('name: Test Workflow');
      });
    });

    test('accepts .yml files', async () => {
      const onUpload = vi.fn();
      render(<YAMLFileDropzone onUpload={onUpload} />);

      const file = new File(['name: Test'], 'test.yml', { type: 'text/yaml' });
      const input = document.querySelector(
        'input[type="file"]'
      ) as HTMLInputElement;

      fireEvent.change(input, { target: { files: [file] } });

      await waitFor(() => {
        expect(onUpload).toHaveBeenCalled();
      });
    });

    test('rejects non-YAML files', async () => {
      const onUpload = vi.fn();
      render(<YAMLFileDropzone onUpload={onUpload} />);

      const file = new File(['test'], 'test.txt', { type: 'text/plain' });
      const input = document.querySelector(
        'input[type="file"]'
      ) as HTMLInputElement;

      fireEvent.change(input, { target: { files: [file] } });

      await waitFor(() => {
        expect(
          screen.getByText(/File must be .yml or .yaml format/i)
        ).toBeInTheDocument();
        expect(onUpload).not.toHaveBeenCalled();
      });
    });

    test('rejects files larger than 8MB', async () => {
      const onUpload = vi.fn();
      render(<YAMLFileDropzone onUpload={onUpload} />);

      // Create a file larger than 8MB
      const largeContent = 'x'.repeat(9 * 1024 * 1024); // 9MB
      const file = new File([largeContent], 'large.yaml', {
        type: 'text/yaml',
      });
      Object.defineProperty(file, 'size', { value: 9 * 1024 * 1024 });

      const input = document.querySelector(
        'input[type="file"]'
      ) as HTMLInputElement;

      fireEvent.change(input, { target: { files: [file] } });

      await waitFor(() => {
        expect(screen.getByText(/exceeds maximum of 8MB/i)).toBeInTheDocument();
        expect(onUpload).not.toHaveBeenCalled();
      });
    });

    test('accepts files exactly at 8MB limit', async () => {
      const onUpload = vi.fn();
      render(<YAMLFileDropzone onUpload={onUpload} />);

      const content = 'x'.repeat(8 * 1024 * 1024);
      const file = new File([content], 'exact.yaml', { type: 'text/yaml' });
      Object.defineProperty(file, 'size', { value: 8 * 1024 * 1024 });

      const input = document.querySelector(
        'input[type="file"]'
      ) as HTMLInputElement;

      fireEvent.change(input, { target: { files: [file] } });

      await waitFor(() => {
        expect(screen.queryByText(/exceeds maximum/i)).not.toBeInTheDocument();
        expect(onUpload).toHaveBeenCalled();
      });
    });
  });

  describe('Drag and drop', () => {
    test('shows visual feedback during drag', () => {
      const onUpload = vi.fn();
      const { container } = render(<YAMLFileDropzone onUpload={onUpload} />);

      const dropzone = container.querySelector('div[class*="border-dashed"]')!;

      fireEvent.dragOver(dropzone);

      expect(dropzone.className).toContain('border-indigo-500');
      expect(dropzone.className).toContain('bg-indigo-50');
    });

    test('removes visual feedback when drag leaves', () => {
      const onUpload = vi.fn();
      const { container } = render(<YAMLFileDropzone onUpload={onUpload} />);

      const dropzone = container.querySelector('div[class*="border-dashed"]')!;

      fireEvent.dragOver(dropzone);
      fireEvent.dragLeave(dropzone);

      expect(dropzone.className).not.toContain('border-indigo-500');
    });

    test('handles file drop', async () => {
      const onUpload = vi.fn();
      const { container } = render(<YAMLFileDropzone onUpload={onUpload} />);

      const dropzone = container.querySelector('div[class*="border-dashed"]')!;
      const file = new File(['name: Test'], 'test.yaml', { type: 'text/yaml' });

      const dropEvent = new Event('drop', { bubbles: true });
      Object.defineProperty(dropEvent, 'dataTransfer', {
        value: { files: [file] },
      });

      fireEvent(dropzone, dropEvent);

      await waitFor(() => {
        expect(onUpload).toHaveBeenCalled();
      });
    });
  });

  describe('UI elements', () => {
    test('displays upload instructions', () => {
      const onUpload = vi.fn();
      render(<YAMLFileDropzone onUpload={onUpload} />);

      expect(screen.getByText(/Upload a file/i)).toBeInTheDocument();
      expect(screen.getByText(/or drag and drop/i)).toBeInTheDocument();
      expect(screen.getByText(/YML or YAML, up to 8MB/i)).toBeInTheDocument();
    });

    test('displays upload icon', () => {
      const onUpload = vi.fn();
      const { container } = render(<YAMLFileDropzone onUpload={onUpload} />);

      const icon = container.querySelector('span.hero-cloud-arrow-up');
      expect(icon).toBeInTheDocument();
    });

    test('has accessible file input', () => {
      const onUpload = vi.fn();
      render(<YAMLFileDropzone onUpload={onUpload} />);

      const input = document.querySelector(
        'input[type="file"]'
      ) as HTMLInputElement;
      expect(input).toBeInTheDocument();
      expect(input).toHaveAttribute('accept', '.yaml,.yml');
    });
  });
});
