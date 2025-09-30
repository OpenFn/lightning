import { MonacoEditor } from '#/monaco';
import { useEffect, useState } from 'react';

async function fetchDataclipContent(dataclipId: string) {
  try {
    const response = await fetch(`/dataclip/body/${dataclipId}`);
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
  const [copied, setCopied] = useState(false);

  useEffect(() => {
    fetchDataclipContent(dataclipId).then(setContent);
  }, [dataclipId]);

  const handleCopy = async () => {
    try {
      // @ts-expect-error - clipboard API not in type definitions
      if (navigator.clipboard?.writeText) {
        // @ts-expect-error - clipboard API not in type definitions
        await navigator.clipboard.writeText(content);
        setCopied(true);
        setTimeout(() => setCopied(false), 2000);
      }
    } catch (error) {
      console.error('Failed to copy:', error);
    }
  };

  return (
    <div className='h-full relative overflow-hidden'>
      {content && content !== 'Failed to load content' && (
        <button
          onClick={handleCopy}
          className="absolute top-2 right-2 z-10 inline-flex items-center gap-1.5 px-3 py-1.5 text-sm bg-white/90 hover:bg-white border border-gray-300 rounded-md shadow-sm text-gray-700 hover:text-gray-900 focus:outline-none focus:ring-2 focus:ring-primary-500"
          title="Copy JSON to clipboard"
        >
          {copied ? (
            <>
              <svg className="w-4 h-4 text-green-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M5 13l4 4L19 7" />
              </svg>
              <span className="text-green-600">Copied!</span>
            </>
          ) : (
            <>
              <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M8 16H6a2 2 0 01-2-2V6a2 2 0 012-2h8a2 2 0 012 2v2m-6 12h8a2 2 0 002-2v-8a2 2 0 00-2-2h-8a2 2 0 00-2 2v8a2 2 0 002 2z" />
              </svg>
              <span>Copy</span>
            </>
          )}
        </button>
      )}
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
