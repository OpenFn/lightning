defmodule LightningWeb.Router do
  use LightningWeb, :router

  import LightningWeb.UserAuth
  import Phoenix.LiveDashboard.Router

  alias ProjectLive
  alias JobLive
  alias CredentialLive
  alias UserLive

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, {LightningWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_user
    plug LightningWeb.Plugs.FirstSetup
  end

  pipeline :api do
    plug :accepts, ["json"]
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
  end

  ## JSON API

  scope "/api", LightningWeb, as: :api do
    pipe_through [
      :api,
      :authenticate_bearer,
      :require_authenticated_user
    ]

    get "/provision/yaml", API.ProvisioningController, :show_yaml
    resources "/provision", API.ProvisioningController, only: [:create, :show]

    resources "/projects", API.ProjectController, only: [:index, :show] do
      resources "/jobs", API.JobController, only: [:index, :show]
      resources "/runs", API.RunController, only: [:index, :show]
    end

    resources "/jobs", API.JobController, only: [:index, :show]
    resources "/runs", API.RunController, only: [:index, :show]
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

    get "/profile/confirm_email/:token",
        UserConfirmationController,
        :confirm_email

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

      live "/settings/users", UserLive.Index, :index
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
    end

    live_session :default, on_mount: LightningWeb.InitAssigns do
      live "/mfa_required", ProjectLive.MFARequired, :index

      scope "/projects/:project_id", as: :project do
        live "/jobs", JobLive.Index, :index

        live "/settings", ProjectLive.Settings, :index
        live "/settings/delete", ProjectLive.Settings, :delete

        live "/runs", RunLive.Index, :index
        live "/runs/:id", RunLive.Show, :show

        live "/attempts/:id", AttemptLive.Show, :show

        live "/dataclips", DataclipLive.Index, :index
        live "/dataclips/new", DataclipLive.Edit, :new
        live "/dataclips/:id/edit", DataclipLive.Edit, :edit

        live "/w", WorkflowLive.Index, :index
        live "/w/new", WorkflowLive.Edit, :new
        live "/w/:id", WorkflowLive.Edit, :edit
      end

      live "/credentials", CredentialLive.Index, :index
      live "/credentials/:id/delete", CredentialLive.Index, :delete
      live "/credentials/new", CredentialLive.Edit, :new
      live "/credentials/:id", CredentialLive.Edit, :edit

      live "/profile", ProfileLive.Edit, :edit
      live "/profile/:id/delete", ProfileLive.Edit, :delete

      live "/profile/tokens", TokensLive.Index, :index
      live "/profile/tokens/:id/delete", TokensLive.Index, :delete

      live "/", DashboardLive.Index, :index
    end
  end

  scope "/i", LightningWeb do
    pipe_through :api

    post "/*path", WebhooksController, :create
  end

  # Other scopes may use custom stacks.
  # scope "/api", LightningWeb do
  #   pipe_through :api
  # end

  # Enables the Swoosh mailbox preview and LiveDashboard in development.
  #
  # Note that preview only shows emails that were sent by the same
  # node running the Phoenix server.
  #

  # LiveDashboard enables basic system monitoring but is only available to
  # superusers—i.e., the people who installed/maintain the instance.
  scope "/" do
    pipe_through [:browser, :require_authenticated_user, :require_superuser]

    live_dashboard "/dashboard", metrics: LightningWeb.Telemetry
  end

  if Mix.env() == :dev do
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
