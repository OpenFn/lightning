defmodule LightningWeb.ConnCase do
  @moduledoc """
  This module defines the test case to be used by
  tests that require setting up a connection.

  Such tests rely on `Phoenix.ConnTest` and also
  import other functionality to make it easier
  to build common data structures and query the data layer.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use LightningWeb.ConnCase, async: true`, although
  this option is not recommended for other databases.
  """
  use ExUnit.CaseTemplate

  using do
    quote do
      # The default endpoint for testing
      @endpoint LightningWeb.Endpoint

      use LightningWeb, :verified_routes

      # Import conveniences for testing with connections
      import Plug.Conn
      import Phoenix.ConnTest, only: :functions
      import Bureaucrat.Helpers
      import Bureaucrat.Macros
      import LightningWeb.ConnCase
      import LightningWeb.ConnHelpers

      alias Ecto.Changeset
      alias LightningWeb.Router.Helpers, as: Routes
      alias Lightning.Repo

      import Lightning.LiveViewHelpers
      import Lightning.ModelHelpers
      import Plug.HTML

      setup :stub_usage_limiter_ok
    end
  end

  setup tags do
    Mox.stub_with(Lightning.MockConfig, Lightning.Config.API)

    Mox.stub_with(LightningMock, Lightning.API)

    # Default to Hackney adapter so that Bypass dependent tests continue working
    Mox.stub_with(Lightning.Tesla.Mock, Tesla.Adapter.Hackney)

    Mox.stub_with(
      Lightning.Extensions.MockUsageLimiter,
      Lightning.Extensions.UsageLimiter
    )

    Mox.stub_with(
      Lightning.Extensions.MockAccountHook,
      Lightning.Extensions.AccountHook
    )

    Mox.stub_with(
      Lightning.Extensions.MockCollectionHook,
      Lightning.Extensions.CollectionHook
    )

    Mox.stub_with(
      Lightning.Extensions.MockProjectHook,
      Lightning.Extensions.ProjectHook
    )

    pid =
      Ecto.Adapters.SQL.Sandbox.start_owner!(Lightning.Repo,
        shared: not tags[:async]
      )

    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)

    Map.get(tags, :create_initial_user, true)
    |> if do
      Lightning.AccountsFixtures.superuser_fixture()
    end

    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end

  @doc """
  Setup helper that registers and logs in users.

      setup :register_and_log_in_user

  It stores an updated connection and a registered user in the
  test context.

  Optionally you may provide the current user's email address by providing
  an `email` tag in the context.

      @tag email: "my@user.com"
  """
  def register_and_log_in_user(%{conn: conn} = tags) do
    attrs = Map.take(tags, [:email])
    user = Lightning.Factories.insert(:user, attrs)
    %{conn: log_in_user(conn, user), user: user}
  end

  @doc """
  Setup helper that registers and logs in a support user.

      setup :register_and_log_in_support_user

  It stores an updated connection and a support user in the
  test context.
  """
  def register_and_log_in_support_user(%{conn: conn}) do
    user = Lightning.Factories.insert(:user, support_user: true)
    %{conn: log_in_user(conn, user), user: user}
  end

  def register_and_log_in_superuser(%{conn: conn}) do
    user = Lightning.AccountsFixtures.superuser_fixture()
    %{conn: log_in_user(conn, user), user: user}
  end

  @doc """
  Setup helper that registers and logs in users for token authentication.

      setup :assign_bearer_for_api

  It stores an updated connection and a registered user in the
  test context.

  You can also specify a `login_as` tag in the context to log in as a specific user.

      @tag login_as: "superuser"
      test "..." do
        # ...
      end
  """
  def assign_bearer_for_api(%{conn: conn, login_as: "superuser"}) do
    user = Lightning.AccountsFixtures.superuser_fixture()

    token = Lightning.Accounts.generate_api_token(user)
    conn = conn |> Plug.Conn.put_req_header("authorization", "Bearer #{token}")

    %{conn: conn, user: user}
  end

  def assign_bearer_for_api(%{conn: conn}) do
    user = Lightning.AccountsFixtures.user_fixture()

    token = Lightning.Accounts.generate_api_token(user)
    conn = conn |> Plug.Conn.put_req_header("authorization", "Bearer #{token}")

    %{conn: conn, user: user}
  end

  @doc """
  Setup helper that adds the current user to a new project

      setup :register_and_login_user
      # ^ Must have a `:user` key in the context before calling
      setup :create_project_for_current_user

  It then adds the project (as `:project`) to the setup context

  The currently logged in user will be added to the project as an editor by default.
  This can be changed using `@tag role: :viewer` or `@tag role: :admin` etc
  above the test definition.
  """
  def create_project_for_current_user(%{user: user} = context) do
    project =
      Lightning.Factories.insert(:project, %{
        project_users: [
          %{user: user, role: Map.get(context, :role, :editor)}
        ]
      })

    %{project: project}
  end

  @doc """
  Setup helper that creates a user adds them as project user with a given role and logs them them in
  """
  def setup_project_users(conn, project, roles) when is_list(roles) do
    for role <- roles do
      setup_project_user(conn, project, role)
    end
  end

  def setup_project_user(conn, project, role) do
    user = Lightning.Factories.insert(:user)

    conn = setup_project_user(conn, project, user, role)

    {conn, user}
  end

  def setup_project_user(conn, project, user, role) do
    Lightning.Factories.insert(:project_user,
      user: user,
      project: project,
      role: role
    )

    log_in_user(conn, user)
  end

  @doc """
  Logs the given `user` into the `conn`.

  It returns an updated `conn`.
  """
  def log_in_user(conn, user) do
    token = Lightning.Accounts.generate_user_session_token(user)

    conn
    |> Phoenix.ConnTest.init_test_session(%{})
    |> Plug.Conn.put_session(:user_token, token)
  end

  @doc """
  """
  def build_project_user_conns(project, roles) do
    Enum.map(roles, fn role ->
      project_user =
        Lightning.Factories.insert(:project_user,
          role: role,
          project: project,
          user: Lightning.Factories.build(:user)
        )

      Phoenix.ConnTest.build_conn()
      |> log_in_user(project_user.user)
    end)
  end

  alias Lightning.Extensions.MockRateLimiter
  alias Lightning.Extensions.MockUsageLimiter

  @doc """
  Stub rate limiter for success
  """
  def stub_rate_limiter_ok(_context) do
    Mox.stub(MockRateLimiter, :limit_request, fn _conn, _ctx, _opts ->
      :ok
    end)

    :ok
  end

  @doc """
  Stub usage limiter for success
  """
  def stub_usage_limiter_ok(_context) do
    Mox.stub(MockUsageLimiter, :check_limits, fn _context ->
      :ok
    end)

    Mox.stub(MockUsageLimiter, :limit_action, fn _action, _ctx ->
      :ok
    end)

    :ok
  end
end
