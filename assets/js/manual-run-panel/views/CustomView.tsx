import { InformationCircleIcon } from '@heroicons/react/24/outline';
import React from 'react';

import { cn } from '#/utils/cn';

import { MonacoEditor } from '../../monaco';
import { addKeyboardShortcutOverrides } from '../../monaco/keyboard-overrides';
import FileUploader from '../FileUploader';

const iconStyle = 'h-4 w-4 text-grey-400';

const CustomView: React.FC<{
  pushEvent: (event: string, data: any) => void;
  renderMode?: 'standalone' | 'embedded';
}> = ({ pushEvent, renderMode = 'standalone' }) => {
  const [editorValue, setEditorValue] = React.useState('');

  async function uploadFiles(f: File[]) {
    if (f.length) {
      const file = f[0];
      if (file) {
        const content = await readFileContent(file);
        try {
          handleEditorChange(JSON.stringify(JSON.parse(content), undefined, 2));
        } catch (e: any) {
          handleEditorChange(content);
        }
      }
    }
  }

  const isEmpty = React.useMemo(() => !editorValue.trim(), [editorValue]);
  const jsonParseResult = React.useMemo(() => {
    try {
      const parsed = JSON.parse(editorValue);
      if (Array.isArray(parsed))
        return { success: false, message: 'Must be an object' };
      return { success: true };
    } catch (e) {
      return { success: false, message: 'Invalid JSON format' };
    }
  }, [editorValue]);

  const handleEditorChange = React.useCallback(
    (value: string) => {
      setEditorValue(value);
      pushEvent('manual_run_change', {
        manual: {
          body: value,
          dataclip_id: null,
        },
      });
    },
    [pushEvent]
  );

  return (
    <div
      className={cn(
        'h-full flex flex-col',
        renderMode === 'embedded' ? 'pt-2' : 'pt-3'
      )}
    >
      <div className="px-3 shrink-0">
        <FileUploader count={1} formats={['json']} onUpload={uploadFiles} />
        <div className="relative">
          <div
            className="absolute inset-0 flex items-center"
            aria-hidden="true"
          >
            <div className="w-full border-t border-gray-300"></div>
          </div>
          <div className="relative flex justify-center">
            <span className="bg-white px-2 text-sm text-gray-500 py-2">OR</span>
          </div>
        </div>
      </div>
      <div className="relative flex-1 min-h-0 flex flex-col overflow-hidden">
        {!isEmpty && !jsonParseResult.success ? (
          <div className="text-red-700 text-sm flex gap-1 mb-1 items-center">
            <InformationCircleIcon className={iconStyle} />{' '}
            {jsonParseResult.message}
          </div>
        ) : null}
        <div className="overflow-hidden flex-1">
          <MonacoEditor
            defaultLanguage="json"
            theme="default"
            value={editorValue}
            onChange={handleEditorChange}
            onMount={(editor, monaco) => {
              addKeyboardShortcutOverrides(editor, monaco);
            }}
            loading={<div>Loading...</div>}
            options={{
              readOnly: false,
              lineNumbersMinChars: 3,
              tabSize: 2,
              scrollBeyondLastLine: false,
              overviewRulerLanes: 0,
              overviewRulerBorder: false,
              fontFamily: 'Fira Code VF',
              fontSize: 14,
              fontLigatures: true,
              minimap: {
                enabled: false,
              },
              wordWrap: 'on',
            }}
          />
        </div>
      </div>
    </div>
  );
};

export default CustomView;

export async function readFileContent(file: File): Promise<string> {
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
