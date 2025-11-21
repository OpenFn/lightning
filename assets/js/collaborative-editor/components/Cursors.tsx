import { useEffect, useMemo } from 'react';

import { useUserCursors, useRemoteUsers } from '../hooks/useAwareness';

function BaseStyles() {
  const baseStyles = `
    /* Base cursor selection background */
    .yRemoteSelection {
      opacity: 0.5;
      margin-right: -1px;
    }

    /* Base cursor caret */
    .yRemoteSelectionHead {
      position: absolute;
      box-sizing: border-box;
      height: 100%;
      border-left: 2px solid var(--user-color);
    }

    /* Base cursor name */
    .yRemoteSelectionHead::after {
      position: absolute;
      top: -1.4em;
      left: -2px;
      padding: 2px 6px;
      color: #fff;
      border: 0;
      border-radius: 6px;
      border-bottom-left-radius: 0;
      line-height: normal;
      white-space: nowrap;
      font-size: 14px;
      font-style: normal;
      font-weight: 600;
      pointer-events: none;
      user-select: none;
      z-index: 1000;
    }
  `;

  return <style dangerouslySetInnerHTML={{ __html: baseStyles }} />;
}

/**
 * Cursors component using awareness hooks for better performance and maintainability
 *
 * Key improvements:
 * - Uses useUserCursors() hook with memoized Map for efficient lookups
 * - Uses useRemoteUsers() for selection data (referentially stable)
 * - Eliminates manual awareness state management and reduces re-renders
 */
export function Cursors() {
  // Get cursor data as a Map for efficient clientId lookups
  const cursorsMap = useUserCursors();

  // Get remote users for selection data
  const remoteUsers = useRemoteUsers();

  // Dynamic user-specific cursor styles - now using Map entries
  const userStyles = useMemo(() => {
    let cursorStyles = '';

    // Only iterate over users who actually have cursor/selection data
    for (const [clientId, user] of cursorsMap) {
      cursorStyles += `
          .yRemoteSelection-${clientId} {
            background-color: ${user.user.color};
          }

          .yRemoteSelectionHead-${clientId} {
            --user-color: ${user.user.color};
          }

          .yRemoteSelectionHead-${clientId}::after {
            content: "${user.user.name}";
            background: ${user.user.color};
          }

          .yRemoteSelectionHead-${clientId}.cursor-at-top::after {
            top: 1.2em;
            border-radius: 6px;
            border-top-left-radius: 0;
            border-bottom-left-radius: 6px;
          }
        `;
    }

    return { __html: cursorStyles };
  }, [cursorsMap]);

  // Detect when a users cursor is near the top of the editor and flip the
  // position of the label to below their position.
  useEffect(() => {
    const checkCursorPositions = () => {
      const cursors = document.querySelectorAll(
        '[class*="yRemoteSelectionHead-"]'
      );
      cursors.forEach(cursor => {
        const rect = cursor.getBoundingClientRect();
        const editorContainer =
          cursor.closest('.monaco-editor') ||
          cursor.closest('[data-mode-id="javascript"]');

        if (editorContainer) {
          const containerRect = editorContainer.getBoundingClientRect();
          const relativeTop = rect.top - containerRect.top;

          // If cursor is within 30px of the top of the editor, add the class
          if (relativeTop < 30) {
            cursor.classList.add('cursor-at-top');
          } else {
            cursor.classList.remove('cursor-at-top');
          }
        }
      });
    };

    // Also check on scroll events
    // FIXME: This references the first editor anywhere on the page.
    // We need to pass in the editor element to the component.
    const editorElement = document.querySelector('.monaco-editor');
    editorElement?.addEventListener('scroll', checkCursorPositions);

    checkCursorPositions();

    return () => {
      editorElement?.removeEventListener('scroll', checkCursorPositions);
    };
  }, [remoteUsers.length]); // Only re-run when remote users change

  return (
    <>
      <BaseStyles />
      <style dangerouslySetInnerHTML={userStyles} />
    </>
  );
}
