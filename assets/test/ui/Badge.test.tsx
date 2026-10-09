import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { createRef } from 'react';
import { describe, expect, test, vi } from 'vitest';

import { Tooltip } from '#/components/Tooltip';
import { Badge, badgeClassName } from '#/ui/Badge';

const colors = [
  'neutral',
  'success',
  'warning',
  'danger',
  'info',
  'brand',
  'orange',
  'dark',
] as const;

describe('Badge', () => {
  test('renders a neutral, default-size span with its children', () => {
    render(<Badge data-testid="badge">main</Badge>);

    const badge = screen.getByTestId('badge');
    expect(badge.tagName).toBe('SPAN');
    expect(badge).toHaveTextContent('main');
    expect(badge).toHaveClass('ui-badge', 'ui-badge--neutral');
    expect(badge).not.toHaveClass(
      'ui-badge--small',
      'ui-badge--mono',
      'ui-badge--dot'
    );
    expect(badge.querySelector('.ui-badge__dot')).toBeNull();
    expect(screen.queryByRole('button')).not.toBeInTheDocument();
  });

  test.each(colors)('applies the %s colour', color => {
    render(
      <Badge data-testid="badge" color={color}>
        x
      </Badge>
    );

    expect(screen.getByTestId('badge')).toHaveClass(`ui-badge--${color}`);
  });

  test('falls back to neutral when color is null or undefined', () => {
    render(
      <>
        <Badge data-testid="null" color={null}>
          x
        </Badge>
        <Badge data-testid="undefined" color={undefined}>
          x
        </Badge>
      </>
    );

    expect(screen.getByTestId('null')).toHaveClass('ui-badge--neutral');
    expect(screen.getByTestId('undefined')).toHaveClass('ui-badge--neutral');
  });

  test('applies the small, mono and className modifiers', () => {
    render(
      <Badge data-testid="badge" size="small" mono className="max-w-32">
        a1b2c3d
      </Badge>
    );

    expect(screen.getByTestId('badge')).toHaveClass(
      'ui-badge',
      'ui-badge--small',
      'ui-badge--mono',
      'max-w-32'
    );
  });

  test('dot renders a dot, styled by dotStyle, with the pulse inside it', () => {
    render(
      <Badge
        data-testid="badge"
        color="info"
        dot
        pulse
        dotStyle={{ backgroundColor: 'rgb(1, 2, 3)' }}
      >
        Running
      </Badge>
    );

    const badge = screen.getByTestId('badge');
    const dot = badge.querySelector('.ui-badge__dot');
    expect(badge).toHaveClass('ui-badge--dot', 'ui-badge--info');
    expect(dot).toHaveStyle({ backgroundColor: 'rgb(1, 2, 3)' });
    expect(dot?.querySelector('.ui-badge__pulse')).not.toBeNull();
  });

  test('pulse without dot renders nothing', () => {
    render(
      <Badge data-testid="badge" pulse>
        x
      </Badge>
    );

    expect(
      screen.getByTestId('badge').querySelector('.ui-badge__pulse')
    ).toBeNull();
  });

  test('renders the icon before the children', () => {
    render(
      <Badge data-testid="badge" icon="hero-bolt">
        Webhook
      </Badge>
    );

    const icon = screen.getByTestId('badge').firstElementChild;
    expect(icon).toHaveClass('hero-bolt', 'ui-badge__icon');
    expect(icon).toHaveAttribute('aria-hidden', 'true');
  });

  test('passes rest props and the ref to the span', () => {
    const ref = createRef<HTMLSpanElement>();
    render(
      <Badge ref={ref} id="env-badge" aria-label="Sandbox" data-testid="badge">
        main
      </Badge>
    );

    const badge = screen.getByTestId('badge');
    expect(badge).toHaveAttribute('id', 'env-badge');
    expect(badge).toHaveAttribute('aria-label', 'Sandbox');
    expect(ref.current).toBe(badge);
  });

  test('the x is a named button that calls onRemove', async () => {
    const onRemove = vi.fn();
    render(
      <Badge onRemove={onRemove} removeLabel="Remove Project A">
        Project A
      </Badge>
    );

    const remove = screen.getByRole('button', { name: 'Remove Project A' });
    expect(remove).toHaveAttribute('type', 'button');
    expect(remove).toHaveClass('ui-badge__remove');
    expect(remove.firstElementChild).toHaveClass(
      'hero-x-mark-micro',
      'h-3',
      'w-3'
    );

    await userEvent.click(remove);
    expect(onRemove).toHaveBeenCalledTimes(1);
  });

  test('removeDisabled disables the x', async () => {
    const onRemove = vi.fn();
    render(
      <Badge onRemove={onRemove} removeLabel="Remove tag" removeDisabled>
        tag
      </Badge>
    );

    const remove = screen.getByRole('button', { name: 'Remove tag' });
    expect(remove).toBeDisabled();

    await userEvent.click(remove);
    expect(onRemove).not.toHaveBeenCalled();
  });

  test('opens a Tooltip on hover', async () => {
    render(
      <Tooltip content="Deployed and running">
        <Badge color="success">Live</Badge>
      </Tooltip>
    );

    await userEvent.hover(screen.getByText('Live'));

    expect(await screen.findByRole('tooltip')).toHaveTextContent(
      'Deployed and running'
    );
  });
});

describe('badgeClassName', () => {
  test('returns the badge classes, plus interactive, for real buttons', () => {
    expect(
      badgeClassName({
        color: 'brand',
        size: 'small',
        mono: true,
        interactive: true,
        className: 'extra',
      }).split(' ')
    ).toEqual([
      'ui-badge',
      'ui-badge--brand',
      'ui-badge--small',
      'ui-badge--mono',
      'ui-badge--interactive',
      'extra',
    ]);
    expect(badgeClassName({})).toBe('ui-badge ui-badge--neutral');
  });
});
