import { useEffect, useState } from 'react';

import { CodeViewer } from './CodeViewer';

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

  useEffect(() => {
    void (async () => {
      const rawContent = await fetchDataclipContent(dataclipId);
      try {
        const parsed = JSON.parse(rawContent);
        setContent(JSON.stringify(parsed, null, 2));
      } catch {
        setContent(rawContent);
      }
    })();
  }, [dataclipId]);

  return <CodeViewer content={content} />;
};
