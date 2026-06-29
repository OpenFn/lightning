import type { Meta, StoryObj } from '@storybook/react-vite';
import type { ButtonHTMLAttributes, ReactNode } from 'react';

import { cn } from '#/utils/cn';

import { Showcase, Section, Row, Specimen } from '../_shared/showcase';

/**
 * React clone of `LightningWeb.Components.NewInputs.button/1`
 * (lib/lightning_web/components/new_inputs.ex).
 *
 * The server component renders a themed `<button>`; this is a presentational
 * copy of the same base/size/theme Tailwind classes. The `phx-submit-loading`
 * opacity variant from the original is omitted (it only applies inside a
 * LiveView form submit).
 */
type ButtonTheme =
  | 'primary'
  | 'secondary'
  | 'danger'
  | 'success'
  | 'warning'
  | 'custom';
type ButtonSize = 'sm' | 'md' | 'lg';

const BASE = 'rounded-md text-sm font-semibold shadow-xs cursor-pointer';

const SIZE_CLASSES: Record<ButtonSize, string> = {
  sm: 'px-2.5 py-1.5',
  md: 'px-3 py-2',
  lg: 'px-3.5 py-2.5',
};

const THEME_ENABLED: Record<ButtonTheme, string> = {
  primary:
    'bg-primary-600 hover:bg-primary-500 text-white focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary-600',
  secondary:
    'bg-white hover:bg-gray-50 text-gray-900 ring-1 ring-gray-300 ring-inset',
  danger:
    'bg-red-600 hover:bg-red-500 text-white focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-red-600',
  success:
    'bg-green-600 hover:bg-green-500 text-white focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-green-600',
  warning:
    'bg-yellow-600 hover:bg-yellow-500 text-white focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-yellow-600',
  custom: '',
};

const THEME_DISABLED: Record<ButtonTheme, string> = {
  primary: 'bg-primary-300 text-white',
  secondary: 'bg-gray-50 text-gray-400 ring-1 ring-gray-200 ring-inset',
  danger: 'bg-red-300 text-white',
  success: 'bg-green-300 text-white',
  warning: 'bg-yellow-300 text-white',
  custom: '',
};

interface LvButtonProps
  extends Omit<ButtonHTMLAttributes<HTMLButtonElement>, 'type'> {
  theme?: ButtonTheme;
  size?: ButtonSize;
  type?: 'button' | 'submit';
  children: ReactNode;
}

function LvButton({
  theme = 'primary',
  size = 'md',
  type = 'button',
  className,
  disabled = false,
  children,
  ...rest
}: LvButtonProps) {
  return (
    <button
      type={type}
      disabled={disabled}
      className={cn(
        BASE,
        'disabled:cursor-auto',
        SIZE_CLASSES[size],
        disabled ? THEME_DISABLED[theme] : THEME_ENABLED[theme],
        className
      )}
      {...rest}
    >
      {children}
    </button>
  );
}

const THEMES: ButtonTheme[] = [
  'primary',
  'secondary',
  'danger',
  'success',
  'warning',
];
const SIZES: ButtonSize[] = ['sm', 'md', 'lg'];

const meta = {
  title: 'LiveView Clones/Button (LiveView Clone)',
  tags: ['core'],
  component: LvButton,
  parameters: { layout: 'centered' },
  args: { theme: 'primary', size: 'md', disabled: false, children: 'Button' },
  argTypes: {
    theme: { control: 'select', options: THEMES },
    size: { control: 'inline-radio', options: SIZES },
  },
} satisfies Meta<typeof LvButton>;

export default meta;

type Story = StoryObj<typeof meta>;

export const Playground: Story = {};

export const Themes: Story = {
  render: () => (
    <Showcase>
      <Section title="Themes">
        <Row>
          {THEMES.map(theme => (
            <LvButton key={theme} theme={theme}>
              {theme}
            </LvButton>
          ))}
        </Row>
      </Section>
      <Section title="Disabled">
        <Row>
          {THEMES.map(theme => (
            <LvButton key={theme} theme={theme} disabled>
              {theme}
            </LvButton>
          ))}
        </Row>
      </Section>
    </Showcase>
  ),
};

export const Sizes: Story = {
  render: () => (
    <Showcase>
      <Section title="Sizes">
        <Row>
          {SIZES.map(size => (
            <Specimen key={size} label={size}>
              <LvButton size={size}>Button</LvButton>
            </Specimen>
          ))}
        </Row>
      </Section>
    </Showcase>
  ),
};
