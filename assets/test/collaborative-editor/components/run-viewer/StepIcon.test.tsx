import { render } from '@testing-library/react';
import { describe, expect, test } from 'vitest';

import { StepIcon } from '../../../../js/collaborative-editor/components/run-viewer/StepIcon';

describe('StepIcon', () => {
  test('renders the resource-budget icon for kill family error types (known and unknown)', () => {
    const errorTypes = [
      'OOMError',
      'StateTooLargeError',
      'SomeFutureWorkerError',
    ];

    for (const errorType of errorTypes) {
      const { container } = render(
        <StepIcon exitReason="kill" errorType={errorType} />
      );
      const span = container.querySelector('span');
      expect(span?.className).toContain('hero-exclamation-circle-solid');
      expect(span?.className).toContain('text-yellow-800');
    }
  });
});
