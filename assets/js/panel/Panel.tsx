import type { WithActionProps } from '#/react/lib/with-props';
import type { HTMLAttributes, ReactNode } from 'react';

interface PanelProps extends HTMLAttributes<HTMLDivElement> {
  heading: ReactNode;
  cancelUrl: string;
  className?: string;
  children?: ReactNode;
  footer?: ReactNode;
}

export const Panel: WithActionProps<PanelProps> = ({
  heading,
  cancelUrl,
  className = '',
  children,
  footer,
  navigate
}) => {
  return (
    <div
      className={`absolute right-0 sm:m-4 w-full sm:w-1/2 md:w-1/3 lg:w-1/4 max-h-content ${className}`}
    >
      <div className="divide-y divide-gray-200 rounded-lg bg-white shadow h-full flex flex-col">
        <div className="flex px-4 py-5 sm:px-6">
          <div className="grow font-bold">{heading}</div>
          <div className="flex-none">
            <div
              onClick={() => { navigate(cancelUrl); }}
              className="justify-center hover:text-gray-500 cursor-pointer"
              id="close-panel"
            >
              <span className="hero-x-mark h-4 w-4 inline-block" />
            </div>
          </div>
        </div>
        <div className="px-4 py-5 sm:p-6 grow flex flex-col overflow-visible">
          <div className="md:gap-4 grow flex flex-col overflow-visible">{children}</div>
        </div>
        {footer && (
          <div className="p-3">
            <div className="md:grid md:grid-cols-6 md:gap-4 @container">
              <div className="col-span-6">
                {footer}
              </div>
            </div>
          </div>
        )}
      </div>
    </div>
  );
};
