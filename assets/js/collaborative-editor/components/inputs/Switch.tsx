import { Switch as HeadlessSwitch } from '@headlessui/react';

interface SwitchProps {
  checked: boolean;
  onChange: (checked: boolean) => void;
  disabled?: boolean;
  className?: string;
}

export function Switch({
  checked,
  onChange,
  disabled,
  className,
}: SwitchProps) {
  return (
    <HeadlessSwitch
      checked={checked}
      onChange={onChange}
      disabled={disabled ?? false}
      className={
        className ||
        'group relative inline-flex h-6 w-11 items-center rounded-full bg-gray-200 transition-colors duration-200 ease-in-out border-2 border-transparent data-checked:bg-indigo-600 focus:outline-none cursor-pointer'
      }
    >
      <span className="pointer-events-none absolute h-5 w-5 inline-block transform rounded-full bg-white shadow ring-0 transition duration-200 ease-in-out translate-x-0 group-data-checked:translate-x-5">
        <span
          className="absolute inset-0 flex h-full w-full items-center justify-center transition-opacity duration-200 ease-in opacity-100 group-data-checked:opacity-0"
          aria-hidden="true"
        >
          <span className="hero-x-mark-micro h-4 w-4 text-gray-400" />
        </span>
        <span
          className="absolute inset-0 flex h-full w-full items-center justify-center transition-opacity duration-200 ease-in opacity-0 group-data-checked:opacity-100"
          aria-hidden="true"
        >
          <span className="hero-check-micro h-4 w-4 text-indigo-600" />
        </span>
      </span>
    </HeadlessSwitch>
  );
}
