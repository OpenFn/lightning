import { useState, useRef, useEffect, type ReactNode } from 'react';

import { cn } from '#/utils/cn';

import { ShortcutKeys } from './ShortcutKeys';
import { Tooltip } from './Tooltip';

interface RunRetryButtonProps {
  isRetryable: boolean;
  isDisabled: boolean;
  isSubmitting: boolean;
  onRun: () => void;
  onRetry: () => void;
  buttonText?: {
    run?: string;
    retry?: string;
    processing?: string;
  };
  variant?: 'primary' | 'secondary';
  dropdownPosition?: 'up' | 'down';
  className?: string;
  showKeyboardShortcuts?: boolean;
  disabledTooltip?: ReactNode;
}

/**
 * RunRetryButton - Button for Run/Retry operations
 *
 * Renders as:
 * - Single button when not retryable:
 *   - "Run" when idle
 *   - "Processing" when submitting
 * - Split button when retryable:
 *   - "Run (Retry)" + chevron when idle
 *   - "Processing" + disabled chevron when submitting (chevron stays for visual consistency)
 *
 * The chevron opens a dropdown with "Run (New Work Order)" option.
 * Uses min-width to prevent layout shift during text changes.
 *
 * @example
 * <RunRetryButton
 *   isRetryable={true}
 *   isDisabled={false}
 *   isSubmitting={false}
 *   onRun={() => console.log("Run")}
 *   onRetry={() => console.log("Retry")}
 * />
 */
