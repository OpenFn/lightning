import type { HTMLAttributes, ReactNode } from 'react';

import { cn } from '../utils/cn';

interface PanelProps extends HTMLAttributes<HTMLDivElement> {
  heading: ReactNode;
  className?: string;
  children?: ReactNode;
  footer?: ReactNode;
  onClose?: () => void;
  onBack?: () => void;
}

export const Panel: React.FC<PanelProps> = ({
  heading,
  className = '',
  children,
  footer,
  onClose,
  onBack,
}) => {
  return (
    <div
      className={cn(
        'absolute right-0 sm:m-4 w-full sm:w-1/2 md:w-1/3 lg:w-1/4 max-h-content',
        className
      )}
    >
      <div className="divide-y divide-gray-200 rounded-lg bg-white shadow h-full flex flex-col">
        <div className="flex px-4 py-5 sm:px-6 gap-2 items-center">
          <div className="flex-none flex items-center">
            <div
              onClick={() => {
                onBack();
              }}
              className="justify-center flex items-center hover:text-gray-500 cursor-pointer"
            >
              <span className="hero-arrow-left h-4 w-4 inline-block" />
            </div>
          </div>
          <div className="grow font-bold truncate">{heading}</div>
          <div className="flex-none flex items-center">
            <div
              onClick={() => {
                onClose();
              }}
              className="justify-center flex items-center hover:text-gray-500 cursor-pointer"
              id="close-panel"
            >
              <span className="hero-x-mark h-4 w-4 inline-block" />
            </div>
          </div>
        </div>
        <div className="px-4 py-5 sm:p-6 grow flex flex-col overflow-visible h-130">
          <div className="md:gap-4 grow flex flex-col overflow-visible">
            {children}
          </div>
        </div>
        {footer && (
          <div className="p-3 z-50 bg-white rounded-lg">
            <div className="md:grid md:grid-cols-6 md:gap-4 @container">
              <div className="col-span-6">{footer}</div>
            </div>
          </div>
        )}
      </div>
    </div>
  );
};
