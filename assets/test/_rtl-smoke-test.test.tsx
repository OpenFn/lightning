import { render, screen } from '@testing-library/react';
import { describe, expect, test } from 'vitest';

describe('React Testing Library smoke test', () => {
  test('RTL renders and queries work correctly', () => {
    render(<div>Hello RTL</div>);
    expect(screen.getByText('Hello RTL')).toBeInTheDocument();
  });

  test('RTL can find elements by role', () => {
    render(<button>Click me</button>);
    expect(
      screen.getByRole('button', { name: 'Click me' })
    ).toBeInTheDocument();
  });

  test('RTL can test component props', () => {
    const TestComponent = ({ message }: { message: string }) => (
      <p>{message}</p>
    );
    render(<TestComponent message="Test message" />);
    expect(screen.getByText('Test message')).toBeInTheDocument();
  });
});
