import type { HTMLAttributes, ReactNode } from 'react';

import { cn } from '../utils/cn';

interface PanelProps extends HTMLAttributes<HTMLDivElement> {
  heading: ReactNode;
  className?: string;
  children?: ReactNode;
  footer?: ReactNode;
  onClose?: () => void;
  onBack?: () => void;
  fixedHeight?: boolean;
}

export const Panel: React.FC<PanelProps> = ({
  heading,
  className = '',
  children,
  footer,
  onClose,
  onBack,
  fixedHeight = false,
}) => {
  return (
    <div
      className={cn(
        'absolute right-0 sm:m-4 w-full max-w-md flex items-start',
        fixedHeight ? 'top-auto bottom-auto' : 'top-0 bottom-0',
        className
      )}
    >
      <div
        className={cn(
          'flex flex-col w-full rounded-lg bg-white shadow-sm',
          fixedHeight ? 'h-[600px] max-h-full' : 'max-h-full'
        )}
      >
        <div className="px-4 py-5 sm:px-6 border-b border-gray-200 shrink-0">
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-3">
              <button
                type="button"
                onClick={() => {
                  onBack();
                }}
                className="flex items-center justify-center hover:text-gray-500 cursor-pointer text-gray-900"
              >
                <span className="hero-arrow-left h-4 w-4 inline-block" />
                <span className="sr-only">Back</span>
              </button>
              <h2 className="text-base font-semibold text-gray-900 truncate">
                {heading}
              </h2>
            </div>
            <div className="ml-3 flex h-7 items-center">
              <button
                type="button"
                onClick={() => {
                  onClose();
                }}
                className="flex items-center justify-center hover:text-gray-500 cursor-pointer text-gray-900"
                id="close-panel"
              >
                <span className="hero-x-mark h-4 w-4 inline-block" />
                <span className="sr-only">Close</span>
              </button>
            </div>
          </div>
        </div>
        <div className="flex-1 overflow-y-auto px-4 py-5 sm:p-6">
          <div className="flex flex-col h-full">{children}</div>
        </div>
        {footer && (
          <div className="shrink-0 px-4 py-5 sm:px-6 border-t border-gray-200">
            {footer}
          </div>
        )}
      </div>
    </div>
  );
};
