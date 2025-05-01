import { InformationCircleIcon } from "@heroicons/react/24/outline";
import { CloudArrowUpIcon, XMarkIcon } from "@heroicons/react/24/solid";
import React, { type ChangeEvent } from "react";

export interface UploadedFile {
  name: string;
  type: string;
  size: number;
}

interface FileUploader {
  currFiles: UploadedFile[];
  onUpload: (files: UploadedFile[]) => void;
  onDelete: (index: number) => void;
  count: number;
  formats: string[];
}

const FileUploader: React.FC<FileUploader> = ({
  currFiles,
  onUpload,
  onDelete,
  count,
  formats
}) => {
  const dropContainer = React.useRef<HTMLDivElement | null>(null);
  const [dragging, setDragging] = React.useState(false);
  const fileRef = React.useRef<HTMLInputElement | null>(null);
  const [issue, setIssue] = React.useState("");
  const timeout = React.useRef<ReturnType<typeof setTimeout> | null>(null)


  const setVanishingIssue = (issue: string) => {
    setIssue(issue);
    if (timeout.current) clearTimeout(timeout.current);
    timeout.current = setTimeout(() => {
      setIssue("");
      timeout.current = null;
    }, 3500); // wait 3.5secs
  }
  const handleDrop = React.useCallback((type?: string) => (e: DragEvent | ChangeEvent) => {
    let files: File[] = [];

    if (type === "inputFile" && "target" in e) {
      const inputEl = e.target as HTMLInputElement;
      if (inputEl.files) files = Array.from(inputEl.files);
    } else if ("dataTransfer" in e) {
      e.preventDefault();
      e.stopPropagation();
      setDragging(false);
      files = Array.from(e.dataTransfer?.files || []);
    }

    const allFilesValid = files.every((file) =>
      formats.some((format) => file.type.toLowerCase().endsWith(`/${format.toLowerCase()}`))
    );

    if (!allFilesValid) {
      setVanishingIssue(`Invalid file format. Please only upload: ${formats.join(", ").toUpperCase()}`);
      return;
    }

    if (currFiles.length + files.length > count) {
      setVanishingIssue(`Only ${count} files can be uploaded`)
      return;
    } else {
      onUpload(files.map(file => ({ name: file.name, type: file.type, size: file.size })));
    }

  }, [count, currFiles.length, formats, onUpload])

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
      node.addEventListener("dragover", handleDragOver);
      node.addEventListener("drop", handleDrop());
      node.addEventListener("dragleave", handleDragLeave);
    }

    return () => {
      if (node) {
        node.removeEventListener("dragover", handleDragOver);
        node.removeEventListener("drop", handleDrop());
        node.removeEventListener("dragleave", handleDragLeave);
      }
    };
  }, [currFiles, handleDrop]);

  return (
    <>
      {issue ? <div className="text-red-700 bg-red-200 px-2 py-1 rounded-lg text-sm flex gap-1 mb-1 items-center justify-between items-center">
        <div className="flex gap-1 items-center"><InformationCircleIcon className="size-4" />{issue}</div>
        <XMarkIcon onClick={() => { setIssue("") }} className="size-4 hover:bg-red-700 hover:text-red-50 rounded cursor-pointer" />
      </div> : null}

      {currFiles.length > 0 && (
        <div className="mt-4 grid grid-cols-2 gap-4">
          {currFiles.map((file, index) => (
            <div
              key={index}
              className="w-full p-4 rounded-md bg-gray-100 space-y-3"
            >
              <div className="flex justify-between items-center">
                <div className="w-[70%] cursor-pointer">
                  <div className="text-sm font-medium text-gray-700">{file.name}</div>
                  <div className="text-xs text-gray-500">{Math.floor(file.size / 1024)} KB</div>
                </div>
                <button
                  className="text-sm text-red-500"
                  onClick={() => { onDelete(index) }}
                >
                  ✕
                </button>
              </div>
            </div>
          ))}
        </div>
      )}
      <div
        ref={dropContainer}
        className={`${dragging ? "border border-blue-400 bg-blue-100" : "border-dashed border-gray-300"
          } grow flex items-center justify-center text-center border-2 rounded-md mt-4 py-5`}
      >
        <div className="flex flex-col items-center">
          <CloudArrowUpIcon className="size-16 text-[#9CA3AF]" />
          <div className=" text-gray-500">
            <input
              ref={fileRef}
              type="file"
              multiple
              accept={formats.map(f => `.${f}`).join(",")}
              className="opacity-0 hidden"
              onChange={(e) => { handleDrop("inputFile")(e) }}
            />
            <span
              className="font-semibold text-[#6466E9] cursor-pointer"
              onClick={() => fileRef.current?.click()}
            >
              Click to upload
            </span>{" "}
            or drag and drop
          </div>
          <div className="text-xs text-gray-500 mt-1">
            Max {count} file(s): {formats.join(", ").toUpperCase()}
          </div>
        </div>
      </div>
    </>
  );
}

export default FileUploader