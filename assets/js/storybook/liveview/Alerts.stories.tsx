import type { Meta, StoryObj } from '@storybook/react-vite';
import type { ReactNode } from 'react';

import { cn } from '#/utils/cn';

import { Showcase, Section } from '../_shared/showcase';

/**
 * React clones of `LightningWeb.Components.Common.alert/1` and `banner/1`
 * (lib/lightning_web/live/components/common.ex).
 *
 * Presentational only. The original interpolates Tailwind colors at compile
 * time (`bg-#{@color}-50`, etc.); those classes are enumerated literally here
 * so Tailwind emits them. Action buttons drop their `phx-click`/`phx-target`
 * bindings, and the `banner` `alert-#{type}` utility classes are applied as-is.
 */
type AlertType = 'info' | 'success' | 'warning' | 'danger';

interface AlertColors {
  container: string;
  icon: string;
  header: string;
  body: string;
  link: string;
  action: string;
  iconName: string;
}

// Mirrors `select_icon/1` + the `color` mapping in alert/1.
const ALERT_STYLES: Record<AlertType, AlertColors> = {
  info: {
    container: 'bg-blue-50',
    icon: 'text-blue-400',
    header: 'text-blue-800',
    body: 'text-blue-700',
    link: 'text-blue-700 hover:text-blue-600',
    action:
      'bg-blue-50 text-blue-800 hover:bg-blue-100 focus:ring-blue-600 focus:ring-offset-blue-50',
    iconName: 'hero-information-circle-solid',
  },
  success: {
    container: 'bg-green-50',
    icon: 'text-green-400',
    header: 'text-green-800',
    body: 'text-green-700',
    link: 'text-green-700 hover:text-green-600',
    action:
      'bg-green-50 text-green-800 hover:bg-green-100 focus:ring-green-600 focus:ring-offset-green-50',
    iconName: 'hero-check-circle-solid',
  },
  warning: {
    container: 'bg-yellow-50',
    icon: 'text-yellow-400',
    header: 'text-yellow-800',
    body: 'text-yellow-700',
    link: 'text-yellow-700 hover:text-yellow-600',
    action:
      'bg-yellow-50 text-yellow-800 hover:bg-yellow-100 focus:ring-yellow-600 focus:ring-offset-yellow-50',
    iconName: 'hero-exclamation-triangle',
  },
  danger: {
    container: 'bg-red-50',
    icon: 'text-red-400',
    header: 'text-red-800',
    body: 'text-red-700',
    link: 'text-red-700 hover:text-red-600',
    action:
      'bg-red-50 text-red-800 hover:bg-red-100 focus:ring-red-600 focus:ring-offset-red-50',
    iconName: 'hero-x-circle-solid',
  },
};

interface LinkRight {
  text: string;
  target: string;
}

interface AlertAction {
  id: string;
  text: string;
}

function Alert({
  type,
  header,
  children,
  linkRight,
  actions = [],
}: {
  type: AlertType;
  header?: string;
  children: ReactNode;
  linkRight?: LinkRight;
  actions?: AlertAction[];
}) {
  const styles = ALERT_STYLES[type];

  return (
    <div className={cn('rounded-md p-4 text-wrap', styles.container)}>
      <div className={cn('flex', header ? 'items-start' : 'items-center')}>
        <div className="shrink-0">
          <span className={cn(styles.iconName, 'block h-5 w-5', styles.icon)} />
        </div>
        <div
          className={cn(
            'ml-3 min-w-0 flex-1',
            linkRight && 'md:flex md:justify-between'
          )}
        >
          {header ? (
            <>
              <h3 className={cn('text-sm font-medium', styles.header)}>
                {header}
              </h3>
              <div className={cn('mt-2 text-sm', styles.body)}>{children}</div>
            </>
          ) : (
            <div className={cn('text-sm', styles.body)}>{children}</div>
          )}
          {linkRight ? (
            <p className="mt-3 text-sm md:mt-0 md:ml-6">
              <a
                href={linkRight.target}
                className={cn('font-medium whitespace-nowrap', styles.link)}
              >
                {linkRight.text}
                <span aria-hidden="true"> &rarr;</span>
              </a>
            </p>
          ) : null}
          {actions.length > 0 ? (
            <div className="mt-4">
              <div className="-mx-2 -my-1.5 flex">
                {actions.map(action => (
                  <button
                    key={action.id}
                    id={action.id}
                    type="button"
                    className={cn(
                      'rounded-md px-2 py-1.5 text-sm font-medium focus:ring-2 focus:ring-offset-2 focus:outline-none',
                      styles.action
                    )}
                  >
                    {action.text}
                  </button>
                ))}
              </div>
            </div>
          ) : null}
        </div>
      </div>
    </div>
  );
}

