import invariant from 'tiny-invariant';

import React, { useLayoutEffect } from 'react';

import { shallowEqual } from '#/react/lib';

export type InnerSlotProps = {
  slot: string;
  innerHTML?:
    | {
        __html: string | TrustedHTML;
      }
    | undefined;
};

export const InnerSlot = React.memo(
  React.forwardRef<HTMLDivElement, InnerSlotProps>(function InnerSlot(
    { slot, innerHTML },
    ref
  ) {
    useLayoutEffect(() => {
      console.debug('React InnerSlot render');
    });

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
  }),
  (a, b) => {
    const equal = shallowEqual(a, b);

    invariant(
      equal,
      "`InnerSlot`'s props have changed! It should remain the same for the lifetime of the component, as it is meant to never re-render, its DOM content is not to be managed or changed by React!"
    );

    return equal;
  }
);
