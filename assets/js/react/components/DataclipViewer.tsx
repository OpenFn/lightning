import { useEffect, useState } from 'react';

import { CodeViewer } from './CodeViewer';

type FetchResult =
  | { kind: 'ok'; body: string }
  | { kind: 'not-found' }
  | { kind: 'error' };

async function fetchDataclipContent(dataclipId: string): Promise<FetchResult> {
  try {
    const response = await fetch(`/dataclip/body/${dataclipId}`);

    if (response.status === 404) {
      return { kind: 'not-found' };
    }

    if (!response.ok) {
      console.error(
        `Error fetching content: unexpected status ${response.status}`
      );
      return { kind: 'error' };
    }

    return { kind: 'ok', body: await response.text() };
  } catch (error) {
    console.error('Error fetching content:', error);
    return { kind: 'error' };
  }
}

export const DataclipViewer = ({ dataclipId }: { dataclipId: string }) => {
  const [content, setContent] = useState<string>('');

  useEffect(() => {
    void (async () => {
      const result = await fetchDataclipContent(dataclipId);

      switch (result.kind) {
        case 'ok':
          try {
            const parsed = JSON.parse(result.body);
            setContent(JSON.stringify(parsed, null, 2));
          } catch {
            setContent(result.body);
          }
          break;
        case 'not-found':
          setContent('Dataclip not found');
          break;
        case 'error':
          setContent('Failed to load content');
          break;
      }
    })();
  }, [dataclipId]);

  return <CodeViewer content={content} />;
};
