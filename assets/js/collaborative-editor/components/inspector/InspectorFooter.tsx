import type { ReactNode } from 'react';

interface InspectorFooterProps {
  leftButtons?: ReactNode;
  rightButtons?: ReactNode;
}

/**
 * Reusable footer component for inspector panels.
 * Provides left and right button slots with consistent styling.
 *
 * @example
 * <InspectorFooter
 *   leftButtons={
 *     <>
 *       <Button onClick={handleEdit}>Edit</Button>
 *       <Button onClick={handleRun}>Run</Button>
 *     </>
 *   }
 *   rightButtons={
 *     <Button variant="danger" onClick={handleDelete}>
 *       Delete
 *     </Button>
 *   }
 * />
 */
export function InspectorFooter({
  leftButtons,
  rightButtons,
}: InspectorFooterProps) {
  // Don't render if no buttons provided
  if (!leftButtons && !rightButtons) {
    return null;
  }

  return (
    <div className={'flex justify-between items-center'}>
      {/* Left side: Edit, Run, etc. */}
      <div className="flex gap-2">{leftButtons}</div>

      {/* Right side: Delete button */}
      <div className="flex gap-2">{rightButtons}</div>
    </div>
  );
}
