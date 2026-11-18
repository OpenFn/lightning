defmodule LightningWeb.AppMap do
  @moduledoc """
  A build-time, machine-readable catalog of every user-facing page in
  Lightning — "the app map". It is intended to be fed to the AI assistant so
  it can tell users where things are.

  ## How it works

  Routes are discovered at runtime via `Phoenix.Router.routes/1`, never by
  parsing `router.ex`. That matters: four top-level pages (`/projects`,
  `/projects/:project_id/settings`, `/profile`, `/settings/users`) are not in
  the router file at all — they are injected at compile time from
  `config/config.exs` via `Lightning.Extensions.Routing`. Router introspection
  sees them; file parsing would not.

  The human-authored content (id, label, section, description, tabs) lives in
  the catalog in this module, keyed by route *path pattern* so it stays stable
  across module renames. `build/0` joins the introspected routes with the
  catalog and raises if a non-excluded route has no catalog entry — adding a
  page without describing it (or excluding it) fails the test suite. See
  `test/lightning_web/app_map_test.exs`.

  ## What counts as a page

  GET routes that render a browser page a user navigates to. Everything else
  is excluded, by path prefix or exact path:

  * machine APIs: `/api`, `/collections`, `/i` (webhooks), `/health_check`,
    `/.well-known` (OAuth metadata), `/adaptors` (icon assets and the JSON
    catalogue)
  * data/download endpoints that return files or JSON rather than pages:
    `/download`, `/dataclip`, `/project_files`, dataclip/step JSON endpoints
    under `/projects`
  * auth-flow plumbing the user never "goes to": OIDC/OAuth callbacks
    (`/authenticate`, `/oauth`), token-exchange logins, email-token landing
    pages, logout, the send-confirmation-email trigger, the credential
    transfer confirmation link
  * operational/dev UIs that are not part of the product: Phoenix
    LiveDashboard (`/dashboard`), `/dev` routes
  * redirects: `/` (to `/projects`), the retired legacy editor URLs
    (`/w/new/legacy`, `/w/:id/legacy`), and `/setup_vcs` (a self-closing
    popup used by the GitHub app installation flow)
  * `/profile/auth/backup_codes/print` — a print rendition of the backup
    codes page, which is catalogued at its live route
  """

  @typedoc "A page entry in the app map."
  @type page :: %{
          required(:id) => String.t(),
          required(:path) => String.t(),
          required(:module) => String.t(),
          required(:label) => String.t(),
          required(:section) => String.t(),
          required(:description) => String.t(),
          optional(:tabs) => [
            %{hash: String.t(), label: String.t(), description: String.t()}
          ]
        }

  @excluded_prefixes [
    # machine APIs and infrastructure
    "/api",
    "/i",
    "/collections",
    "/health_check",
    "/.well-known",
    "/adaptors",
    # file/JSON endpoints, not pages
    "/download",
    "/dataclip",
    "/project_files",
    # auth-flow plumbing (external IdP callbacks)
    "/authenticate",
    "/oauth",
    # operational/dev UIs
    "/dashboard",
    "/dev"
  ]

  @excluded_paths [
    # redirects
    "/",
    "/projects/:project_id/w/new/legacy",
    "/projects/:project_id/w/:id/legacy",
    # auth/session plumbing
    "/users/log_out",
    "/users/token_exchange/:token",
    "/users/confirm/:token",
    "/users/send-confirmation-email",
    "/profile/confirm_email/:token",
    "/credentials/transfer/:token",
    # self-closing popup at the end of the GitHub app installation flow
    "/setup_vcs",
    # print rendition of the backup codes live page
    "/profile/auth/backup_codes/print",
    # JSON endpoints under /projects
    "/projects/:project_id/jobs/:job_id/dataclips",
    "/projects/:project_id/runs/:run_id/dataclip",
    "/projects/:project_id/runs/:run_id/steps"
  ]

  @project_settings_tabs [
    %{
      hash: "project",
      label: "Setup",
      description:
        "Edit the project (or sandbox) name and description, view the project UUID, and export a copy of the project as YAML."
    },
    %{
      hash: "credentials",
      label: "Credentials",
      description:
        "Manage the OAuth 2.0 clients and credentials accessible to this project."
    },
    %{
      hash: "collections",
      label: "Collections",
      description:
        "Create, rename, and delete this project's collections — key-value data stores that jobs can read and write."
    },
    %{
      hash: "webhook_security",
      label: "Webhook Security",
      description:
        "Manage webhook authentication methods used by the webhook triggers that start workflows."
    },
    %{
      hash: "collaboration",
      label: "Collaboration",
      description:
        "View collaborators, add or remove project users, and manage failure alerts and digest email settings."
    },
    %{
      hash: "security",
      label: "Security",
      description:
        "Manage project security settings, such as requiring multi-factor authentication from all collaborators."
    },
    %{
      hash: "vcs",
      label: "Sync to GitHub",
      description:
        "Connect this project to a GitHub repository and manage version control sync settings."
    },
    %{
      hash: "data-storage",
      label: "Data Storage",
      description:
        "Choose how input/output data from runs is retained and manage this project's data storage policy."
    },
    %{
      hash: "history-exports",
      label: "History Exports",
      description:
        "View the status of work order history exports and download completed export files."
    }
  ]

  # Authored content for every included page, keyed by route path pattern.
  # Path patterns are stable across refactors of module names; `build/0`
  # verifies the catalog stays in sync with the router in both directions.
  @catalog %{
    ## Auth
    "/users/log_in" => %{
      id: "login",
      label: "Log in",
      section: "auth",
      description:
        "Sign in to Lightning with an email and password, or via a configured external identity provider."
    },
    "/users/register" => %{
      id: "register",
      label: "Register",
      section: "auth",
      description:
        "Create a new user account. Only available when self-signup is enabled on the instance."
    },
    "/users/reset_password" => %{
      id: "forgot_password",
      label: "Forgot password",
      section: "auth",
      description:
        "Request a password reset email by entering the account's email address."
    },
    "/users/reset_password/:token" => %{
      id: "reset_password",
      label: "Reset password",
      section: "auth",
      description:
        "Choose a new password after following the reset link from the password reset email."
    },
    "/users/two-factor" => %{
      id: "two_factor",
      label: "Two-factor authentication",
      section: "auth",
      description:
        "Complete login by entering a time-based one-time code from an authenticator app, or a backup code."
    },
    "/users/confirm" => %{
      id: "resend_confirmation",
      label: "Resend confirmation email",
      section: "auth",
      description:
        "Request a new account-confirmation email by entering the account's email address."
    },
    "/users/confirm-required" => %{
      id: "confirmation_required",
      label: "Email confirmation required",
      section: "auth",
      description:
        "Shown when an account is locked pending email confirmation. Resend the confirmation link or correct a mistyped email address."
    },
    "/auth/confirm_access" => %{
      id: "confirm_access",
      label: "Confirm access",
      section: "auth",
      description:
        "Re-authenticate with a password or two-factor code before performing a sensitive action, such as viewing backup codes."
    },
    "/mfa_required" => %{
      id: "mfa_required",
      label: "MFA required",
      section: "auth",
      description:
        "Shown when a project requires multi-factor authentication that the current user has not enabled. Explains how to set up MFA to regain access."
    },

    ## User (personal) pages
    "/projects" => %{
      id: "projects_dashboard",
      label: "Projects",
      section: "user",
      description:
        "The landing page after login: lists the projects the user belongs to, with workflow counts and recent run activity, and is the entry point into each project."
    },
    "/profile" => %{
      id: "profile",
      label: "User Profile",
      section: "user",
      description:
        "Manage the user's own account: change name, email, and password, enable multi-factor authentication, connect GitHub, toggle experimental features, and delete the account."
    },
    "/profile/:id/delete" => %{
      id: "profile_delete",
      label: "Delete account",
      section: "user",
      description:
        "Confirmation dialog on the profile page for permanently deleting the user's own account."
    },
    "/credentials" => %{
      id: "credentials",
      label: "Credentials",
      section: "user",
      description:
        "List and manage the user's credentials and OAuth clients for external services: create, edit, delete, and transfer them, and control which projects can use them."
    },
    "/profile/tokens" => %{
      id: "api_tokens",
      label: "API Tokens",
      section: "user",
      description:
        "List, generate, and revoke personal access tokens used to authenticate against the Lightning API."
    },
    "/profile/tokens/:id/delete" => %{
      id: "api_token_delete",
      label: "Revoke API token",
      section: "user",
      description:
        "Confirmation dialog on the API tokens page for revoking a personal access token."
    },
    "/profile/auth/backup_codes" => %{
      id: "backup_codes",
      label: "Backup codes",
      section: "user",
      description:
        "View, copy, print, and regenerate the one-time backup codes used to log in when the authenticator device is unavailable. Requires re-authentication to open."
    },

    ## Instance administration (superuser)
    "/first_setup" => %{
      id: "first_setup",
      label: "First setup",
      section: "admin",
      description:
        "Create the first superuser account on a freshly installed instance. Only available until a user exists."
    },
    "/settings/users" => %{
      id: "admin_users",
      label: "Users",
      section: "admin",
      description:
        "Superuser list of every user account on the instance, with links to create, edit, and delete users."
    },
    "/settings/users/new" => %{
      id: "admin_user_new",
      label: "New user",
      section: "admin",
      description:
        "Superuser form for creating a user account, including role (user or superuser) and scheduled deletion."
    },
    "/settings/users/:id" => %{
      id: "admin_user_edit",
      label: "Edit user",
      section: "admin",
      description:
        "Superuser form for editing an existing user account's details and role."
    },
    "/settings/users/:id/delete" => %{
      id: "admin_user_delete",
      label: "Delete user",
      section: "admin",
      description:
        "Confirmation dialog on the users list for scheduling a user account for deletion."
    },
    "/settings/projects" => %{
      id: "admin_projects",
      label: "Projects (admin)",
      section: "admin",
      description:
        "Superuser list of every project on the instance, with links to create, edit, and delete projects."
    },
    "/settings/projects/new" => %{
      id: "admin_project_new",
      label: "New project",
      section: "admin",
      description:
        "Superuser form for creating a project and assigning users to it with roles."
    },
    "/settings/projects/:id" => %{
      id: "admin_project_edit",
      label: "Edit project",
      section: "admin",
      description:
        "Superuser form for editing a project's details and user assignments."
    },
    "/settings/projects/:id/delete" => %{
      id: "admin_project_delete",
      label: "Delete project",
      section: "admin",
      description:
        "Confirmation dialog on the admin projects list for scheduling a project for deletion."
    },
    "/settings/audit" => %{
      id: "audit_trail",
      label: "Audit",
      section: "admin",
      description:
        "Superuser view of the instance audit trail: who did what and when, across logins, credential changes, project changes, and more."
    },
    "/settings/maintenance" => %{
      id: "maintenance",
      label: "Maintenance",
      section: "admin",
      description:
        "Superuser maintenance actions: refresh the adaptor registry and re-fetch adaptor icons on demand."
    },
    "/settings/authentication" => %{
      id: "auth_providers",
      label: "Authentication",
      section: "admin",
      description:
        "Superuser configuration of an external identity provider (OIDC) for single sign-on."
    },
    "/settings/authentication/new" => %{
      id: "auth_provider_new",
      label: "New authentication provider",
      section: "admin",
      description:
        "Superuser form for adding an external identity provider (OIDC) configuration."
    },
    "/settings/collections" => %{
      id: "admin_collections",
      label: "Collections (admin)",
      section: "admin",
      description:
        "Superuser list of every collection on the instance: create, rename, and delete the key-value data stores that jobs can use."
    },

    ## Project pages
    "/projects/:project_id/w" => %{
      id: "project_workflows",
      label: "Workflows",
      section: "project",
      description:
        "The project overview: lists the project's workflows with run activity and success metrics, and is where new workflows are created, and existing ones enabled, disabled, or deleted."
    },
    "/projects/:project_id/w/new" => %{
      id: "workflow_new",
      label: "New workflow",
      section: "project",
      description:
        "The collaborative workflow editor opened on a brand-new workflow: name it, add a trigger, jobs, and edges, then save it into the project."
    },
    "/projects/:project_id/w/:id" => %{
      id: "workflow_edit",
      label: "Workflow editor",
      section: "project",
      description:
        "The real-time collaborative editor for a workflow: build the DAG of triggers, jobs, and edges, write job code with adaptors and credentials, run work manually, and inspect runs — with live cursors of other editors."
    },
    "/projects/:project_id/w/:id/health" => %{
      id: "workflow_health",
      label: "Workflow health",
      section: "project",
      description:
        "A health summary for a single workflow: work order outcomes, failure patterns, and run activity over a selectable time window."
    },
    "/projects/:project_id/history" => %{
      id: "project_history",
      label: "History",
      section: "project",
      description:
        "Search and filter past work orders and runs by status, workflow, date, and dataclip content; inspect results and retry or rerun failed work in bulk."
    },
    "/projects/:project_id/history/channels" => %{
      id: "channel_logs",
      label: "Channel logs",
      section: "project",
      description:
        "The channels tab of History: a log of HTTP requests proxied through the project's channels, filterable by channel and outcome."
    },
    "/projects/:project_id/history/channels/:id" => %{
      id: "channel_request",
      label: "Channel request",
      section: "project",
      description:
        "Detail view of a single proxied channel request: request and response bodies, headers, timing, and outcome."
    },
    "/projects/:project_id/runs/:id" => %{
      id: "run_show",
      label: "Run details",
      section: "project",
      description:
        "Detail view of a single run: live logs, the steps it executed, and each step's input and output dataclips."
    },
    "/projects/:project_id/dataclips/:id/show" => %{
      id: "dataclip_show",
      label: "Dataclip",
      section: "project",
      description:
        "View the body of a single dataclip — the JSON state passed into or produced by a step."
    },
    "/projects/:project_id/channels" => %{
      id: "project_channels",
      label: "Channels",
      section: "project",
      description:
        "List and manage the project's channels — HTTP proxy configurations that forward requests from a client to a destination. Experimental feature."
    },
    "/projects/:project_id/channels/new" => %{
      id: "channel_new",
      label: "New channel",
      section: "project",
      description:
        "Form for creating a channel: configure the destination, authentication, and request persistence policy."
    },
    "/projects/:project_id/channels/:id/edit" => %{
      id: "channel_edit",
      label: "Edit channel",
      section: "project",
      description: "Form for editing an existing channel's configuration."
    },
    "/projects/:project_id/sandboxes" => %{
      id: "project_sandboxes",
      label: "Sandboxes",
      section: "project",
      description:
        "List and manage the project's sandboxes — isolated copies of the project for safe experimentation — and merge sandbox changes back into the parent."
    },
    "/projects/:project_id/sandboxes/new" => %{
      id: "sandbox_new",
      label: "New sandbox",
      section: "project",
      description:
        "Form for creating a sandbox: an isolated copy of the project with its own name, color, and environment."
    },
    "/projects/:project_id/sandboxes/:id/edit" => %{
      id: "sandbox_edit",
      label: "Edit sandbox",
      section: "project",
      description: "Form for editing a sandbox's name, color, and environment."
    },
    "/projects/:project_id/settings" => %{
      id: "project_settings",
      label: "Settings",
      section: "project",
      description:
        "Project settings, organised into tabs addressed by URL hash (e.g. #vcs): setup, credentials, collections, webhook security, collaboration, security, GitHub sync, data storage, and history exports.",
      tabs: @project_settings_tabs
    },
    "/projects/:project_id/settings/delete" => %{
      id: "project_delete",
      label: "Delete project",
      section: "project",
      description:
        "Confirmation dialog on project settings for scheduling the project for deletion."
    }
  }

  @doc """
  The authored catalog, keyed by route path pattern.

  Exposed so tests can verify it against the router in both directions.
  """
  @spec catalog() :: %{String.t() => map()}
  def catalog, do: @catalog

  @doc """
  The user-facing browser routes introspected from `LightningWeb.Router`,
  after applying the exclusions documented in the moduledoc.

  Each element is a map with `:path` (the route pattern) and `:module` (the
  LiveView or controller module).
  """
  @spec routes() :: [%{path: String.t(), module: module()}]
  def routes do
    Phoenix.Router.routes(LightningWeb.Router)
    |> Enum.filter(&(&1.verb == :get))
    |> Enum.reject(&excluded?(&1.path))
    |> Enum.map(&%{path: &1.path, module: route_module(&1)})
  end

  @doc """
  Builds the app map: every page from `routes/0` joined with its catalog
  entry, sorted by id.

  Raises if a non-excluded route has no catalog entry, so the map cannot
  silently drift from the router.
  """
  @spec build() :: [page()]
  def build do
    routes = routes()

    case Enum.reject(routes, &Map.has_key?(@catalog, &1.path)) do
      [] ->
        :ok

      missing ->
        raise """
        LightningWeb.AppMap: no catalog entry for the following route(s):

        #{Enum.map_join(missing, "\n", &"  #{&1.path} (#{inspect(&1.module)})")}

        Add an entry to the catalog in #{__ENV__.file}, or exclude the
        route there if it is not a user-facing page.
        """
    end

    routes
    |> Enum.map(fn %{path: path, module: module} ->
      @catalog
      |> Map.fetch!(path)
      |> Map.merge(%{path: path, module: inspect(module)})
    end)
    |> Enum.sort_by(& &1.id)
  end

  @doc """
  The app map as a deterministic JSON-encodable structure: a list of
  string-keyed maps sorted by id, with `tabs` present only where a page
  has sub-tabs.
  """
  @spec to_json() :: [%{String.t() => term()}]
  def to_json do
    Enum.map(build(), fn page ->
      page
      |> Map.new(fn
        {:tabs, tabs} ->
          {"tabs",
           Enum.map(tabs, &Map.new(&1, fn {k, v} -> {to_string(k), v} end))}

        {key, value} ->
          {to_string(key), value}
      end)
    end)
  end

  defp excluded?(path) do
    path in @excluded_paths or
      Enum.any?(@excluded_prefixes, fn prefix ->
        path == prefix or String.starts_with?(path, prefix <> "/")
      end)
  end

  defp route_module(%{
         metadata: %{phoenix_live_view: {module, _action, _opts, _meta}}
       }),
       do: module

  defp route_module(%{plug: plug}), do: plug
end
