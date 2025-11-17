import type { View } from 'phoenix_live_view';
import warning from 'tiny-warning';

import { Slot, type SlotProps } from '#/react/components';

// Store named slots here so we don't create a whole bunch of duplicates
const slots = new Map<string, React.FunctionComponent<SlotProps>>();

export const renderSlots = <const Props = object,>({
  props,
  view,
  cID = null,
}: {
  props: Props;
  view: View;
  cID?: number | null;
}): Props => {
  return typeof props !== 'object' || props === null
    ? props
    : (Object.fromEntries(
        Object.entries(props).map(
          ([key, value]: [key: string, value: unknown]) => [
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

              const name = key === 'children' ? 'inner_block' : key;

              const NamedSlot =
                slots.get(name) ??
                (() => {
                  const NamedSlot: React.FunctionComponent<SlotProps> = props =>
                    Slot(props);
                  // Easier debugging in the React devtools
                  NamedSlot.displayName = `slot(:${name})`;
                  slots.set(name, NamedSlot);
                  return NamedSlot;
                })();

              return (
                <NamedSlot
                  view={view}
                  name={name}
                  html={atob(value.data)}
                  cID={cID}
                />
              );
            })(),
          ]
        )
      ) as Props);
};
