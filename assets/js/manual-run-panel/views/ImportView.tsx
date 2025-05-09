import { InformationCircleIcon } from "@heroicons/react/24/outline";
import React from "react";
import FileUploader from "../FileUploader";

const iconStyle = 'h-4 w-4 text-grey-400';

const ImportView: React.FC<{
  pushEvent: (event: string, data: any) => void;
}> = ({ pushEvent }) => {
  const [importedFiles, setImportedFiles] = React.useState<File[]>([]);
  const [isValidJSON, setIsValidJSON] = React.useState(true);

  function uploadFiles(f: File[]) {
    setImportedFiles([...importedFiles, ...f]);
  }

  function deleteFile(indexImg: number) {
    setImportedFiles(prev => prev.filter((_, index) => index !== indexImg));
  }

  React.useEffect(() => {
    if (importedFiles.length === 1) {
      const file = importedFiles[0];
      if (!file) return;
      void readFileContent(file).then(content => {
        // check whether JSON is valid
        try {
          JSON.parse(content);
          setIsValidJSON(true);
          pushEvent('manual_run_change', {
            manual: {
              body: content,
              dataclip_id: null,
            },
          });
        } catch (e) {
          setIsValidJSON(false);
        }
        return;
      });
    } else {
      setIsValidJSON(true);
      pushEvent('manual_run_change', {
        manual: {
          body: null,
          dataclip_id: null,
        },
      });
    }
  }, [importedFiles, importedFiles.length, pushEvent]);

  return (
    <>
      {!isValidJSON ? (
        <div className="text-red-700 text-sm flex gap-1 mb-1 items-center">
          <InformationCircleIcon className={iconStyle} /> File has invalid JSON
          content
        </div>
      ) : null}
      <FileUploader
        currFiles={importedFiles}
        onUpload={uploadFiles}
        onDelete={deleteFile}
        count={1}
        formats={['json']}
      />
    </>
  );
};

export default ImportView;


async function readFileContent(file: File): Promise<string> {
  return new Promise<string>((resolve, reject) => {
    const reader = new FileReader();

    reader.onload = () => {
      resolve(reader.result as string);
    };
    reader.onerror = () => {
      reject(reader.error);
    };

    reader.readAsText(file);
  });
}