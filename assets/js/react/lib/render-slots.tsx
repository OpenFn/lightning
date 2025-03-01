import warning from 'tiny-warning';

import type { View } from 'phoenix_live_view';

import { Slot, type SlotProps } from '#/react/components';

export const renderSlots = ({
  props,
  view,
  slots,
}: {
  props: unknown;
  view: View;
  slots: Map<string, React.FunctionComponent<SlotProps>>;
}) => {
  return typeof props !== 'object' || props === null
    ? props
    : Object.fromEntries(
        Object.entries(props).map(([key, value]) => [
          key,
          (() => {
            if (typeof value !== 'object' || value === null) {
              return value;
            }

            const keys = Object.keys(value);

            if (keys.length !== 2 || !('__type__' in value)) {
              return value;
            }

            if (
              value.__type__ !== '__slot__' ||
              !('data' in value) ||
              typeof value.data !== 'string'
            ) {
              warning(
                void 0,
                `Object at key \`${key}\` with key \`__type__\` does not conform to expectation. Not rendering it as a slot.'`
              );
              return value;
            }

            if (!slots.has(key)) {
              const NamedSlot: React.FunctionComponent<SlotProps> = props =>
                Slot(props);
              // Easier debugging in the React devtools
              NamedSlot.displayName = `slot(:${key === 'children' ? 'inner_block' : key})`;
              slots.set(key, NamedSlot);
            }

            const NamedSlot = slots.get(key)!;

            const slot = (
              <NamedSlot view={view} slot={key} data={atob(value.data)} />
            );

            return slot;
          })(),
        ])
      );
};
