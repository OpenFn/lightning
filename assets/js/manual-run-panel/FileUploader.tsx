import {
  CloudArrowUpIcon,
  InformationCircleIcon,
  XMarkIcon,
} from '@heroicons/react/24/outline';
import React, { type ChangeEvent } from 'react';

interface FileUploader {
  onUpload: (files: File[]) => void;
  count: number;
  formats: string[];
}

const FileUploader: React.FC<FileUploader> = ({ onUpload, count, formats }) => {
  const dropContainer = React.useRef<HTMLDivElement | null>(null);
  const [dragging, setDragging] = React.useState(false);
  const fileRef = React.useRef<HTMLInputElement | null>(null);
  const [issue, setIssue] = React.useState('');
  const timeout = React.useRef<ReturnType<typeof setTimeout> | null>(null);

  const setVanishingIssue = (issue: string) => {
    setIssue(issue);
    if (timeout.current) clearTimeout(timeout.current);
    timeout.current = setTimeout(() => {
      setIssue('');
      timeout.current = null;
    }, 3500); // wait 3.5secs
  };
  const handleDrop = React.useCallback(
    (type?: string) => (e: DragEvent | ChangeEvent) => {
      let files: File[] = [];

      if (type === 'inputFile' && 'target' in e) {
        const inputEl = e.target as HTMLInputElement;
        if (inputEl.files) files = Array.from(inputEl.files);
      } else if ('dataTransfer' in e) {
        e.preventDefault();
        e.stopPropagation();
        setDragging(false);
        files = Array.from(e.dataTransfer?.files || []);
      }

      const allFilesValid = files.every(file =>
        formats.some(format =>
          file.type.toLowerCase().endsWith(`/${format.toLowerCase()}`)
        )
      );

      if (!allFilesValid) {
        setVanishingIssue(
          `Invalid file format. Please only upload: ${formats.join(', ').toUpperCase()}`
        );
        return;
      }

      if (files.length > count) {
        setVanishingIssue(`Only ${count} files can be uploaded`);
        return;
      } else {
        onUpload(files);
      }
    },
    [count, formats, onUpload]
  );

  React.useEffect(() => {
    const handleDragOver = (e: DragEvent) => {
      e.preventDefault();
      e.stopPropagation();
      setDragging(true);
    };

    const handleDragLeave = (e: DragEvent) => {
      e.preventDefault();
      e.stopPropagation();
      setDragging(false);
    };

    const node = dropContainer.current;
    if (node) {
      node.addEventListener('dragover', handleDragOver);
      node.addEventListener('drop', handleDrop());
      node.addEventListener('dragleave', handleDragLeave);
    }

    return () => {
      if (node) {
        node.removeEventListener('dragover', handleDragOver);
        node.removeEventListener('drop', handleDrop());
        node.removeEventListener('dragleave', handleDragLeave);
      }
    };
  }, [handleDrop]);

  return (
    <>
      <div
        ref={dropContainer}
        className={`${
          dragging
            ? 'border border-blue-400 bg-blue-100'
            : 'border-dashed border-gray-300'
        } mt-2 flex justify-center rounded-lg border border-dashed border-gray-900/25 px-6 py-4 transition-colors duration-200 ease-in-out`}
      >
        <div className="flex flex-col items-center">
          <CloudArrowUpIcon className="mx-auto size-8 text-gray-300" />
          <div className="mt-2 flex flex-wrap justify-center text-sm/6 text-gray-600">
            <label
              htmlFor="uploader"
              className="relative cursor-pointer rounded-md font-semibold text-indigo-600 focus-within:outline-none focus-within:ring-offset-2 hover:text-indigo-500"
            >
              <input
                id="uploader"
                ref={fileRef}
                type="file"
                multiple
                accept={formats.map(f => `.${f}`).join(',')}
                className="opacity-0 hidden"
                onChange={e => {
                  handleDrop('inputFile')(e);
                }}
              />
              <span>Upload a file</span>
            </label>
            <p className="pl-1">or drag and drop</p>
          </div>
          <p className="text-xs/5 text-gray-600">
            {formats.join(', ').toUpperCase()}, up to 8MB
          </p>
        </div>
      </div>

      {issue ? (
        <div className="text-red-700 bg-red-200 px-2 py-1 rounded-lg text-sm flex gap-1 mb-1 justify-between items-center">
          <div className="flex gap-1 items-center">
            <InformationCircleIcon className="size-4" />
            {issue}
          </div>
          <XMarkIcon
            onClick={() => {
              setIssue('');
            }}
            className="size-4 hover:bg-red-700 hover:text-red-50 rounded cursor-pointer"
          />
        </div>
      ) : null}
    </>
  );
};

export default FileUploader;
