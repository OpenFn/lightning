import { render } from '@testing-library/react';
import { afterEach, describe, expect, test, vi } from 'vitest';

import { StepIcon } from '../../../../js/collaborative-editor/components/run-viewer/StepIcon';

describe('StepIcon', () => {
  afterEach(() => {
    vi.restoreAllMocks();
  });

  test('renders the resource-budget icon for kill family error types (known and unknown)', () => {
    vi.spyOn(console, 'warn').mockImplementation(() => {});

    for (const errorType of [
      'OOMError',
      'StateTooLargeError',
      'SomeFutureWorkerError',
    ]) {
      const { container } = render(
        <StepIcon exitReason="kill" errorType={errorType} />
      );
      const span = container.querySelector('span');
      expect(span?.className).toContain('hero-exclamation-circle-solid');
      expect(span?.className).toContain('text-yellow-800');
    }
  });

  test('warns on unknown kill error types but not on known ones', () => {
    const warnSpy = vi.spyOn(console, 'warn').mockImplementation(() => {});

    render(<StepIcon exitReason="kill" errorType="OOMError" />);
    render(<StepIcon exitReason="kill" errorType="StateTooLargeError" />);
    expect(warnSpy).not.toHaveBeenCalled();

    render(<StepIcon exitReason="kill" errorType="SomeFutureWorkerError" />);
    expect(warnSpy).toHaveBeenCalledOnce();
    expect(warnSpy).toHaveBeenCalledWith(
      expect.stringContaining('SomeFutureWorkerError')
    );
  });
});
