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

      use Oban.Testing, repo: Lightning.Repo
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

    pid =
      Ecto.Adapters.SQL.Sandbox.start_owner!(Lightning.Repo,
        shared: not tags[:async]
      )

    # Seed ETS cache with minimal adaptor registry so AdaptorRegistry.all()
    # never falls through to DB from the GenServer (sandbox ownership issue).
    registry_json =
      Jason.encode!([
        %{
          name: "@openfn/language-common",
          repo: "",
          latest: "1.6.2",
          versions: [
            %{version: "1.6.2"},
            %{version: "1.5.0"},
            %{version: "1.0.0"}
          ]
        },
        %{
          name: "@openfn/language-http",
          repo: "",
          latest: "7.2.0",
          versions: [
            %{version: "7.2.0"},
            %{version: "2.0.0"},
            %{version: "1.0.0"}
          ]
        },
        %{
          name: "@openfn/language-dhis2",
          repo: "",
          latest: "3.0.4",
          versions: [%{version: "3.0.4"}, %{version: "3.0.0"}]
        },
        %{
          name: "@openfn/language-salesforce",
          repo: "",
          latest: "4.0.0",
          versions: [%{version: "4.0.0"}]
        }
      ])

    Lightning.AdaptorData.Cache.put(
      "registry",
      "all",
      %{data: registry_json, content_type: "application/json"}
    )

    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
    :ok
  end
end
