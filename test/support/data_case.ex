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
      import Lightning.TestUtils

      import Lightning.DataCase

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

    # Seed the Cachex cache directly with minimal adaptor registry data so
    # AdaptorRegistry.all() never falls through to a DB query from the
    # GenServer process (which would fail sandbox ownership checks in async tests).
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
  end
end
