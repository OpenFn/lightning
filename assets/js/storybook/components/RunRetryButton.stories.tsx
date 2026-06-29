import type { Meta, StoryObj } from '@storybook/react-vite';

import { RunRetryButton } from '#/collaborative-editor/components/RunRetryButton';

import { Showcase, Section, Row, Specimen } from '../_shared/showcase';

/**
 * Run / Retry button for the collaborative editor
 * (`js/collaborative-editor/components/RunRetryButton.tsx`). It is fully
 * driven by props (no stores), so it renders standalone:
 * - Not retryable -> a single "Run Workflow" button.
 * - Retryable -> a split button ("Run (Retry)" + chevron) whose dropdown
 *   offers "Run (New Work Order)".
 * - Submitting -> spinner + "Processing", chevron kept for layout stability.
 *
 * `primary` and `secondary` visual variants are available. Callbacks are
 * stubbed with no-ops.
 */
const meta = {
  title: 'Components/Run Retry Button',
  tags: ['useful', 'modular'],
  component: RunRetryButton,
  parameters: { layout: 'centered' },
  args: {
    isRetryable: true,
    isDisabled: false,
    isSubmitting: false,
    variant: 'primary',
    dropdownPosition: 'down',
    showKeyboardShortcuts: false,
    onRun: () => {},
    onRetry: () => {},
  },
  argTypes: {
    variant: { control: 'inline-radio', options: ['primary', 'secondary'] },
    dropdownPosition: { control: 'inline-radio', options: ['up', 'down'] },
  },
} satisfies Meta<typeof RunRetryButton>;

export default meta;

type Story = StoryObj<typeof meta>;

export const Playground: Story = {};

export const States: Story = {
  render: () => (
    <Showcase>
      <Section
        title="Primary"
        description="Idle (run-only), retryable split button, and submitting."
      >
        <Row>
          <Specimen label="not retryable">
            <RunRetryButton
              isRetryable={false}
              isDisabled={false}
              isSubmitting={false}
              onRun={() => {}}
              onRetry={() => {}}
            />
          </Specimen>
          <Specimen label="retryable">
            <RunRetryButton
              isRetryable
              isDisabled={false}
              isSubmitting={false}
              onRun={() => {}}
              onRetry={() => {}}
            />
          </Specimen>
          <Specimen label="submitting">
            <RunRetryButton
              isRetryable
              isDisabled={false}
              isSubmitting
              onRun={() => {}}
              onRetry={() => {}}
            />
          </Specimen>
          <Specimen label="disabled">
            <RunRetryButton
              isRetryable
              isDisabled
              isSubmitting={false}
              onRun={() => {}}
              onRetry={() => {}}
            />
          </Specimen>
        </Row>
      </Section>

      <Section title="Secondary">
        <Row>
          <Specimen label="not retryable">
            <RunRetryButton
              variant="secondary"
              isRetryable={false}
              isDisabled={false}
              isSubmitting={false}
              onRun={() => {}}
              onRetry={() => {}}
            />
          </Specimen>
          <Specimen label="retryable">
            <RunRetryButton
              variant="secondary"
              isRetryable
              isDisabled={false}
              isSubmitting={false}
              onRun={() => {}}
              onRetry={() => {}}
            />
          </Specimen>
        </Row>
      </Section>
    </Showcase>
  ),
};
