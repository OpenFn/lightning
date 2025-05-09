import { MonacoEditor } from "../../monaco";
import { CheckCircleIcon, InformationCircleIcon } from "@heroicons/react/24/outline";
import React from "react";

const iconStyle = 'h-4 w-4 text-grey-400';

const CustomView: React.FC<{
  pushEvent: (event: string, data: any) => void;
}> = ({ pushEvent }) => {
  const [editorValue, setEditorValue] = React.useState('');

  const isEmpty = React.useMemo(() => !editorValue.trim(), [editorValue]);
  const jsonParseResult = React.useMemo(() => {
    try {
      const parsed = JSON.parse(editorValue);
      if (Array.isArray(parsed)) return { success: false, message: "Must be an object" }
      return { success: true }
    } catch (e) {
      return { success: false, message: "Invalid JSON format" }
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
    <div className="relative h-[420px]">
      <div className="font-semibold mb-3 text-gray-600">Create a new input</div>
      {isEmpty || !jsonParseResult.success ? (
        <div className="text-red-700 text-sm flex gap-1 mb-1 items-center">
          <InformationCircleIcon className={iconStyle} />{' '}
          {isEmpty ? "Enter a valid JSON object" : jsonParseResult.message}
        </div>
      ) : (
        <div className="text-gray-700 text-sm flex gap-1 mb-1 items-center">
          <CheckCircleIcon className={iconStyle} />
          Valid JSON
        </div>
      )}
      <MonacoEditor
        defaultLanguage="json"
        theme="default"
        value={editorValue}
        onChange={handleEditorChange}
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
  );
};

export default CustomView;