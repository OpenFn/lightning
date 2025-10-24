import type { ReactNode } from "react";

// import _logger from "#/utils/logger";

// const logger = _logger.ns("InspectorLayout").seal();

interface InspectorLayoutProps {
  title: string;
  nodeType?: "job" | "trigger" | "edge";
  onClose: () => void;
  footer?: ReactNode;
  children: ReactNode;
  "data-testid"?: string;
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
  "data-testid": dataTestId,
}: InspectorLayoutProps) {
  return (
    <div
      className="pointer-events-auto w-screen max-w-md h-full"
      data-testid={dataTestId}
    >
      <div className="relative flex h-full flex-col divide-y divide-gray-200 bg-white shadow-xl">
        {/* Header */}
        <div className="flex min-h-0 flex-1 flex-col overflow-y-auto py-6">
          <div className="px-4 sm:px-6">
            <div className="flex items-start justify-between">
              <h2 className="text-base font-semibold text-gray-900">{title}</h2>
              <div className="ml-3 flex h-7 items-center">
                <button
                  type="button"
                  onClick={onClose}
                  className="relative rounded-md text-gray-400 hover:text-gray-500 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-indigo-600"
                >
                  <span className="absolute -inset-2.5" />
                  <span className="sr-only">Close panel</span>
                  <div className="hero-x-mark size-6" />
                </button>
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
          <div className="relative mt-6 flex-1 px-4 sm:px-6">{children}</div>
        </div>

        {/* Footer - only render if provided */}
        {footer && <div className="shrink-0 px-4 py-4">{footer}</div>}
      </div>
    </div>
  );
}
