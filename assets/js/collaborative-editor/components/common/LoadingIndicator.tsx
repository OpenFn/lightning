import { Spinner } from './Spinner';

interface LoadingIndicatorProps {
  text?: string;
}

/**
 * LoadingIndicator - Text with spinner for loading states
 *
 * Displays a text message alongside a spinning icon.
 * Used for Monaco editor type definitions loading.
 *
 * @example
 * <LoadingIndicator text="Loading types" />
 * <LoadingIndicator text="Loading workflow" />
 */
export function LoadingIndicator({ text = 'Loading' }: LoadingIndicatorProps) {
  return (
    <div className="inline-block p-2">
      <Spinner size="md" className="inline-block mr-2" />
      <span>{text}</span>
    </div>
  );
}
