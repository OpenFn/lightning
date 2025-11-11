import * as RadixTooltip from '@radix-ui/react-tooltip';
import type { ReactNode } from 'react';

/**
 * Tooltip component using Radix UI primitives
 * Provides accessible tooltips following Lightning's design patterns
 *
 * Usage:
 * ```tsx
 * <Tooltip content="Save changes">
 *   <button>Save</button>
 * </Tooltip>
 * ```
 */
export function Tooltip({
  children,
  content,
  side = 'bottom',
  align = 'center',
  delayDuration = 200,
}: {
  children: ReactNode;
  content: ReactNode;
  side?: 'top' | 'right' | 'bottom' | 'left';
  align?: 'start' | 'center' | 'end';
  delayDuration?: number;
}) {
  return (
    <RadixTooltip.Provider delayDuration={delayDuration}>
      <RadixTooltip.Root>
        <RadixTooltip.Trigger asChild>{children}</RadixTooltip.Trigger>
        <RadixTooltip.Portal>
          <RadixTooltip.Content
            side={side}
            align={align}
            className="z-50 overflow-hidden rounded-md bg-gray-900
            px-3 py-1.5 text-xs text-white shadow-md
            animate-in fade-in-0 zoom-in-95
            data-[state=closed]:animate-out
            data-[state=closed]:fade-out-0
            data-[state=closed]:zoom-out-95
            data-[side=bottom]:slide-in-from-top-2
            data-[side=left]:slide-in-from-right-2
            data-[side=right]:slide-in-from-left-2
            data-[side=top]:slide-in-from-bottom-2"
            sideOffset={5}
          >
            {content}
            <RadixTooltip.Arrow className="fill-gray-900" />
          </RadixTooltip.Content>
        </RadixTooltip.Portal>
      </RadixTooltip.Root>
    </RadixTooltip.Provider>
  );
}
