defmodule LightningWeb.Router do
  use LightningWeb, :router

  import LightningWeb.UserAuth
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

    get "/profile/confirm_email/:token",
        UserConfirmationController,
        :confirm_email

    live_session :settings, on_mount: LightningWeb.InitAssigns do
      live "/settings", SettingsLive.Index, :index

      live "/settings/users", UserLive.Index, :index
      live "/settings/users/new", UserLive.Edit, :new
      live "/settings/users/:id", UserLive.Edit, :edit
      live "/settings/users/:id/delete", UserLive.Index, :delete

      live "/settings/projects", ProjectLive.Index, :index
      live "/settings/projects/new", ProjectLive.Index, :new
      live "/settings/projects/:id", ProjectLive.Index, :edit

      live "/settings/audit", AuditLive.Index, :index

      live "/settings/authentication", AuthProvidersLive.Index, :edit
      live "/settings/authentication/new", AuthProvidersLive.Index, :new

      live "/settings/tokens", TokensLive.Index, :index
      live "/settings/tokens/new", TokensLive.Edit, :new
      live "/settings/tokens/:id", TokensLive.Edit, :edit
    end

    live_session :default, on_mount: LightningWeb.InitAssigns do
      scope "/projects/:project_id", as: :project do
        live "/jobs", JobLive.Index, :index

        live "/settings", ProjectLive.Settings, :index

        live "/runs", RunLive.Index, :index
        live "/runs/:id", RunLive.Show, :show

        live "/dataclips", DataclipLive.Index, :index
        live "/dataclips/new", DataclipLive.Edit, :new
        live "/dataclips/:id/edit", DataclipLive.Edit, :edit

        live "/w/:workflow_id/j/new", WorkflowLive, :new_job
        live "/w/:workflow_id/j/:job_id", WorkflowLive, :edit_job
        live "/w/:workflow_id/edit", WorkflowLive, :edit_workflow
        live "/w/:workflow_id", WorkflowLive, :show
        live "/w", WorkflowLive, :index
      end

      live "/credentials", CredentialLive.Index, :index
      live "/credentials/new", CredentialLive.Edit, :new
      live "/credentials/:id", CredentialLive.Edit, :edit

      live "/profile", ProfileLive.Edit, :edit
      live "/profile/:id/delete", ProfileLive.Edit, :delete

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
  # If you want to use the LiveDashboard in production, you should put
  # it behind authentication and allow only admins to access it.
  # If your application does not have an admins-only section yet,
  # you can use Plug.BasicAuth to set up some basic authentication
  # as long as you are also using SSL (which you should anyway).
  if Mix.env() in [:dev, :test] do
    import Phoenix.LiveDashboard.Router

    scope "/" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: LightningWeb.Telemetry
    end
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
