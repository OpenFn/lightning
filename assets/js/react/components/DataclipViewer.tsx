import { MonacoEditor } from '#/monaco';
import { useEffect, useState } from 'react';

async function fetchDataclipContent(dataclipId: string) {
  try {
    const response = await fetch(`/dataclip/body/${dataclipId}`, {
      cache: 'default',
    });
    if (!response.ok && response.status !== 304) {
      throw new Error('Network response was not ok');
    }

    return await response.text();
  } catch (error) {
    console.error('Error fetching content:', error);
    return 'Failed to load content';
  }
}

export const DataclipViewer = ({ dataclipId }: { dataclipId: string }) => {
  const [content, setContent] = useState<string>('');

  useEffect(() => {
    fetchDataclipContent(dataclipId).then(setContent);
  }, [dataclipId]);

  return (
    <div className='h-full relative overflow-hidden'>
      <MonacoEditor
        defaultLanguage="json"
        theme="default"
        value={content}
        loading={<div>Loading...</div>}
        options={{
          readOnly: true,
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
