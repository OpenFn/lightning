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
      import Phoenix.ConnTest
      import LightningWeb.ConnCase

      alias LightningWeb.Router.Helpers, as: Routes

      import Lightning.ModelHelpers
      import Plug.HTML
    end
  end

  setup tags do
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
  """
  def register_and_log_in_user(%{conn: conn}) do
    user = Lightning.AccountsFixtures.user_fixture()
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
  """
  def create_project_for_current_user(%{user: user}) do
    project =
      Lightning.ProjectsFixtures.project_fixture(
        project_users: [%{user_id: user.id}]
      )

    %{project: project}
  end

  @doc """
  Setup helper that creates a user adds them as project user with a given role and logs them them in
  """
  def setup_project_user(conn, project, role) do
    user = Lightning.AccountsFixtures.user_fixture()

    conn = setup_project_user(conn, project, user, role)

    {conn, user}
  end

  def setup_project_user(conn, project, user, role) do
    project_users =
      project.project_users
      |> Enum.concat([
        %Lightning.Projects.ProjectUser{user_id: user.id, role: role}
      ])

    {:ok, _project} =
      Lightning.Projects.Project.changeset(project, %{})
      |> Ecto.Changeset.put_assoc(:project_users, project_users)
      |> Lightning.Repo.update()

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
end
