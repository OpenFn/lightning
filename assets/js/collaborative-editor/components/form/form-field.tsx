import { Tooltip } from '../../../components/Tooltip';

import { ErrorMessage } from './error-message';

export const INPUT_CLASSES =
  'focus:outline focus:outline-2 focus:outline-offset-1 block w-full rounded-lg text-slate-900 focus:ring-0 sm:text-sm sm:leading-6 disabled:cursor-not-allowed disabled:bg-gray-50 disabled:text-gray-500 border-slate-300 focus:border-slate-400 focus:outline-indigo-600';

interface FormFieldProps {
  name: string;
  label: string;
  meta: any; // TanStack Form meta type
  helpText?: string | undefined;
  labelTooltip?: React.ReactNode | undefined;
  children: React.ReactNode;
}

export function FormField({
  name,
  label,
  meta,
  helpText,
  labelTooltip,
  children,
}: FormFieldProps) {
  return (
    <div>
      <label
        htmlFor={name}
        className="text-sm/6 font-medium text-slate-800 mb-2 flex items-center gap-2"
      >
        {label}
        {labelTooltip && (
          <Tooltip content={labelTooltip} side="right">
            <span className="hero-information-circle h-4 w-4 text-gray-400 cursor-help" />
          </Tooltip>
        )}
      </label>
      {children}
      {helpText && (
        <p className="text-xs text-gray-500 mt-1 italic">{helpText}</p>
      )}
      <ErrorMessage meta={meta} />
    </div>
  );
}