export function RunRetryButton({
  isRetryable,
  isDisabled,
  isSubmitting,
  onRun,
  onRetry,
  buttonText = {},
  variant = 'primary',
  dropdownPosition = 'up',
  className,
  showKeyboardShortcuts = false,
  disabledTooltip,
}: RunRetryButtonProps) {
  const {
    run = 'Run Workflow',
    retry = 'Run (Retry)',
    processing = 'Processing',
  } = buttonText;

  // Always show chevron during processing, otherwise based on isRetryable
  const showChevron = isSubmitting || isRetryable;

  // Compute tooltip content based on props and state
  const mainButtonTooltip =
    isDisabled && disabledTooltip ? (
      disabledTooltip
    ) : showKeyboardShortcuts ? (
      <ShortcutKeys keys={['mod', 'enter']} />
    ) : null;

  const dropdownTooltip =
    showKeyboardShortcuts && showChevron ? (
      <ShortcutKeys keys={['mod', 'shift', 'enter']} />
    ) : null;

  const [isDropdownOpen, setIsDropdownOpen] = useState(false);
  const dropdownRef = useRef<HTMLDivElement>(null);

  // Variant-specific styles
  const variantStyles = {
    primary: {
      base: 'bg-primary-600 hover:bg-primary-500 text-white',
      disabled: 'disabled:bg-primary-300',
      submitting: 'bg-primary-300 text-white',
      focus: 'focus-visible:outline-primary-600',
      chevronBase: 'bg-primary-600 hover:bg-primary-500 text-white',
      chevronDisabled: 'bg-primary-300 text-white',
    },
    secondary: {
      base: 'bg-white hover:bg-gray-50 text-gray-900 inset-ring inset-ring-gray-300 hover:inset-ring-gray-400',
      disabled: 'disabled:bg-gray-50 disabled:text-gray-400',
      submitting: 'bg-gray-50 text-gray-400 inset-ring inset-ring-gray-300',
      focus: 'focus-visible:outline-gray-600',
      chevronBase:
        'bg-white hover:bg-gray-50 text-gray-900 inset-ring inset-ring-gray-300 hover:inset-ring-gray-400',
      chevronDisabled:
        'bg-gray-50 text-gray-400 inset-ring inset-ring-gray-300',
    },
  };

  const styles = variantStyles[variant];

  useEffect(() => {
    if (!isDropdownOpen) return;

    const handleClickOutside = (event: MouseEvent) => {
      if (
        dropdownRef.current &&
        !dropdownRef.current.contains(event.target as Node)
      ) {
        setIsDropdownOpen(false);
      }
    };

    document.addEventListener('mousedown', handleClickOutside);
    return () => document.removeEventListener('mousedown', handleClickOutside);
  }, [isDropdownOpen]);

  const handleDropdownClick = () => {
    setIsDropdownOpen(false);
    onRun();
  };

  // Single button when not showing chevron (no dropdown options available)
  if (!showChevron) {
    const buttonContent = isSubmitting ? (
      <>
        <span className="hero-arrow-path w-4 h-4 animate-spin"></span>
        {processing}
      </>
    ) : (
      <>
        <span className="hero-play-mini w-4 h-4"></span>
        {run}
      </>
    );

    return (
      <Tooltip content={isSubmitting ? null : mainButtonTooltip} side="bottom">
        <button
          type="button"
          onClick={onRun}
          disabled={isDisabled || isSubmitting}
          className={cn(
            'rounded-md text-sm font-semibold shadow-xs px-3 py-2',
            'inline-flex items-center justify-center gap-1',
            'focus-visible:outline-2 focus-visible:outline-offset-2',
            isSubmitting
              ? [styles.submitting, 'cursor-not-allowed']
              : [
                  styles.base,
                  styles.disabled,
                  'disabled:cursor-not-allowed',
                  styles.focus,
                ],
            className
          )}
        >
          {buttonContent}
        </button>
      </Tooltip>
    );
  }

  // Split button when showing chevron (chevron stays during processing for visual consistency)
  const chevronDisabled = isDisabled || isSubmitting;

  const buttonContent = isSubmitting ? (
    <>
      <span className="hero-arrow-path w-4 h-4 animate-spin"></span>
      {processing}
    </>
  ) : (
    <>
      <span className="hero-play-mini w-4 h-4"></span>
      {retry}
    </>
  );

  return (
    <div
      className={cn('inline-flex rounded-md shadow-xs', className)}
      ref={dropdownRef}
    >
      {/* Main button - shows "Run (Retry)" or "Processing" */}
      <Tooltip content={isSubmitting ? null : mainButtonTooltip} side="bottom">
        <button
          type="button"
          onClick={onRetry}
          disabled={isDisabled || isSubmitting}
          className={cn(
            'rounded-md text-sm font-semibold shadow-xs px-3 py-2',
            'relative inline-flex items-center justify-center gap-1 rounded-r-none',
            'focus-visible:outline-2 focus-visible:outline-offset-2',
            'min-w-[8rem]', // Consistent width between "Processing" and "Run (Retry)"
            isSubmitting
              ? [styles.submitting, 'cursor-not-allowed']
              : [
                  styles.base,
                  styles.disabled,
                  'disabled:cursor-not-allowed',
                  styles.focus,
                ]
          )}
        >
          {buttonContent}
        </button>
      </Tooltip>

      {/* Chevron dropdown button - stays visible during processing for consistency */}
      <div className="relative -ml-px">
        <Tooltip
          content={!chevronDisabled ? dropdownTooltip : null}
          side="bottom"
        >
          <button
            type="button"
            onClick={() =>
              !chevronDisabled && setIsDropdownOpen(!isDropdownOpen)
            }
            disabled={chevronDisabled}
            className={cn(
              'rounded-md text-sm font-semibold shadow-xs px-1 py-2',
              'h-full rounded-l-none',
              'focus-visible:outline-2 focus-visible:outline-offset-2',
              chevronDisabled
                ? [styles.submitting, 'cursor-not-allowed']
                : [styles.chevronBase, styles.focus]
            )}
            aria-expanded={isDropdownOpen}
            aria-haspopup="true"
          >
            <span className="sr-only">Open options</span>
            <span className="hero-chevron-down w-4 h-4"></span>
          </button>
        </Tooltip>

        {/* Dropdown menu */}
        {isDropdownOpen && (
          <div
            role="menu"
            aria-orientation="vertical"
            className={cn(
              'absolute right-0 z-10 w-max',
              dropdownPosition === 'up' ? 'bottom-full mb-2' : 'top-full mt-2'
            )}
          >
            <Tooltip content={dropdownTooltip} side="bottom">
              <button
                type="button"
                onClick={handleDropdownClick}
                disabled={isDisabled}
                className={cn(
                  'rounded-md text-sm font-semibold shadow-lg px-3 py-2',
                  'bg-white hover:bg-gray-50 text-gray-900',
                  'ring-1 ring-gray-300 ring-inset',
                  'disabled:opacity-50 disabled:cursor-not-allowed',
                  'flex items-center gap-1 whitespace-nowrap'
                )}
              >
                <span className="hero-play-solid w-4 h-4"></span>
                Run (New Work Order)
              </button>
            </Tooltip>
          </div>
        )}
      </div>
    </div>
  );
}
