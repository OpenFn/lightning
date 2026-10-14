import { RocketLaunchIcon } from '@heroicons/react/24/outline';
import { fireEvent, render, screen } from '@testing-library/react';
import { describe, expect, test } from 'vitest';

import { Avatar } from '#/ui/Avatar';

describe('Avatar', () => {
  test('shows upcased initials from first and last name', () => {
    const { container } = render(
      <Avatar firstName="ada" lastName="lovelace" />
    );

    expect(container.firstElementChild).toHaveTextContent(/^AL$/);
    expect(container.querySelector('svg')).toBeNull();
  });

  test("shows one initial when there's only one name", () => {
    const { container, rerender } = render(<Avatar firstName="Ada" />);
    expect(container.firstElementChild).toHaveTextContent(/^A$/);

    rerender(<Avatar firstName=" " lastName="Lovelace" />);
    expect(container.firstElementChild).toHaveTextContent(/^L$/);
  });

  test("shows the icon when there's no name", () => {
    const { container, rerender } = render(<Avatar />);
    expect(container.querySelector('svg.ui-avatar__icon')).not.toBeNull();

    rerender(<Avatar icon={RocketLaunchIcon} />);
    expect(container.querySelector('svg.ui-avatar__icon')).not.toBeNull();
  });

  test('puts the image over the initials, and drops it if it fails to load', () => {
    const { container } = render(<Avatar firstName="Ada" src="/a.png" />);

    const img = container.querySelector('img.ui-avatar__image')!;
    expect(img).toHaveAttribute('src', '/a.png');
    expect(img).toHaveAttribute('alt', '');
    expect(container.firstElementChild).toHaveTextContent(/^A$/);

    fireEvent.error(img);
    expect(container.querySelector('img')).toBeNull();
  });

  test('is hidden from screen readers unless it has a label', () => {
    const { container, rerender } = render(<Avatar firstName="Ada" />);
    expect(container.firstElementChild).toHaveAttribute('aria-hidden', 'true');
    expect(screen.queryByRole('img')).toBeNull();

    rerender(<Avatar firstName="Ada" src="/a.png" label="Ada Lovelace" />);
    expect(container.firstElementChild).not.toHaveAttribute('aria-hidden');
    expect(screen.getByRole('img', { name: 'Ada Lovelace' })).toBe(
      container.firstElementChild
    );
  });

  test("maps size to a modifier class and keeps the caller's class", () => {
    const { container, rerender } = render(<Avatar />);
    expect(container.firstElementChild).toHaveAttribute('class', 'ui-avatar');

    rerender(<Avatar size="small" className="x" />);
    expect(container.firstElementChild).toHaveAttribute(
      'class',
      'ui-avatar ui-avatar--small x'
    );

    rerender(<Avatar size="large" />);
    expect(container.firstElementChild).toHaveClass('ui-avatar--large');
  });
});
