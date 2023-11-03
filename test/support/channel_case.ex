defmodule LightningWeb.ChannelCase do
  @moduledoc """
  This module defines the test case to be used by
  channel tests.

  Such tests rely on `Phoenix.ChannelTest` and also
  import other functionality to make it easier
  to build common data structures and query the data layer.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use LightningWeb.ChannelCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      # Import conveniences for testing with channels
      import Phoenix.ChannelTest
      import LightningWeb.ChannelCase

      import Mox

      alias Lightning.Repo

      # The default endpoint for testing
      @endpoint LightningWeb.Endpoint
    end
  end

  setup tags do
    # Mox.stub_with(Lightning.Config.Mock, Lightning.Config.Stub)
    # Application.put_env(:lightning, Lightning.Config, Lightning.Config.Mock)
    Mox.stub_with(Lightning.Mock, Lightning.Stub)
    # Application.put_env(:lightning, Lightning, Lightning.Mock)

    pid =
      Ecto.Adapters.SQL.Sandbox.start_owner!(Lightning.Repo,
        shared: not tags[:async]
      )

    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
    :ok
  end
end
