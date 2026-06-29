import type { Meta, StoryObj } from '@storybook/react-vite';

import { ShortcutKeys } from '#/collaborative-editor/components/ShortcutKeys';

import { Showcase, Section, Row, Specimen } from '../_shared/showcase';

/**
 * `ShortcutKeys` renders a keyboard shortcut as a series of `<kbd>` elements
 * joined by `+`. The special token `mod` becomes `⌘` on macOS and `Ctrl`
 * elsewhere; every other key is title-cased. Rendering is platform-dependent,
 * so the exact glyphs reflect the machine viewing Storybook.
 */
const meta = {
  title: 'Components/Shortcut Keys',
  tags: ['useful'],
  component: ShortcutKeys,
  parameters: { layout: 'centered' },
  args: { keys: ['mod', 's'] },
} satisfies Meta<typeof ShortcutKeys>;

export default meta;

type Story = StoryObj<typeof meta>;

export const Playground: Story = {};

export const Examples: Story = {
  render: () => (
    <Showcase>
      <Section
        title="Common shortcuts"
        description="mod resolves to ⌘ on macOS and Ctrl on other platforms."
      >
        <Row>
          <Specimen label="save">
            <ShortcutKeys keys={['mod', 's']} />
          </Specimen>
          <Specimen label="run">
            <ShortcutKeys keys={['mod', 'enter']} />
          </Specimen>
          <Specimen label="run (all)">
            <ShortcutKeys keys={['mod', 'shift', 'enter']} />
          </Specimen>
          <Specimen label="close">
            <ShortcutKeys keys={['esc']} />
          </Specimen>
        </Row>
      </Section>
    </Showcase>
  ),
};
