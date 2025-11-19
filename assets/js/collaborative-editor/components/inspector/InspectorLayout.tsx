import type { ReactNode } from 'react';

import { Button } from '../Button';

// import _logger from "#/utils/logger";

// const logger = _logger.ns("InspectorLayout").seal();

interface InspectorLayoutProps {
  title: string;
  nodeType?: 'job' | 'trigger' | 'edge';
  onClose: () => void;
  footer?: ReactNode;
  children: ReactNode;
  'data-testid'?: string;
  fixedHeight?: boolean;
  showBackButton?: boolean;
  fullHeight?: boolean;
}

/**
 * Reusable layout shell for all inspector panels.
 * Provides consistent header, scrollable content area, optional footer,
 * and keyboard shortcut handling (Escape to close).
 */
export function InspectorLayout({
  title,
  nodeType,
  onClose,
  footer,
  children,
  'data-testid': dataTestId,
  fixedHeight = false,
  showBackButton = false,
  fullHeight = false,
}: InspectorLayoutProps) {
  return (
    <div
      className="pointer-events-auto w-screen max-w-md h-full flex items-start justify-end p-6"
      data-testid={dataTestId}
    >
      <div
        className={`relative flex flex-col bg-white shadow-sm rounded-lg w-full ${
          fixedHeight
            ? 'h-[600px] max-h-full'
            : fullHeight
              ? 'max-h-full min-h-0'
              : 'max-h-full'
        }`}
      >
        {/* Header */}
        <div className="px-6 py-4 border-b border-gray-200">
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-3">
              {showBackButton && (
                <button
                  type="button"
                  onClick={onClose}
                  className="flex items-center justify-center hover:text-gray-500 cursor-pointer text-gray-900"
                >
                  <span className="hero-arrow-left h-4 w-4 inline-block" />
                  <span className="sr-only">Back</span>
                </button>
              )}
              <h2 className="text-base font-semibold text-gray-900">{title}</h2>
            </div>
            <div className="ml-3 flex h-7 items-center">
              <Button variant="nakedClose" onClick={onClose} />
            </div>
          </div>
          {nodeType && (
            <div className="mt-2">
              <span className="text-xs bg-gray-100 px-2 py-1 rounded">
                {nodeType}
              </span>
            </div>
          )}
        </div>

        {/* Scrollable content */}
        <div className="flex-1 overflow-y-auto">{children}</div>

        {/* Footer - only render if provided */}
        {footer && (
          <div className="shrink-0 px-6 py-4 border-t border-gray-200">
            {footer}
          </div>
        )}
      </div>
    </div>
  );
}
