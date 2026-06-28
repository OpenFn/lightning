import type { Meta, StoryObj } from '@storybook/react-vite';

import { Showcase, Section, Row, Specimen } from '../_shared/showcase';

/**
 * Custom Tailwind `@utility` classes defined in `assets/css/app.css`. These are
 * app-wide building blocks (link styles, table action buttons, the shared modal
 * backdrop and the AI gradients) used by both HEEx and React. Class names are
 * literal so Tailwind emits them.
 */
const meta = {
  title: 'LiveView Clones/Utilities (LiveView Clone)',
  parameters: { layout: 'fullscreen' },
} satisfies Meta;

export default meta;

type Story = StoryObj<typeof meta>;

export const Utilities: Story = {
  render: () => (
    <Showcase>
      <Section
        title="Links"
        description="Anchor styles. The base `link` plus semantic variants and the monospace `link-uuid` used for IDs."
      >
        <Row className="gap-6">
          <a className="link" href="https://docs.openfn.org">
            link
          </a>
          <a className="link-info" href="https://docs.openfn.org">
            link-info
          </a>
          <a className="link-danger" href="https://docs.openfn.org">
            link-danger
          </a>
          <a className="link-success" href="https://docs.openfn.org">
            link-success
          </a>
          <a className="link-warning" href="https://docs.openfn.org">
            link-warning
          </a>
          <a className="link-plain" href="https://docs.openfn.org">
            link-plain
          </a>
          <a className="link-uuid" href="https://docs.openfn.org">
            a1b2c3d4-e5f6
          </a>
        </Row>
      </Section>

      <Section
        title="Table actions"
        description="The `table-action` button used in table rows, plus its disabled variant."
      >
        <Row>
          <button type="button" className="table-action">
            Rerun
          </button>
          <button type="button" className="table-action">
            View
          </button>
          <button type="button" className="table-action-disabled" disabled>
            Delete
          </button>
        </Row>
      </Section>

      <Section
        title="AI gradients"
        description="Gradient backgrounds used by the AI assistant surfaces."
      >
        <Row>
          <Specimen label="ai-bg-gradient">
            <div className="ai-bg-gradient h-16 w-40 rounded-lg" />
          </Specimen>
          <Specimen label="ai-bg-gradient-light">
            <div className="ai-bg-gradient-light h-16 w-40 rounded-lg" />
          </Specimen>
          <Specimen label="ai-bg-gradient-error">
            <div className="ai-bg-gradient-error h-16 w-40 rounded-lg" />
          </Specimen>
        </Row>
      </Section>

      <Section
        title="modal-backdrop"
        description="The single source-of-truth overlay used behind every modal (rendered here inside a relative box; it is position: fixed in the app)."
      >
        <div className="relative h-40 w-full max-w-md overflow-hidden rounded-lg border border-gray-200">
          <div className="p-4 text-sm text-gray-700">
            Page content sitting behind the backdrop.
          </div>
          <div className="absolute inset-0 bg-gray-900/60 backdrop-blur-xs" />
          <div className="absolute inset-0 flex items-center justify-center">
            <span className="rounded-md bg-white px-3 py-2 text-sm font-medium text-gray-900 shadow">
              Dialog
            </span>
          </div>
        </div>
      </Section>
    </Showcase>
  ),
};
