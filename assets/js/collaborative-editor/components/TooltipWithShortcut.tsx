import { type ComponentProps } from 'react';

import { formatShortcut } from '../utils/formatShortcut';

import { Tooltip } from './Tooltip';

interface TooltipWithShortcutProps
  extends Omit<ComponentProps<typeof Tooltip>, 'content'> {
  description: string;
  shortcut?: string[] | undefined;
}

/**
 * Tooltip component with optional keyboard shortcut display
 * Format: "Description Shortcut"
 * Example: "Save workflow ⌘ S"
 *
 * Pass undefined or empty array for shortcut to show description only
 *
 * Usage:
 * <TooltipWithShortcut
 *   description="Save workflow"
 *   shortcut={["mod", "s"]}
 *   side="bottom"
 * >
 *   <button>Save</button>
 * </TooltipWithShortcut>
 */
export function TooltipWithShortcut({
  children,
  description,
  shortcut,
  ...tooltipProps
}: TooltipWithShortcutProps) {
  // Format content as JSX with optional shortcut
  const content =
    shortcut && shortcut.length > 0 ? (
      <>
        {description} {formatShortcut(shortcut)}
      </>
    ) : (
      description
    );

  return (
    <Tooltip content={content} {...tooltipProps}>
      {children}
    </Tooltip>
  );
}
