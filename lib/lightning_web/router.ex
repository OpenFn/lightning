defmodule LightningWeb.Router do
  @moduledoc """
  The router for Lightning.
  """
  use LightningWeb, :router
  use Lightning.BuildMacros

  import LightningWeb.UserAuth
  import Phoenix.LiveDashboard.Router

  alias CredentialLive
  alias JobLive
  alias ProjectLive
  alias UserLive

  @root_layout Application.compile_env(
                 :lightning,
                 :root_layout,
                 {LightningWeb.Layouts, :root}
               )

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, @root_layout
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_user
    plug LightningWeb.Plugs.FirstSetup

    plug LightningWeb.Plugs.BlockRoutes, [
      {
        "/users/register",
        :allow_signup,
        "Self-signup has been disabled for this instance. Please contact the administrator."
      }
    ]
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :authenticated_api do
    plug :accepts, ["json"]
    plug LightningWeb.Plugs.ApiAuth
  end

  pipeline :authenticated_json do
    plug :accepts, ["json"]
    plug :fetch_session
    plug :protect_from_forgery
    plug :fetch_current_user
  end

  scope "/", LightningWeb do
    pipe_through [:browser]

    live "/first_setup", FirstSetupLive.Superuser, :show

    get "/users/log_out", UserSessionController, :delete
    get "/users/confirm", UserConfirmationController, :new
    post "/users/confirm", UserConfirmationController, :create
    get "/users/confirm/:token", UserConfirmationController, :edit
    post "/users/confirm/:token", UserConfirmationController, :update

    get "/authenticate/callback", OidcController, :new
    get "/authenticate/:provider", OidcController, :show
    get "/authenticate/:provider/callback", OidcController, :new

    get "/oauth/:provider/callback", OauthController, :new
  end

  ## JSON API

  scope "/api", LightningWeb, as: :api do
    pipe_through [:api]

    post "/users/register", API.RegistrationController, :create

    pipe_through [
      :authenticate_bearer,
      :require_authenticated_api_resource
    ]

    get "/provision/yaml", API.ProvisioningController, :show_yaml
    resources "/provision", API.ProvisioningController, only: [:create, :show]

    resources "/projects", API.ProjectController, only: [:index, :show] do
      resources "/credentials", API.CredentialController, only: [:index]
      resources "/workflows", API.WorkflowsController, except: [:delete]
      resources "/jobs", API.JobController, only: [:index, :show]
      resources "/work_orders", API.WorkOrdersController, only: [:index, :show]
      resources "/runs", API.RunController, only: [:index, :show]
      # resources "/logs"...
    end

    resources "/credentials", API.CredentialController,
      only: [:index, :create, :delete]

    resources "/workflows", API.WorkflowsController, only: [:index, :show]
    resources "/jobs", API.JobController, only: [:index, :show]
    resources "/work_orders", API.WorkOrdersController, only: [:index, :show]
    resources "/runs", API.RunController, only: [:index, :show]
    resources "/log_lines", API.LogLinesController, only: [:index]
  end

  ## AI Assistant JSON API (cookie-authenticated)
  scope "/api", LightningWeb, as: :api do
    pipe_through [:authenticated_json, :require_authenticated_user]

    get "/ai_assistant/sessions", API.AiAssistantController, :list_sessions
  end

  ## Collections
  scope "/collections", LightningWeb do
    pipe_through [:authenticated_api]

    get "/:name", CollectionsController, :stream
    get "/:name/:key", CollectionsController, :get
    put "/:name/:key", CollectionsController, :put
    post "/:name", CollectionsController, :put_all
    delete "/:name/:key", CollectionsController, :delete
    delete "/:name", CollectionsController, :delete_all
  end

  ## Authentication routes
  scope "/", LightningWeb do
    pipe_through [:browser, :redirect_if_user_is_authenticated]

    get "/users/register", UserRegistrationController, :new
    post "/users/register", UserRegistrationController, :create
    get "/users/token_exchange/:token", UserSessionController, :exchange_token
    get "/users/log_in", UserSessionController, :new
    post "/users/log_in", UserSessionController, :create
    get "/users/reset_password", UserResetPasswordController, :new
    post "/users/reset_password", UserResetPasswordController, :create
    get "/users/reset_password/:token", UserResetPasswordController, :edit
    put "/users/reset_password/:token", UserResetPasswordController, :update
  end

  scope "/", LightningWeb do
    pipe_through [:browser, :require_authenticated_user]

    get "/users/two-factor", UserTOTPController, :new
    post "/users/two-factor", UserTOTPController, :create
    get "/setup_vcs", VersionControlController, :index
    get "/download/yaml", DownloadsController, :download_project_yaml
    get "/dataclip/body/:id", DataclipController, :show

    get "/projects/:project_id/jobs/:job_id/dataclips",
        DataclipController,
        :search

    get "/projects/:project_id/runs/:run_id/dataclip",
        DataclipController,
        :show_for_run

    patch "/projects/:project_id/dataclips/:dataclip_id",
          DataclipController,
          :update_name

    post "/projects/:project_id/workflows/:workflow_id/runs",
         WorkflowController,
         :create_run

    get "/projects/:project_id/runs/:run_id/steps",
        WorkflowController,
        :get_run_steps

    post "/projects/:project_id/runs/:run_id/retry",
         WorkflowController,
         :retry_run

    get "/project_files/:id/download", ProjectFileController, :download

    get "/profile/confirm_email/:token",
        UserConfirmationController,
        :confirm_email

    get "/users/send-confirmation-email", UserConfirmationController, :send_email

    get "/credentials/transfer/:credential_id/:receiver_id/:token",
        CredentialTransferController,
        :confirm

    live_session :auth, on_mount: LightningWeb.InitAssigns do
      live "/auth/confirm_access", ReAuthenticateLive.New, :new
    end

    scope "/" do
      pipe_through [
        :reauth_sudo_mode,
        :require_sudo_user
      ]

      live_session :sudo_auth,
        on_mount: [
          {LightningWeb.InitAssigns, :default},
          {LightningWeb.UserAuth, :ensure_sudo}
        ] do
        live "/profile/auth/backup_codes", BackupCodesLive.Index, :index
        get "/profile/auth/backup_codes/print", BackupCodesController, :print
      end
    end

    live_session :settings, on_mount: LightningWeb.InitAssigns do
      live "/settings", SettingsLive.Index, :index

      live "/settings/users/new", UserLive.Edit, :new
      live "/settings/users/:id", UserLive.Edit, :edit
      live "/settings/users/:id/delete", UserLive.Index, :delete

      live "/settings/projects", ProjectLive.Index, :index
      live "/settings/projects/new", ProjectLive.Index, :new
      live "/settings/projects/:id", ProjectLive.Index, :edit
      live "/settings/projects/:id/delete", ProjectLive.Index, :delete

      live "/settings/audit", AuditLive.Index, :index

      live "/settings/authentication", AuthProvidersLive.Index, :edit
      live "/settings/authentication/new", AuthProvidersLive.Index, :new

      live "/settings/collections", CollectionLive.Index, :index
    end

    live_session :default, on_mount: LightningWeb.InitAssigns do
      live "/mfa_required", ProjectLive.MFARequired, :index

      scope "/projects/:project_id", as: :project do
        live "/jobs", JobLive.Index, :index

        live "/settings/delete", ProjectLive.Settings, :delete

        live "/history", RunLive.Index, :index
        live "/runs/:id", RunLive.Show, :show

        live "/dataclips/:id/show", DataclipLive.Show, :show

        live "/w", WorkflowLive.Index, :index
        live "/w/new/legacy", WorkflowLive.Edit, :new
        live "/w/new", WorkflowLive.Collaborate, :new
        live "/w/:id/legacy", WorkflowLive.Edit, :edit
        live "/w/:id", WorkflowLive.Collaborate, :edit

        live "/channels", ChannelLive.Index, :index
        live "/channels/new", ChannelLive.Index, :new
        live "/channels/:id/edit", ChannelLive.Index, :edit

        live "/sandboxes", SandboxLive.Index, :index
        live "/sandboxes/new", SandboxLive.Index, :new
        live "/sandboxes/:id/edit", SandboxLive.Index, :edit
      end

      live "/credentials", CredentialLive.Index, :index

      live "/profile/:id/delete", ProfileLive.Edit, :delete

      live "/profile/tokens", TokensLive.Index, :index
      live "/profile/tokens/:id/delete", TokensLive.Index, :delete

      get "/", Plugs.Redirect, to: "/projects"
    end
  end

  scope "/i", LightningWeb do
    pipe_through :api

    post "/*path", WebhooksController, :create
    get "/*path", WebhooksController, :check
  end

  scope "/" do
    @routing_config Application.compile_env(
                      :lightning,
                      Lightning.Extensions.Routing,
                      []
                    )
    @services_opts @routing_config |> Keyword.get(:session_opts, [])
    @services_routes @routing_config |> Keyword.get(:routes, [])

    pipe_through [:browser, :require_authenticated_user]

    live_session :services, @services_opts do
      Enum.each(@services_routes, fn {path, module, action, opts} ->
        live(path, module, action, opts)
      end)
    end
  end

  # LiveDashboard enables basic system monitoring but is only available to
  # superusers—i.e., the people who installed/maintain the instance.
  scope "/" do
    pipe_through [:browser, :require_authenticated_user, :require_superuser]

    live_dashboard "/dashboard", metrics: LightningWeb.Telemetry
  end

  do_in(:dev) do
    import PhoenixStorybook.Router

    scope "/" do
      storybook_assets()
    end

    scope "/" do
      pipe_through :browser

      live_storybook("/storybook", backend_module: LightningWeb.Storybook)
    end

    scope "/dev" do
      pipe_through :browser

      forward "/mailbox", Plug.Swoosh.MailboxPreview

      live "/components", LightningWeb.Dev.ComponentsLive, :index
      live "/react", LightningWeb.Dev.ReactLive, :index
    end
  end

  forward "/health_check", LightningWeb.HealthCheck
end

defmodule LightningWeb.HealthCheck do
  use Plug.Router

  plug :match
  plug :dispatch

  get "/" do
    send_resp(conn, 200, "Hello you!")
  end
end
