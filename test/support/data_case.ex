defmodule Lightning.DataCase do
  @moduledoc """
  This module defines the setup for tests requiring
  access to the application's data layer.

  You may define functions here to be used as helpers in
  your tests.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use Lightning.DataCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      alias Lightning.Repo

      import Ecto
      import Ecto.Changeset
      import Ecto.Query

      import Lightning.Factories
      import Lightning.ModelHelpers

      import Lightning.DataCase
      import Lightning.AuditHelpers

      use Oban.Testing, repo: Lightning.Repo
    end
  end

  setup tags do
    # Default to Hackney adapter so that Bypass dependent tests continue working
    Mox.stub_with(Lightning.Tesla.Mock, Tesla.Adapter.Hackney)

    # pid =
    #   Ecto.Adapters.SQL.Sandbox.start_owner!(Lightning.Repo,
    #     shared: not tags[:async]
    #   )

    # on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)

    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Lightning.Repo)

    unless tags[:async] do
      Ecto.Adapters.SQL.Sandbox.mode(Lightning.Repo, {:shared, self()})
    end

    :ok
  end
end