// Mirrors the `alert-#{type}` utility classes from assets/css/app.css.
const BANNER_THEME: Record<AlertType, string> = {
  info: 'alert-info',
  success: 'alert-success',
  warning: 'alert-warning',
  danger: 'alert-danger',
};

interface BannerAction {
  text: string;
  target: string;
}

function Banner({
  type,
  message,
  children,
  centered = false,
  icon = false,
  iconName,
  action,
}: {
  type: AlertType;
  message?: string;
  children?: ReactNode;
  centered?: boolean;
  icon?: boolean;
  iconName?: string;
  action?: BannerAction;
}) {
  const resolvedIcon = iconName ?? ALERT_STYLES[type].iconName;

  return (
    <div
      className={cn(
        'flex w-full items-center gap-x-6 px-6 py-2.5 sm:px-3.5',
        centered && 'sm:before:flex-1',
        BANNER_THEME[type]
      )}
    >
      <p className="text-sm leading-6">
        {icon ? (
          <span
            className={cn(
              resolvedIcon,
              'mr-2 inline-block h-5 w-5 align-middle'
            )}
          />
        ) : null}
        {message ?? children}
        {action ? (
          <a href={action.target} className="font-semibold whitespace-nowrap">
            {action.text}
            <span aria-hidden="true"> &rarr;</span>
          </a>
        ) : null}
      </p>
      <div className="flex flex-1 justify-end" />
    </div>
  );
}

const meta = {
  title: 'LiveView Clones/Alerts (LiveView Clone)',
  parameters: { layout: 'fullscreen' },
} satisfies Meta;

export default meta;

type Story = StoryObj<typeof meta>;

export const Alerts: Story = {
  render: () => (
    <Showcase>
      <Section
        title="alert/1 — types"
        description="One alert per type. The color and icon are derived from the type: info (blue), success (green), warning (yellow), danger (red)."
      >
        <div className="flex max-w-2xl flex-col gap-3">
          <Alert type="info">
            A new snapshot of this workflow is available.
          </Alert>
          <Alert type="success">Your credential was saved successfully.</Alert>
          <Alert type="warning">
            This workflow has unsaved changes that will be lost.
          </Alert>
          <Alert type="danger">
            We could not connect to the worker. Runs are paused.
          </Alert>
        </div>
      </Section>

      <Section
        title="alert/1 — with header"
        description="When a header is given the layout switches to items-start, with the title above the message."
      >
        <div className="max-w-2xl">
          <Alert type="warning" header="Workflow validation failed">
            Two jobs are missing an adaptor. Fix them before enabling the
            trigger.
          </Alert>
        </div>
      </Section>

      <Section
        title="alert/1 — with link_right"
        description="A trailing call-to-action link that floats to the right on medium screens."
      >
        <div className="max-w-2xl">
          <Alert
            type="info"
            linkRight={{ text: 'View docs', target: 'https://docs.openfn.org' }}
          >
            Adaptors connect your jobs to external systems.
          </Alert>
        </div>
      </Section>

      <Section
        title="alert/1 — with actions"
        description="A row of action buttons. In the app each button carries a phx-click; here they are inert."
      >
        <div className="max-w-2xl">
          <Alert
            type="danger"
            header="Delete this project?"
            actions={[
              { id: 'confirm-delete', text: 'Delete project' },
              { id: 'cancel-delete', text: 'Cancel' },
            ]}
          >
            This permanently removes all workflows, runs and credentials.
          </Alert>
        </div>
      </Section>

      <Section
        title="banner/1"
        description="Full-width notices using the alert-* utility themes. Banners can carry an inline icon and a single action link, and can be horizontally centered."
      >
        <div className="flex flex-col gap-3 overflow-hidden rounded-md">
          <Banner type="info" icon message="Scheduled maintenance tonight at 22:00 UTC." />
          <Banner
            type="success"
            icon
            message="GitHub sync is connected."
            action={{ text: 'View repository', target: 'https://github.com' }}
          />
          <Banner
            type="warning"
            centered
            message="Your trial ends in 3 days."
            action={{ text: 'Upgrade', target: '#' }}
          />
          <Banner type="danger" icon>
            A run failed and could not be retried automatically.
          </Banner>
        </div>
      </Section>
    </Showcase>
  ),
};
