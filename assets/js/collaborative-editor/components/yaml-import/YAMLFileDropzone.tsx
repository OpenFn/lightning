/**
 * YAMLFileDropzone - Drag-and-drop file upload component
 *
 * Features:
 * - Drag and drop .yaml/.yml files
 * - Click to browse files
 * - Visual feedback for drag states
 */

import { useState, useCallback } from 'react';

interface YAMLFileDropzoneProps {
  onUpload: (content: string) => void;
}

export function YAMLFileDropzone({ onUpload }: YAMLFileDropzoneProps) {
  const [isDragging, setIsDragging] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const readFile = (file: File) => {
    const reader = new FileReader();
    reader.onload = e => {
      const content = e.target?.result as string;
      onUpload(content);
      setError(null);
    };
    reader.onerror = () => {
      setError('Failed to read file');
    };
    reader.readAsText(file);
  };

  const validateFile = (file: File): boolean => {
    // Check file extension
    const validExtensions = ['.yaml', '.yml'];
    const hasValidExtension = validExtensions.some(ext =>
      file.name.toLowerCase().endsWith(ext)
    );

    if (!hasValidExtension) {
      setError('File must be .yml or .yaml format');
      return false;
    }

    // Check file size (max 8MB as per Phase 3.5 requirements)
    const maxSize = 8 * 1024 * 1024; // 8MB
    if (file.size > maxSize) {
      const fileSizeMB = (file.size / 1024 / 1024).toFixed(1);
      setError(`File size ${fileSizeMB}MB exceeds maximum of 8MB`);
      return false;
    }

    return true;
  };

  const handleDrop = useCallback(
    (e: React.DragEvent<HTMLDivElement>) => {
      e.preventDefault();
      setIsDragging(false);

      const files = Array.from(e.dataTransfer.files);
      if (files.length === 0) return;

      const file = files[0];
      if (file && validateFile(file)) {
        readFile(file);
      }
    },
    [onUpload]
  );

  const handleDragOver = useCallback((e: React.DragEvent<HTMLDivElement>) => {
    e.preventDefault();
    setIsDragging(true);
  }, []);

  const handleDragLeave = useCallback((e: React.DragEvent<HTMLDivElement>) => {
    e.preventDefault();
    setIsDragging(false);
  }, []);

  const handleFileInput = useCallback(
    (e: React.ChangeEvent<HTMLInputElement>) => {
      const files = e.target.files;
      if (!files || files.length === 0) return;

      const file = files[0];
      if (file && validateFile(file)) {
        readFile(file);
      }
    },
    [onUpload]
  );

  return (
    <div className="space-y-2">
      <div
        onDrop={handleDrop}
        onDragOver={handleDragOver}
        onDragLeave={handleDragLeave}
        className={`relative border-2 border-dashed rounded-lg p-6 transition-colors ${
          isDragging
            ? 'border-indigo-500 bg-indigo-50'
            : 'border-gray-300 hover:border-gray-400'
        }`}
      >
        <input
          id="workflow-file"
          type="file"
          accept=".yaml,.yml"
          onChange={handleFileInput}
          className="absolute inset-0 w-full h-full opacity-0 cursor-pointer"
        />
        <div className="text-center">
          <span className="mx-auto hero-cloud-arrow-up size-10 text-gray-300"></span>
          <div className="mt-4 text-sm/6 text-gray-600">
            <label
              htmlFor="workflow-file"
              className="relative cursor-pointer font-semibold text-indigo-600 hover:text-indigo-500"
            >
              Upload a file
            </label>
            <span className="pl-1">or drag and drop</span>
          </div>
          <p className="text-xs/5 text-gray-600">YML or YAML, up to 8MB</p>
        </div>
      </div>
      {error && <p className="text-sm text-red-600 mt-2">{error}</p>}
    </div>
  );
}
