import type { Meta, StoryObj } from '@storybook/react-vite';
import type { ReactNode } from 'react';

import { cn } from '#/utils/cn';

import { Showcase, Section } from '../_shared/showcase';

/**
 * React clones of Lightning's banner/alert components:
 *
 *   * `workflow_info_banner/1` and `deprecated_warning/1` from
 *     `LightningWeb.WorkflowLive.Components`
 *     (lib/lightning_web/live/workflow_live/components.ex)
 *   * `sandbox_settings_banner/1` from
 *     `LightningWeb.Components.SandboxSettingsBanner`
 *     (lib/lightning_web/components/sandbox_settings_banner.ex), which renders
 *     `Common.alert/1` (lib/lightning_web/live/components/common.ex)
 *
 * Presentational only — `phx-click="switch_to_collab_editor"` and the Tooltip
 * hooks are dropped. The `Common.alert` colour is interpolated at runtime in
 * the server template (`bg-#{color}-50`, etc.); the equivalent literal classes
 * are inlined per variant here so Tailwind keeps them.
 */

// --- workflow_info_banner/1 -------------------------------------------------
function WorkflowInfoBanner({
  message,
  position = '',
}: {
  message: string;
  position?: string;
}) {
  return (
    <div
      className={cn(
        position,
        'w-full flex-none border-1 border-yellow-400 bg-yellow-50 p-4'
      )}
    >
      <div className="max-w-7xl mx-auto sm:px-6 lg:px-8 flex">
        <div className="flex-shrink-0">
          <span className="hero-exclamation-triangle-solid h-5 w-5 text-yellow-400" />
        </div>
        <div className="ml-2">
          <p className="text-sm text-yellow-700">{message}</p>
        </div>
      </div>
    </div>
  );
}

// --- deprecated_warning/1 ---------------------------------------------------
function DeprecatedWarning() {
  return (
    <button
      type="button"
      aria-label="You're using the legacy workflow builder and will soon be upgraded. Click to switch now."
      className="w-6 h-6 place-self-center text-yellow-500 hover:text-yellow-400 cursor-pointer"
    >
      <span className="hero-exclamation-triangle-solid" />
    </button>
  );
}

// --- Common.alert/1, as used by sandbox_settings_banner/1 -------------------
type AlertType = 'info' | 'success' | 'warning';

const ALERT_BG: Record<AlertType, string> = {
  info: 'bg-blue-50',
  success: 'bg-green-50',
  warning: 'bg-yellow-50',
};

// Mirrors Common.select_icon/1.
const ALERT_ICON: Record<AlertType, string> = {
  info: 'hero-information-circle-solid',
  success: 'hero-check-circle-solid',
  warning: 'hero-exclamation-triangle',
};

const ALERT_ICON_TEXT: Record<AlertType, string> = {
  info: 'text-blue-400',
  success: 'text-green-400',
  warning: 'text-yellow-400',
};

const ALERT_BODY_TEXT: Record<AlertType, string> = {
  info: 'text-blue-700',
  success: 'text-green-700',
  warning: 'text-yellow-700',
};

function Alert({
  type,
  className,
  children,
}: {
  type: AlertType;
  className?: string;
  children: ReactNode;
}) {
  return (
    <div className={cn('rounded-md p-4 text-wrap', ALERT_BG[type], className)}>
      <div className="flex items-center">
        <div className="shrink-0">
          <span className={cn(ALERT_ICON[type], 'block h-5 w-5', ALERT_ICON_TEXT[type])} />
        </div>
        <div className="ml-3 min-w-0 flex-1">
          <div className={cn('text-sm', ALERT_BODY_TEXT[type])}>{children}</div>
        </div>
      </div>
    </div>
  );
}

// --- sandbox_settings_banner/1 ----------------------------------------------
type SandboxVariant = 'local' | 'editable' | 'inherited';

function SandboxSettingsBanner({
  variant,
  parentProjectName,
}: {
  variant: SandboxVariant;
  parentProjectName?: string;
}) {
  if (variant === 'local') {
    return (
      <Alert type="info" className="border border-blue-300">
        Changes you make here only apply to this sandbox and do not sync to the
        parent project on merge.
      </Alert>
    );
  }

  if (variant === 'editable') {
    return (
      <Alert type="success" className="border border-green-400">
        Changes you make here will sync to the parent project on merge.
      </Alert>
    );
  }

  return (
    <Alert type="warning" className="border border-yellow-300">
      These settings are inherited from the parent project
      {parentProjectName ? (
        <>
          {' '}
          (
          <a href="#parent-settings" className="font-medium underline">
            {parentProjectName}
          </a>
          )
        </>
      ) : null}
      and cannot be changed here.
    </Alert>
  );
}

const meta = {
  title: 'LiveView Clones/Banners (LiveView Clone)',
  tags: ['useful'],
  parameters: { layout: 'fullscreen' },
} satisfies Meta;

export default meta;

type Story = StoryObj<typeof meta>;

export const WorkflowInfo: Story = {
  name: 'Workflow info banner',
  render: () => (
    <Showcase className="min-w-[640px]">
      <Section
        title="workflow_info_banner/1"
        description="A full-width yellow notice shown above the workflow editor."
      >
        <WorkflowInfoBanner message="This workflow has unsaved changes. Save before running it to apply your edits." />
      </Section>
    </Showcase>
  ),
};

export const Deprecated: Story = {
  name: 'Deprecated warning',
  render: () => (
    <Showcase className="min-w-[480px]">
      <Section
        title="deprecated_warning/1"
        description="A small triangle button warning that the legacy builder will be upgraded. Hover for the lighter shade."
      >
        <div className="flex items-center gap-2">
          <DeprecatedWarning />
          <span className="text-sm text-gray-600">Legacy workflow builder</span>
        </div>
      </Section>
    </Showcase>
  ),
};

export const SandboxSettings: Story = {
  name: 'Sandbox settings banner',
  render: () => (
    <Showcase className="min-w-[640px]">
      <Section
        title="sandbox_settings_banner/1"
        description="Shown atop a sandbox project's settings tab. Three variants describe how edits flow to the parent project on merge."
      >
        <div className="flex flex-col gap-4">
          <SandboxSettingsBanner variant="local" />
          <SandboxSettingsBanner variant="editable" />
          <SandboxSettingsBanner
            variant="inherited"
            parentProjectName="Ministry of Health"
          />
        </div>
      </Section>
    </Showcase>
  ),
};
