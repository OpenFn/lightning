import type { Meta, StoryObj } from '@storybook/react-vite';

import { cn } from '#/utils/cn';

import { Showcase, Section, Row, Specimen } from '../_shared/showcase';

/**
 * React clones of `LightningWeb.Components.Common.snapshot_version_chip/1`,
 * `beta_chip/1` and `version_chip/1`
 * (lib/lightning_web/live/components/common.ex).
 *
 * Presentational only. The original `snapshot_version_chip` attaches a
 * `phx-hook="Tooltip"`; here the tooltip text is shown via the native `title`
 * attribute. `version_chip` derives its label/title from `Lightning.release/0`
 * at runtime — the three branches (edge build, tagged release, no image tag)
 * are reproduced with inline fixtures.
 */
function SnapshotVersionChip({
  version,
  tooltip,
}: {
  version: string;
  tooltip?: string;
}) {
  const styles =
    version === 'latest'
      ? 'bg-primary-100 text-primary-800'
      : 'bg-yellow-100 text-yellow-800';

  return (
    <div className="flex items-middle text-sm font-normal">
      <span
        title={tooltip}
        aria-label={tooltip}
        className={cn(
          'inline-flex items-center rounded-md px-1.5 py-0.5 text-xs font-medium',
          styles
        )}
      >
        {version}
      </span>
    </div>
  );
}

function BetaChip() {
  return (
    <div className="flex items-middle text-sm font-normal ml-1">
      <span className="inline-flex items-center rounded-md px-1.5 py-0.5 text-xs font-medium bg-purple-100 text-purple-800">
        BETA
      </span>
    </div>
  );
}

function VersionChip({
  display,
  message,
}: {
  display: string;
  message: string;
}) {
  return (
    <div className="text-[8px] primary-light opacity-50 flex justify-center">
      <code
        className={cn(
          'py-1 rounded-md',
          'break-keep primary-light',
          'inline-block align-middle text-center'
        )}
        title={message}
      >
        {display}
      </code>
    </div>
  );
}

const meta = {
  title: 'LiveView Clones/Chips (LiveView Clone)',
  tags: ['useful'],
  parameters: { layout: 'fullscreen' },
} satisfies Meta;

export default meta;

type Story = StoryObj<typeof meta>;

export const Chips: Story = {
  render: () => (
    <Showcase>
      <Section
        title="snapshot_version_chip/1"
        description='Indicates which workflow snapshot is being viewed. "latest" is primary-tinted; any other version is yellow. Hover for the tooltip.'
      >
        <Row>
          <Specimen label='version="latest"'>
            <SnapshotVersionChip
              version="latest"
              tooltip="You are viewing the latest version of this workflow"
            />
          </Specimen>
          <Specimen label='version="v3"'>
            <SnapshotVersionChip
              version="v3"
              tooltip="You are viewing a past version of this workflow"
            />
          </Specimen>
          <Specimen label="no tooltip">
            <SnapshotVersionChip version="v12" />
          </Specimen>
        </Row>
      </Section>

      <Section
        title="beta_chip/1"
        description="A static purple BETA badge placed next to in-development features."
      >
        <Row>
          <Specimen>
            <BetaChip />
          </Specimen>
          <Specimen label="in context">
            <span className="inline-flex items-center text-sm font-medium text-gray-900">
              Collaborative editor
              <BetaChip />
            </span>
          </Specimen>
        </Row>
      </Section>

      <Section
        title="version_chip/1"
        description="A tiny build identifier shown in the footer. The label and hover title depend on the running release: an unreleased edge build, a tagged release, or a build with no image tag."
      >
        <Row className="gap-8">
          <Specimen label="edge build">
            <VersionChip
              display="a1b2c3d"
              message="Unreleased build 'edge' from a1b2c3d on main"
            />
          </Specimen>
          <Specimen label="tagged release">
            <VersionChip
              display="v2.14.0"
              message="Build 'v2.14.0' from a1b2c3d"
            />
          </Specimen>
          <Specimen label="no image tag">
            <VersionChip display="v2.14.0" message="No image tag found." />
          </Specimen>
        </Row>
      </Section>
    </Showcase>
  ),
};
