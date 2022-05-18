defmodule LightningWeb.Router do
  use LightningWeb, :router

  import LightningWeb.UserAuth
  alias JobLive
  alias CredentialLive
  alias UserLive

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, {LightningWeb.LayoutView, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_user
    plug LightningWeb.Plugs.FirstSetup
  end

  pipeline :api do
    plug(:accepts, ["json"])
  end

  scope "/", LightningWeb do
    pipe_through [:browser]

    live("/first_setup", FirstSetupLive.Superuser, :show)

    get "/users/log_out", UserSessionController, :delete
    get "/users/confirm", UserConfirmationController, :new
    post "/users/confirm", UserConfirmationController, :create
    get "/users/confirm/:token", UserConfirmationController, :edit
    post "/users/confirm/:token", UserConfirmationController, :update
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

    get "/profile", UserSettingsController, :edit
    put "/profile", UserSettingsController, :update
    get "/profile/confirm_email/:token", UserSettingsController, :confirm_email

    live_session :settings, on_mount: LightningWeb.InitAssigns do
      live "/settings", SettingsLive.Index, :index

      live "/settings/users", UserLive.Index, :index
      live "/settings/users/new", UserLive.Index, :new

      live "/settings/users/:id", UserLive.Show, :show
      live "/settings/users/:id/edit", UserLive.Edit, :edit

      live "/settings/projects", ProjectLive.Index, :index
      live "/settings/projects/new", ProjectLive.Index, :new
      live "/settings/projects/:id", ProjectLive.Index, :edit
    end

    live_session :default, on_mount: LightningWeb.InitAssigns do
      live("/jobs", JobLive.Index, :index)
      live("/jobs/new", JobLive.Index, :new)
      # live "/jobs/:id/edit", JobLive.Index, :edit

      live("/jobs/:id", JobLive.Show, :show)
      live("/jobs/:id/edit", JobLive.Edit, :edit)
      # live "/jobs/:id/show/edit", JobLive.Show, :edit

      live("/credentials", CredentialLive.Index, :index)
      live("/credentials/new", CredentialLive.Index, :new)

      live("/credentials/:id", CredentialLive.Show, :show)
      live("/credentials/:id/edit", CredentialLive.Edit, :edit)

      live("/dataclips", DataclipLive.Index, :index)
      live("/dataclips/new", DataclipLive.Index, :new)
      live("/dataclips/:id/edit", DataclipLive.Index, :edit)

      live("/dataclips/:id", DataclipLive.Show, :show)
      live("/dataclips/:id/show/edit", DataclipLive.Show, :edit)

      live("/runs", RunLive.Index, :index)
      live("/runs/new", RunLive.Index, :new)
      live("/runs/:id/edit", RunLive.Index, :edit)

      live("/runs/:id", RunLive.Show, :show)
      live("/runs/:id/show/edit", RunLive.Show, :edit)

      live("/", DashboardLive.Index, :index)
    end
  end

  scope "/i", LightningWeb do
    pipe_through(:api)

    post("/*path", WebhooksController, :create)
  end

  # Other scopes may use custom stacks.
  # scope "/api", LightningWeb do
  #   pipe_through :api
  # end

  # Enables LiveDashboard only for development
  #
  # If you want to use the LiveDashboard in production, you should put
  # it behind authentication and allow only admins to access it.
  # If your application does not have an admins-only section yet,
  # you can use Plug.BasicAuth to set up some basic authentication
  # as long as you are also using SSL (which you should anyway).
  if Mix.env() in [:dev, :test] do
    import Phoenix.LiveDashboard.Router

    scope "/" do
      pipe_through(:browser)

      live_dashboard("/dashboard", metrics: LightningWeb.Telemetry)
    end
  end

  # Enables the Swoosh mailbox preview in development.
  #
  # Note that preview only shows emails that were sent by the same
  # node running the Phoenix server.
  if Mix.env() == :dev do
    scope "/dev" do
      pipe_through(:browser)

      forward("/mailbox", Plug.Swoosh.MailboxPreview)
    end
  end
end
