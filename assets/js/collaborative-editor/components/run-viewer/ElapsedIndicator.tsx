import { useEffect, useState } from 'react';

interface ElapsedIndicatorProps {
  startedAt: string | null;
  finishedAt: string | null;
}

// Ported from assets/js/hooks/ElapsedIndicator.ts
function formatParts(elapsedTimeMs: number): [number, string] {
  if (elapsedTimeMs < 1000) {
    return [elapsedTimeMs, 'ms'];
  } else if (elapsedTimeMs < 60 * 1000) {
    const seconds = Math.floor(elapsedTimeMs / 1000);
    return [seconds, 's'];
  } else {
    const minutes = Math.floor(elapsedTimeMs / 1000 / 60);
    return [minutes, 'm'];
  }
}

export function ElapsedIndicator({
  startedAt,
  finishedAt,
}: ElapsedIndicatorProps) {
  const [elapsedText, setElapsedText] = useState<string>('Not started');

  useEffect(() => {
    if (!startedAt) {
      setElapsedText('Not started');
      return undefined;
    }

    const startTime = new Date(startedAt).getTime();
    const finishTime = finishedAt ? new Date(finishedAt).getTime() : null;

    const updateTime = () => {
      const elapsedTime = (finishTime || Date.now()) - startTime;
      const [elapsedTimeNum, elapsedTimeUnit] = formatParts(elapsedTime);
      setElapsedText(`${elapsedTimeNum} ${elapsedTimeUnit}`);
    };

    // Initial update
    updateTime();

    // Only update every second if the run is still running
    if (!finishTime) {
      const interval = setInterval(updateTime, 1000);
      return () => clearInterval(interval);
    }

    return undefined;
  }, [startedAt, finishedAt]);

  return <span>{elapsedText}</span>;
}
