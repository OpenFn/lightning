import type { Meta, StoryObj } from '@storybook/react-vite';
import { useState } from 'react';

import { cn } from '#/utils/cn';

import {
  AppSidebar,
  TopBar,
  Breadcrumbs,
  Crumb,
  ProjectCrumb,
  PageFrame,
  ContentArea,
  Centered,
} from '../liveview/_shell';

/**
 * Composite view: the Project Settings page
 * (lib/lightning_web/live/project_live/settings.html.heex). Shows how the
 * parts connect into a whole — the left sidebar, the header + breadcrumbs, the
 * vertical tabbed nav (`Tabbed.container orientation="vertical"`) and a panel
 * (section_header + a settings form). This is the "project settings" secondary
 * navigation referenced in the brief. Presentational: tab switching is local
 * state; the form is not wired up.
 */
interface SettingsTab {
  hash: string;
  label: string;
  icon: string;
}

const TABS: SettingsTab[] = [
  { hash: 'project', label: 'Setup', icon: 'hero-clipboard' },
  { hash: 'credentials', label: 'Credentials', icon: 'hero-key' },
  { hash: 'collections', label: 'Collections', icon: 'hero-circle-stack' },
  { hash: 'webhook_security', label: 'Webhook Security', icon: 'hero-lock-closed' },
  { hash: 'collaboration', label: 'Collaboration', icon: 'hero-users' },
  { hash: 'security', label: 'Security', icon: 'hero-lock-closed' },
  { hash: 'vcs', label: 'Sync to GitHub', icon: 'hero-arrow-path' },
  { hash: 'data-storage', label: 'Data Storage', icon: 'hero-square-3-stack-3d' },
  { hash: 'history-exports', label: 'History Exports', icon: 'hero-folder-arrow-down' },
];

function SectionHeader({
  title,
  subtitle,
}: {
  title: string;
  subtitle: string;
}) {
  return (
    <div className="flex content-center justify-between">
      <div>
        <h6 className="font-medium text-black">{title}</h6>
        <small className="my-1 block text-xs text-gray-600">{subtitle}</small>
      </div>
    </div>
  );
}

function SetupPanel() {
  return (
    <div className="space-y-4">
      <SectionHeader
        title="Project setup"
        subtitle="Projects are isolated workspaces that contain workflows, accessible to certain users."
      />
      <div className="space-y-4 rounded-md bg-white p-4">
        <div>
          <h6 className="font-medium text-black">Project Identity</h6>
          <small className="my-1 block text-xs text-gray-600">
            This metadata helps you identify the workflows managed in this
            project and the people that have access.
          </small>
        </div>
        <div className="grid grid-cols-1 gap-4">
          <div>
            <label
              htmlFor="settings-name"
              className="text-sm/6 font-medium text-slate-800"
            >
              Name
            </label>
            <input
              id="settings-name"
              type="text"
              defaultValue="openhie-demo"
              className="mt-2 block w-full rounded-lg border-slate-300 text-slate-900 focus:border-slate-400 focus:ring-0 focus:outline-primary-600 sm:text-sm"
            />
          </div>
          <div>
            <label
              htmlFor="settings-desc"
              className="text-sm/6 font-medium text-slate-800"
            >
              Description
            </label>
            <textarea
              id="settings-desc"
              rows={3}
              defaultValue="Demo project for the OpenHIE patient-sync workflows."
              className="mt-2 block w-full rounded-md text-sm shadow-xs focus:ring-0 sm:text-sm border-slate-300 focus:border-slate-400 focus:outline-primary-600"
            />
          </div>
          <div className="flex justify-end">
            <button
              type="button"
              className="cursor-pointer rounded-md bg-primary-600 px-3.5 py-2.5 text-sm font-semibold text-white shadow-xs hover:bg-primary-500"
            >
              Save
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}

function PlaceholderPanel({ tab }: { tab: SettingsTab }) {
  return (
    <div className="space-y-4">
      <SectionHeader
        title={tab.label}
        subtitle={`The ${tab.label} settings panel.`}
      />
      <div className="rounded-md border-2 border-dashed border-gray-300 bg-white/50 p-10 text-center text-sm text-gray-500">
        <span className={cn(tab.icon, 'mx-auto block h-10 w-10 text-secondary-400')} />
        <p className="mt-2">{tab.label} content</p>
      </div>
    </div>
  );
}

const meta = {
  title: 'Pages/Project Settings',
  tags: ['composite'],
  parameters: { layout: 'fullscreen' },
} satisfies Meta;

export default meta;

type Story = StoryObj<typeof meta>;

export const Default: Story = {
  render: function ProjectSettingsPage() {
    const [active, setActive] = useState('project');
    const activeTab = TABS.find(t => t.hash === active);
    return (
      <PageFrame sidebar={<AppSidebar variant="project" activeItem="settings" />}>
        <TopBar>
          <Breadcrumbs>
            <ProjectCrumb label="openhie-demo" />
            <Crumb>Project Settings</Crumb>
          </Breadcrumbs>
        </TopBar>
        <ContentArea>
          <Centered>
            <div className="flex gap-6">
              {/* Vertical tabbed nav (Tabbed.container orientation="vertical") */}
              <nav
                className="flex w-56 shrink-0 flex-col gap-1"
                aria-label="Project settings"
              >
                {TABS.map(tab => {
                  const isActive = tab.hash === active;
                  return (
                    <button
                      key={tab.hash}
                      type="button"
                      role="tab"
                      aria-selected={isActive}
                      onClick={() => {
                        setActive(tab.hash);
                      }}
                      className={cn(
                        'flex items-center gap-2 rounded-md border-l-2 px-3 py-2 text-left text-sm transition-colors',
                        isActive
                          ? 'border-primary-500 bg-white font-semibold text-primary-600'
                          : 'border-transparent text-gray-500 hover:bg-white/60 hover:text-gray-700'
                      )}
                    >
                      <span className={cn(tab.icon, 'h-5 w-5 shrink-0')} />
                      <span className="align-middle">{tab.label}</span>
                    </button>
                  );
                })}
              </nav>
              {/* Active panel */}
              <div className="min-w-0 flex-1">
                {active === 'project' || !activeTab ? (
                  <SetupPanel />
                ) : (
                  <PlaceholderPanel tab={activeTab} />
                )}
              </div>
            </div>
          </Centered>
        </ContentArea>
      </PageFrame>
    );
  },
};
