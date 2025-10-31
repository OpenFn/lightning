import { useState, useRef, useEffect } from "react";
import { cn } from "#/utils/cn";

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
  variant?: "primary" | "secondary";
  dropdownPosition?: "up" | "down";
  className?: string;
}

/**
 * RunRetryButton - Split button for Run/Retry operations
 *
 * Displays a single "Run" button when retry is not available,
 * or a split button with "Run (retry)" main action and
 * "Run (New Work Order)" dropdown option when retry is available.
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
  variant = "primary",
  dropdownPosition = "up",
  className,
}: RunRetryButtonProps) {
  const {
    run = "Run Workflow",
    retry = "Run (retry)",
    processing = "Processing",
  } = buttonText;

  const [isDropdownOpen, setIsDropdownOpen] = useState(false);
  const dropdownRef = useRef<HTMLDivElement>(null);

  // Variant-specific styles
  const variantStyles = {
    primary: {
      base: "bg-primary-600 hover:bg-primary-500 text-white",
      disabled: "disabled:bg-primary-300",
      submitting: "bg-primary-300 text-white",
      focus: "focus-visible:outline-primary-600",
    },
    secondary: {
      base: "bg-white hover:bg-gray-50 text-gray-900 inset-ring inset-ring-gray-300 hover:inset-ring-gray-400",
      disabled: "disabled:bg-gray-50 disabled:text-gray-400",
      submitting: "bg-gray-50 text-gray-400 inset-ring inset-ring-gray-300",
      focus: "focus-visible:outline-gray-600",
    },
  };

  const styles = variantStyles[variant];

  // Click-away handler
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

    document.addEventListener("mousedown", handleClickOutside);
    return () => document.removeEventListener("mousedown", handleClickOutside);
  }, [isDropdownOpen]);

  const handleMainClick = () => {
    if (isRetryable) {
      onRetry();
    } else {
      onRun();
    }
  };

  const handleDropdownClick = () => {
    setIsDropdownOpen(false);
    onRun(); // Always run (force new work order)
  };

  if (isSubmitting) {
    return (
      <button
        type="button"
        disabled
        className={cn(
          "rounded-md text-sm font-semibold shadow-xs px-3 py-2",
          styles.submitting,
          "cursor-not-allowed",
          "flex items-center gap-1",
          className
        )}
      >
        <span className="hero-arrow-path w-4 h-4 animate-spin"></span>
        {processing}
      </button>
    );
  }

  if (!isRetryable) {
    // Single button
    return (
      <button
        type="button"
        onClick={handleMainClick}
        disabled={isDisabled}
        className={cn(
          "rounded-md text-sm font-semibold shadow-xs px-3 py-2",
          styles.base,
          styles.disabled,
          "disabled:cursor-not-allowed",
          "focus-visible:outline-2 focus-visible:outline-offset-2",
          styles.focus,
          "flex items-center gap-1",
          className
        )}
      >
        <span className="hero-play-mini w-4 h-4"></span>
        {run}
      </button>
    );
  }

  // Split button
  return (
    <div
      className={cn("inline-flex rounded-md shadow-xs", className)}
      ref={dropdownRef}
    >
      {/* Main button */}
      <button
        type="button"
        onClick={handleMainClick}
        disabled={isDisabled}
        className={cn(
          "rounded-md text-sm font-semibold shadow-xs px-3 py-2",
          styles.base,
          styles.disabled,
          "disabled:cursor-not-allowed",
          "focus-visible:outline-2 focus-visible:outline-offset-2",
          styles.focus,
          "relative inline-flex items-center rounded-r-none"
        )}
      >
        <span className="hero-play-mini w-4 h-4 mr-1"></span>
        {retry}
      </button>

      {/* Dropdown toggle */}
      <div className="relative -ml-px">
        <button
          type="button"
          onClick={() => setIsDropdownOpen(!isDropdownOpen)}
          disabled={isDisabled}
          className={cn(
            "rounded-md text-sm font-semibold shadow-xs px-1 py-2",
            styles.base,
            styles.disabled,
            "disabled:cursor-not-allowed",
            "focus-visible:outline-2 focus-visible:outline-offset-2",
            styles.focus,
            "h-full rounded-l-none"
          )}
          aria-expanded={isDropdownOpen}
          aria-haspopup="true"
        >
          <span className="sr-only">Open options</span>
          <span className="hero-chevron-down w-4 h-4"></span>
        </button>

        {/* Dropdown menu */}
        {isDropdownOpen && (
          <div
            role="menu"
            aria-orientation="vertical"
            className={cn(
              "absolute right-0 z-10 w-max",
              dropdownPosition === "up" ? "bottom-full mb-2" : "top-full mt-2"
            )}
          >
            <button
              type="button"
              onClick={handleDropdownClick}
              disabled={isDisabled}
              className={cn(
                "rounded-md text-sm font-semibold shadow-lg px-3 py-2",
                "bg-white hover:bg-gray-50 text-gray-900",
                "ring-1 ring-gray-300 ring-inset",
                "disabled:opacity-50 disabled:cursor-not-allowed",
                "flex items-center gap-1 whitespace-nowrap"
              )}
            >
              <span className="hero-play-solid w-4 h-4"></span>
              Run (New Work Order)
            </button>
          </div>
        )}
      </div>
    </div>
  );
}
