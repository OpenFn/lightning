import type { View } from 'phoenix_live_view';
import { useLayoutEffect, useRef, useState } from 'react';

import { performPatch } from '#/react/lib';

const style: React.CSSProperties = {
  // Don't create a box for this element
  // https://developer.mozilla.org/en-US/docs/Web/CSS/display#contents
  display: 'contents',
};

export type SlotProps = {
  view: View;
  name: string;
  html: string;
  cID?: number | null;
};

export const Slot = ({ view, name, html, cID = null }: SlotProps) => {
  const [el, setEl] = useState<HTMLDivElement | null>(null);
  const unpatchedRef = useRef(true);

  // Intentionally referentially stable value, should never change so that React
  // never re-renders the child. We want Phoenix to do it for us instead.
  const [innerHTML] = useState(() => ({ __html: html }));

  useLayoutEffect(() => {
    if (
      el == null ||
      !el.isConnected ||
      (innerHTML.__html === html && unpatchedRef.current)
    ) {
      return;
    }

    performPatch(
      view,
      el,
      `<div data-react-slot=${name} style="display: contents">${html}</div>`,
      cID
    );

    unpatchedRef.current = false;
  }, [name, el, innerHTML.__html, view, html, cID]);

  return (
    <div
      ref={setEl}
      data-react-slot={name}
      dangerouslySetInnerHTML={innerHTML}
      style={style}
    />
  );
};
