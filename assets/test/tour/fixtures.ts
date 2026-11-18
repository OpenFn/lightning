import type { AppMapPage } from '#/tour/plan';

/**
 * A representative subset of the real app map, copied from priv/app_map.json
 * (project_settings carries only three of its tabs to keep the fixture short).
 */
export const appMapPages: AppMapPage[] = [
  {
    description:
      "The project overview: lists the project's workflows with run activity and success metrics, and is where new workflows are created, and existing ones enabled, disabled, or deleted.",
    id: 'project_workflows',
    label: 'Workflows',
    module: 'LightningWeb.WorkflowLive.Index',
    path: '/projects/:project_id/w',
    section: 'project',
  },
  {
    description:
      'The real-time collaborative editor for a workflow: build the DAG of triggers, jobs, and edges, write job code with adaptors and credentials, run work manually, and inspect runs — with live cursors of other editors.',
    id: 'workflow_edit',
    label: 'Workflow editor',
    module: 'LightningWeb.WorkflowLive.Collaborate',
    path: '/projects/:project_id/w/:id',
    section: 'project',
    elements: [
      {
        description:
          'A job step node on the workflow diagram; click it to open its configuration panel.',
        id: 'canvas-step',
        label: 'Workflow step',
      },
      {
        description:
          'Choose which saved credential the selected step uses to authenticate against the external system it talks to.',
        hint: 'Select a step on the canvas to open its configuration panel first.',
        id: 'credential-picker',
        label: 'Credential picker',
        requires: 'canvas-step',
      },
      {
        description:
          'Opens the full-screen editor for the selected step, with code, docs, and run panels.',
        id: 'open-editor',
        label: 'Open editor',
        requires: 'canvas-step',
      },
      {
        description:
          "Adaptor function documentation for the selected step's adaptor.",
        id: 'docs-tab',
        label: 'Docs tab',
        requires: 'open-editor',
      },
      {
        description:
          'Run the workflow manually from here, using a custom or existing input.',
        id: 'run-button',
        label: 'Run button',
      },
    ],
  },
  {
    description:
      'Search and filter past work orders and runs by status, workflow, date, and dataclip content; inspect results and retry or rerun failed work in bulk.',
    id: 'project_history',
    label: 'History',
    module: 'LightningWeb.RunLive.Index',
    path: '/projects/:project_id/history',
    section: 'project',
  },
  {
    description:
      "The channels tab of History: a log of HTTP requests proxied through the project's channels, filterable by channel and outcome.",
    id: 'channel_logs',
    label: 'Channel logs',
    module: 'LightningWeb.RunLive.Index',
    path: '/projects/:project_id/history/channels',
    section: 'project',
  },
  {
    description:
      "List and manage the project's channels — HTTP proxy configurations that forward requests from a client to a destination. Experimental feature.",
    id: 'project_channels',
    label: 'Channels',
    module: 'LightningWeb.ChannelLive.Index',
    path: '/projects/:project_id/channels',
    section: 'project',
  },
  {
    description:
      'Form for creating a channel: configure the destination, authentication, and request persistence policy.',
    id: 'channel_new',
    label: 'New channel',
    module: 'LightningWeb.ChannelLive.Index',
    path: '/projects/:project_id/channels/new',
    section: 'project',
  },
  {
    description:
      "List and manage the project's sandboxes — isolated copies of the project for safe experimentation — and merge sandbox changes back into the parent.",
    id: 'project_sandboxes',
    label: 'Sandboxes',
    module: 'LightningWeb.SandboxLive.Index',
    path: '/projects/:project_id/sandboxes',
    section: 'project',
  },
  {
    description:
      "Detail view of a single run: live logs, the steps it executed, and each step's input and output dataclips.",
    id: 'run_show',
    label: 'Run details',
    module: 'LightningWeb.RunLive.Show',
    path: '/projects/:project_id/runs/:id',
    section: 'project',
  },
  {
    description:
      'Project settings, organised into tabs addressed by URL hash (e.g. #vcs): setup, credentials, collections, webhook security, collaboration, security, GitHub sync, data storage, and history exports.',
    id: 'project_settings',
    label: 'Settings',
    module: 'LightningWeb.ProjectLive.Settings',
    path: '/projects/:project_id/settings',
    section: 'project',
    tabs: [
      {
        description:
          'Edit the project (or sandbox) name and description, view the project UUID, and export a copy of the project as YAML.',
        hash: 'project',
        label: 'Setup',
      },
      {
        description:
          'Connect this project to a GitHub repository and manage version control sync settings.',
        hash: 'vcs',
        label: 'Sync to GitHub',
      },
      {
        description:
          "Choose how input/output data from runs is retained and manage this project's data storage policy.",
        hash: 'data-storage',
        label: 'Data Storage',
      },
    ],
  },
  {
    description:
      'Confirmation dialog on project settings for scheduling the project for deletion.',
    id: 'project_delete',
    label: 'Delete project',
    module: 'LightningWeb.ProjectLive.Settings',
    path: '/projects/:project_id/settings/delete',
    section: 'project',
  },
  {
    description:
      "List and manage the user's credentials and OAuth clients for external services: create, edit, delete, and transfer them, and control which projects can use them.",
    id: 'credentials',
    label: 'Credentials',
    module: 'LightningWeb.CredentialLive.Index',
    path: '/credentials',
    section: 'user',
  },
  {
    description:
      'List, generate, and revoke personal access tokens used to authenticate against the Lightning API.',
    id: 'api_tokens',
    label: 'API Tokens',
    module: 'LightningWeb.TokensLive.Index',
    path: '/profile/tokens',
    section: 'user',
  },
  {
    description:
      'The landing page after login: lists the projects the user belongs to, with workflow counts and recent run activity, and is the entry point into each project.',
    id: 'projects_dashboard',
    label: 'Projects',
    module: 'LightningWeb.DashboardLive.Index',
    path: '/projects',
    section: 'user',
  },
  {
    description:
      'View, copy, print, and regenerate the one-time backup codes used to log in when the authenticator device is unavailable. Requires re-authentication to open.',
    id: 'backup_codes',
    label: 'Backup codes',
    module: 'LightningWeb.BackupCodesLive.Index',
    path: '/profile/auth/backup_codes',
    section: 'user',
  },
  {
    description:
      'Superuser list of every user account on the instance, with links to create, edit, and delete users.',
    id: 'admin_users',
    label: 'Users',
    module: 'LightningWeb.UserLive.Index',
    path: '/settings/users',
    section: 'admin',
  },
  {
    description:
      'Sign in to Lightning with an email and password, or via a configured external identity provider.',
    id: 'login',
    label: 'Log in',
    module: 'LightningWeb.UserSessionController',
    path: '/users/log_in',
    section: 'auth',
  },
];
