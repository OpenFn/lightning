import { useLayoutEffect, useRef, useState } from 'react';

import type { View } from 'phoenix_live_view';

import { InnerSlot } from '#/react/components';

export type SlotProps = {
  view: View;
  slot: string;
  data: string;
};

export const Slot = ({ view, slot, data }: SlotProps) => {
  // const [el, setEl] = useState<HTMLDivElement | null>(null);
  const ref = useRef<HTMLDivElement>(null);

  // Static value, should never change so that React never re-renders `InnerSlot` component.
  const [innerHTML] = useState(() => ({ __html: data }));

  useLayoutEffect(() => {
    console.debug('React Slot first render', { view, slot, data });
  }, []);

  useLayoutEffect(() => {
    const el = ref.current;
    if (!el) return;
    console.debug(`React Slot ${slot}: patching DOM…`, {
      view,
      el,
      slot,
      data,
    });
    patchDom(el, `<div data-react-slot="${slot}">${data}</div>`);

    // forcefully run hooks (very similar to the execNewMounted function)
    el.querySelectorAll('[phx-hook]').forEach(el => {
      view.maybeAddNewHook(el);
    });

    el.querySelectorAll('[phx-mounted]').forEach(el => {
      view.maybeMounted(el);
    });

    () => {
      // TODO: "un-patch" the DOM?
    };
  }, [view, slot, data]);

  // return <InnerSlot ref={setEl} slot={slot} innerHTML={innerHTML} />;
  return (
    <div
      ref={ref}
      data-react-slot={slot}
      dangerouslySetInnerHTML={innerHTML}
      style={{
        // Don't create a box for this element
        // https://developer.mozilla.org/en-US/docs/Web/CSS/display#contents
        display: 'contents',
      }}
    />
  );
};
