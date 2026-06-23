/**
 * MonacoRefContext Tests
 *
 * Covers the editor-ready callback registry used to re-show a pending
 * global-step diff when the editor (re)mounts, alongside the existing diff
 * dismissal registry.
 */

import { render, act } from '@testing-library/react';
import { useEffect, useRef } from 'react';
import { describe, it, expect, vi } from 'vitest';

import type { MonacoHandle } from '../../../js/collaborative-editor/components/CollaborativeMonaco';
import {
  MonacoRefProvider,
  useHandleEditorReady,
  useRegisterEditorReadyCallback,
} from '../../../js/collaborative-editor/contexts/MonacoRefContext';

/**
 * Renders a provider with a consumer that registers a ready callback and
 * exposes the handleEditorReady trigger for the test to call.
 */
function setup(callback: () => void) {
  const triggerRef: { current: (() => void) | undefined } = {
    current: undefined,
  };

  function Consumer() {
    const handleEditorReady = useHandleEditorReady();
    useRegisterEditorReadyCallback(callback);
    useEffect(() => {
      triggerRef.current = handleEditorReady;
    }, [handleEditorReady]);
    return null;
  }

  function Wrapper() {
    const monacoRef = useRef<MonacoHandle>(null);
    return (
      <MonacoRefProvider monacoRef={monacoRef}>
        <Consumer />
      </MonacoRefProvider>
    );
  }

  const utils = render(<Wrapper />);
  return { ...utils, triggerRef };
}

describe('MonacoRefContext - editor ready registry', () => {
  it('invokes registered ready callbacks when handleEditorReady fires', () => {
    const onReady = vi.fn();
    const { triggerRef } = setup(onReady);

    expect(onReady).not.toHaveBeenCalled();

    act(() => {
      triggerRef.current?.();
    });
    expect(onReady).toHaveBeenCalledTimes(1);

    // Each editor (re)mount fires again
    act(() => {
      triggerRef.current?.();
    });
    expect(onReady).toHaveBeenCalledTimes(2);
  });

  it('stops invoking a callback after the consumer unmounts', () => {
    const onReady = vi.fn();
    const { triggerRef, unmount } = setup(onReady);

    // Keep a reference to the trigger before unmounting the consumer
    const trigger = triggerRef.current;
    unmount();

    act(() => {
      trigger?.();
    });
    expect(onReady).not.toHaveBeenCalled();
  });
});
