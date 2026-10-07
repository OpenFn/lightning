import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { describe, expect, test, vi } from 'vitest';

import { Tabs } from '#/ui/Tabs';

const options = [
  { value: 'log', label: 'Log' },
  { value: 'input', label: 'Input' },
  { value: 'output', label: 'Output' },
];

describe('Tabs', () => {
  test('renders a labelled tablist with a tab per option', () => {
    render(<Tabs value="log" onChange={vi.fn()} options={options} />);

    expect(screen.getByRole('tablist', { name: 'Tabs' })).toBeInTheDocument();
    expect(screen.getAllByRole('tab')).toHaveLength(3);
  });

  test('uses the given aria-label', () => {
    render(
      <Tabs
        value="log"
        onChange={vi.fn()}
        options={options}
        aria-label="Count by"
      />
    );

    expect(
      screen.getByRole('tablist', { name: 'Count by' })
    ).toBeInTheDocument();
  });

  test('marks only the selected tab, and renders buttons that do not submit', () => {
    render(<Tabs value="input" onChange={vi.fn()} options={options} />);

    expect(screen.getByRole('tab', { name: 'Input' })).toHaveAttribute(
      'aria-selected',
      'true'
    );
    expect(screen.getByRole('tab', { name: 'Log' })).toHaveAttribute(
      'aria-selected',
      'false'
    );
    for (const tab of screen.getAllByRole('tab')) {
      expect(tab).toHaveAttribute('type', 'button');
    }
  });

  test('calls onChange with the clicked value', async () => {
    const onChange = vi.fn();
    render(<Tabs value="log" onChange={onChange} options={options} />);

    await userEvent.click(screen.getByRole('tab', { name: 'Output' }));

    expect(onChange).toHaveBeenCalledWith('output');
  });

  test('renders a hidden icon before the label', () => {
    const Icon = (props: React.SVGProps<SVGSVGElement>) => (
      <svg data-testid="icon" {...props} />
    );
    render(
      <Tabs
        value="log"
        onChange={vi.fn()}
        options={[{ value: 'log', label: 'Log', icon: Icon }]}
      />
    );

    const tab = screen.getByRole('tab', { name: 'Log' });
    expect(screen.getByTestId('icon')).toHaveAttribute('aria-hidden', 'true');
    expect(tab.firstElementChild).toBe(screen.getByTestId('icon'));
  });

  test('underline and default size are the base classes', () => {
    render(<Tabs value="log" onChange={vi.fn()} options={options} />);

    const list = screen.getByRole('tablist');
    expect(list).toHaveClass('ui-tabs');
    expect(list).not.toHaveClass('ui-tabs--pills');
    expect(list).not.toHaveClass('ui-tabs--small');
  });

  test('applies the pills and small modifiers', () => {
    render(
      <Tabs
        value="log"
        onChange={vi.fn()}
        options={options}
        variant="pills"
        size="small"
      />
    );

    expect(screen.getByRole('tablist')).toHaveClass(
      'ui-tabs',
      'ui-tabs--pills',
      'ui-tabs--small'
    );
  });

  test('puts className on the tablist', () => {
    render(
      <Tabs value="log" onChange={vi.fn()} options={options} className="mx-3" />
    );

    expect(screen.getByRole('tablist')).toHaveClass('ui-tabs', 'mx-3');
  });
});
