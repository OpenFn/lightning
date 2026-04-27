import { Menu, MenuButton, MenuItem, MenuItems } from '@headlessui/react';

import { useCanRun } from '../hooks/useWorkflow';

import { Button } from './Button';
import { ShortcutKeys } from './ShortcutKeys';
import { Tooltip } from './Tooltip';

interface NewRunButtonProps {
  onClick: () => void;
  onRunWithCustomInputClick?: () => void;
  disabled?: boolean;
  isRunning?: boolean;
  tooltipSide?: 'top' | 'bottom';
  text?: string;
}

/**
 * NewRunButton - Standardized button for opening the manual run panel.
 *
 * Displays a play icon with "Run" text. Shows a spinner when isRunning=true.
 * When onRunWithCustomInputClick is provided, renders as a split button with a
 * dropdown containing a "Run with custom input" option.
 *
 * Used in:
 * - Header (canvas)
 * - TriggerInspector
 * - JobInspector
 * - FullScreenIDE (before panel open)
 */
export function NewRunButton({
  onClick,
  onRunWithCustomInputClick,
  disabled: disabledProp,
  isRunning = false,
  tooltipSide = 'bottom',
  text = 'Run',
}: NewRunButtonProps) {
  const { canRun, tooltipMessage } = useCanRun();

  // Disable if parent requests, canRun is false, or a run is in progress
  const isDisabled = disabledProp || !canRun || isRunning;

  const tooltip = canRun ? (
    <ShortcutKeys keys={['mod', 'enter']} />
  ) : (
    tooltipMessage
  );

  const icon = isRunning ? (
    <span className="hero-arrow-path h-4 w-4 animate-spin" />
  ) : (
    <span className="hero-play h-4 w-4" />
  );

  if (!onRunWithCustomInputClick) {
    return (
      <Tooltip content={tooltip} side={tooltipSide}>
        <span className="inline-block">
          <Button variant="primary" onClick={onClick} disabled={isDisabled}>
            <span className="flex items-center gap-1">
              {icon}
              Run
            </span>
          </Button>
        </span>
      </Tooltip>
    );
  }

  return (
    <div className="inline-flex rounded-md shadow-xs">
      <Tooltip content={tooltip} side={tooltipSide}>
        <button
          type="button"
          className="rounded-l-md text-sm font-semibold shadow-xs
          phx-submit-loading:opacity-75 cursor-pointer
          disabled:cursor-not-allowed disabled:bg-primary-300 px-3 py-2
          bg-primary-600 hover:bg-primary-500
          disabled:hover:bg-primary-300 text-white
          focus-visible:outline-2 focus-visible:outline-offset-2
          focus-visible:outline-primary-600 focus:ring-transparent"
          onClick={onClick}
          disabled={isDisabled}
        >
          <span className="flex items-center gap-1">
            {icon}
            {text}
          </span>
        </button>
      </Tooltip>
      <Menu as="div" className="relative -ml-px block">
        <MenuButton
          disabled={isDisabled}
          className="h-full rounded-r-md pr-2 pl-2 text-sm font-semibold
          shadow-xs cursor-pointer disabled:cursor-not-allowed
          bg-primary-600 hover:bg-primary-500
          disabled:bg-primary-300 disabled:hover:bg-primary-300 text-white
          focus-visible:outline-2 focus-visible:outline-offset-2
          focus-visible:outline-primary-600 focus:ring-transparent"
        >
          <span className="sr-only">Open run options</span>
          <span className="hero-chevron-down w-4 h-4" />
        </MenuButton>
        <MenuItems
          transition
          className="absolute right-0 z-[100] mt-2 w-max origin-top-right
          rounded-md bg-white py-1 shadow-lg outline outline-black/5
          transition data-closed:scale-95 data-closed:transform
          data-closed:opacity-0 data-enter:duration-200 data-enter:ease-out
          data-leave:duration-75 data-leave:ease-in"
        >
          <MenuItem>
            <button
              type="button"
              onClick={onRunWithCustomInputClick}
              className="flex items-center gap-2 w-full text-left px-4 py-2
              text-sm text-gray-700 data-focus:bg-gray-100
              data-focus:outline-hidden"
            >
              <span className="hero-play h-4 w-4" />
              Run with custom input
            </button>
          </MenuItem>
        </MenuItems>
      </Menu>
    </div>
  );
}
