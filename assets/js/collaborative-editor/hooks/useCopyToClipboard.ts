import { useState, useCallback, useRef, useEffect } from 'react';

interface UseCopyToClipboardReturn {
  copyStatus: 'idle' | 'copied' | 'error';
  copyText: string; // Display text: '' | 'Copied!' | 'Failed'
  copyToClipboard: (text: string) => Promise<void>;
  isCopied: boolean;
  isError: boolean;
}

/**
 * Hook for copy-to-clipboard functionality with consistent feedback
 *
 * Provides standardized copy behavior:
 * - Shows "Copied!" for 2 seconds on success
 * - Shows "Failed" for 2 seconds on error
 * - Returns to idle state after timeout
 *
 * Button Sizing Strategies (ordered by recommendation):
 *
 * 1. **Invisible spacer** - Recommended for consistent UI (prevents layout shift)
 * 2. **Fixed width** - Simpler alternative for input groups or constrained layouts
 * 3. **Min-width** - For floating buttons that can grow naturally
 *
 * @example Invisible spacer (recommended, prevents layout shift)
 * ```tsx
 * const { copyText, copyToClipboard } = useCopyToClipboard();
 *
 * <div className="flex gap-2">
 *   <button className="px-3 py-2">Download</button>
 *   <button
 *     onClick={() => void copyToClipboard(code)}
 *     className="px-3 py-2 inline-grid"
 *   >
 *     <span className="col-start-1 row-start-1 invisible" aria-hidden="true">
 *       Copy Code
 *     </span>
 *     <span className="col-start-1 row-start-1">
 *       {copyText || 'Copy Code'}
 *     </span>
 *   </button>
 * </div>
 * ```
 *
 * @example Fixed width (simpler, for input groups)
 * ```tsx
 * <div className="flex">
 *   <input type="text" value={url} readOnly className="flex-1 rounded-l-lg" />
 *   <button
 *     onClick={() => void copyToClipboard(url)}
 *     className="w-[100px] rounded-r-lg"
 *   >
 *     {copyText || 'Copy URL'}
 *   </button>
 * </div>
 * ```
 *
 * @example Min-width (for floating buttons that can grow)
 * ```tsx
 * <button
 *   onClick={() => void copyToClipboard(text)}
 *   className="px-2 py-1 rounded"
 * >
 *   {copyText || 'Copy'}
 * </button>
 * ```
 */
export function useCopyToClipboard(): UseCopyToClipboardReturn {
  const [copyStatus, setCopyStatus] = useState<'idle' | 'copied' | 'error'>(
    'idle'
  );
  const timeoutRef = useRef<NodeJS.Timeout | null>(null);

  // Cleanup timeout on unmount
  useEffect(() => {
    return () => {
      if (timeoutRef.current) {
        clearTimeout(timeoutRef.current);
      }
    };
  }, []);

  const copyToClipboard = useCallback(async (text: string) => {
    // Clear any existing timeout
    if (timeoutRef.current) {
      clearTimeout(timeoutRef.current);
    }

    try {
      await navigator.clipboard.writeText(text);
      setCopyStatus('copied');

      timeoutRef.current = setTimeout(() => {
        setCopyStatus('idle');
        timeoutRef.current = null;
      }, 2000);
    } catch (error) {
      console.error('Failed to copy to clipboard:', error);
      setCopyStatus('error');

      timeoutRef.current = setTimeout(() => {
        setCopyStatus('idle');
        timeoutRef.current = null;
      }, 2000);
    }
  }, []);

  const copyText =
    copyStatus === 'copied'
      ? 'Copied!'
      : copyStatus === 'error'
        ? 'Failed'
        : '';

  return {
    copyStatus,
    copyText,
    copyToClipboard,
    isCopied: copyStatus === 'copied',
    isError: copyStatus === 'error',
  };
}
