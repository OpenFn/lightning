defmodule Lightning.AdaptorRegistrySeed do
  @moduledoc """
  Seeds the Cachex adaptor registry with a minimal fixture so
  `AdaptorRegistry.all/0` does not fall through to a DB query from the
  GenServer process (which would fail sandbox ownership checks in async
  tests).

  Used by `ConnCase`, `DataCase`, and `ChannelCase`.
  """

  @registry [
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
  ]

  @spec seed() :: :ok
  def seed do
    Lightning.AdaptorData.Cache.put(
      "registry",
      "all",
      %{data: Jason.encode!(@registry), content_type: "application/json"}
    )

    :ok
  end
end
