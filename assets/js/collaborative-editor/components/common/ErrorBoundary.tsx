import { Component, type ReactNode } from 'react';

interface ErrorBoundaryProps {
  children: ReactNode;
  /**
   * Names the failing area in the console log, e.g. "ManualRunPanel". Every
   * boundary logs, so this is what tells them apart in a stack of them.
   */
  label: string;
  /**
   * Rendered in place of `children` once an error is caught. Receives `reset`
   * so a fallback can offer a retry; boundaries whose fallback is terminal can
   * ignore it.
   */
  fallback: (error: Error, reset: () => void) => ReactNode;
  onError?: (error: Error) => void;
}

interface ErrorBoundaryState {
  error: Error | null;
}

/**
 * The one error boundary in the collaborative editor.
 *
 * React only lets class components catch render errors, so each boundary used
 * to be hand-written — three near-identical classes differing only in their
 * fallback markup. Everything except the markup lives here; callers supply a
 * `fallback` and, where they need one, a named wrapper around this component.
 *
 * Note that this catches errors thrown during render, not in event handlers,
 * effects that escape to a promise, or timers. Async failures still need their
 * own handling at the call site.
 */
export class ErrorBoundary extends Component<
  ErrorBoundaryProps,
  ErrorBoundaryState
> {
  override state: ErrorBoundaryState = { error: null };

  static getDerivedStateFromError(error: Error): ErrorBoundaryState {
    return { error };
  }

  override componentDidCatch(error: Error) {
    console.error(`${this.props.label} error:`, error);
    this.props.onError?.(error);
  }

  private readonly reset = () => {
    this.setState({ error: null });
  };

  override render() {
    const { error } = this.state;
    if (error) return this.props.fallback(error, this.reset);
    return this.props.children;
  }
}
