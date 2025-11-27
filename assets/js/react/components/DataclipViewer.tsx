import { useEffect, useState } from 'react';

import { MonacoEditor } from '#/monaco';

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
    void fetchDataclipContent(dataclipId).then(rawContent => {
      // Format JSON once when it loads
      try {
        const parsed = JSON.parse(rawContent);
        setContent(JSON.stringify(parsed, null, 2));
      } catch {
        // If not valid JSON, use as-is
        setContent(rawContent);
      }
    });
  }, [dataclipId]);

  const handleCopy = (e: React.MouseEvent<HTMLButtonElement>) => {
    const clipboard = (
      navigator as {
        clipboard?: { writeText: (text: string) => Promise<void> };
      }
    ).clipboard;

    // Remove focus after click to prevent outline
    const button = e.currentTarget as unknown as { blur: () => void };
    button.blur();

    if (clipboard?.writeText) {
      void clipboard
        .writeText(content)
        .then(() => {
          setCopied(true);
          setTimeout(() => setCopied(false), 2000);
          return;
        })
        .catch((error: unknown) => {
          console.error('Failed to copy:', error);
        });
    }
  };

  return (
    <div className="h-full relative">
      {content && content !== 'Failed to load content' && (
        <button
          onClick={handleCopy}
          className="absolute top-3 right-3 z-10 p-1.5 rounded text-gray-400 hover:text-gray-600 hover:bg-gray-100/80 focus:outline-none transition-colors"
          title={copied ? 'Copied!' : 'Copy to clipboard'}
          aria-label={copied ? 'Copied to clipboard' : 'Copy to clipboard'}
        >
          {copied ? (
            <svg
              className="w-4 h-4 text-green-600"
              fill="none"
              stroke="currentColor"
              viewBox="0 0 24 24"
            >
              <path
                strokeLinecap="round"
                strokeLinejoin="round"
                strokeWidth={2}
                d="M5 13l4 4L19 7"
              />
            </svg>
          ) : (
            <svg
              className="w-4 h-4"
              fill="none"
              stroke="currentColor"
              viewBox="0 0 24 24"
            >
              <path
                strokeLinecap="round"
                strokeLinejoin="round"
                strokeWidth={2}
                d="M8 16H6a2 2 0 01-2-2V6a2 2 0 012-2h8a2 2 0 012 2v2m-6 12h8a2 2 0 002-2v-8a2 2 0 00-2-2h-8a2 2 0 00-2 2v8a2 2 0 002 2z"
              />
            </svg>
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
          fixedOverflowWidgets: true,
          minimap: {
            enabled: false,
          },
          wordWrap: 'on',
        }}
      />
    </div>
  );
};
