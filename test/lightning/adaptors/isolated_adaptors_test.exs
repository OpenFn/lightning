defmodule Lightning.Adaptors.IsolatedAdaptorsTest do
  @moduledoc """
  `Lightning.AdaptorTestHelpers.isolated_adaptors/1` gives a test its own
  `Lightning.Adaptors.Supervisor` instance and makes it the default one,
  for the test process and its descendants.
  """

  use Lightning.DataCase, async: true

  import Lightning.AdaptorTestHelpers

  alias Lightning.Adaptors
  alias Lightning.Adaptors.Config
  alias Lightning.Adaptors.Supervisor, as: AdaptorsSupervisor

  describe "isolated" do
    setup :isolated_adaptors

    test "the default instance is the isolated one for this test and its descendants",
         %{sup: sup} do
      assert Config.default_instance() == sup

      assert Task.async(fn -> Config.default_instance() end) |> Task.await() ==
               sup

      source = AdaptorsSupervisor.source(sup)

      fake_meta = %{
        name: "@openfn/language-isolated-fixture",
        latest_version: "1.2.3",
        description: nil,
        deprecated: false,
        icon_square_ext: nil,
        icon_rectangle_ext: nil,
        icon_square_sha256: nil,
        icon_rectangle_sha256: nil
      }

      Cachex.put(
        AdaptorsSupervisor.cache_name(sup),
        {:packages, source},
        {:ok, [fake_meta]}
      )

      assert {:ok,
              [%Adaptors.Package{name: "@openfn/language-isolated-fixture"}]} =
               Adaptors.packages()
    end

    test "seed_credential_schema writes into the isolated cache", %{sup: sup} do
      other_sup =
        :"isolated_adaptors_other_#{System.unique_integer([:positive])}"

      ExUnit.Callbacks.start_supervised!(
        Supervisor.child_spec(
          {AdaptorsSupervisor,
           name: other_sup, strategy: Lightning.Adaptors.StrategyMock},
          id: other_sup
        )
      )

      seed_credential_schema("http")

      source = AdaptorsSupervisor.source(sup)

      assert Cachex.get(
               AdaptorsSupervisor.cache_name(sup),
               {:schema, "http", source}
             ) !=
               {:ok, nil}

      assert Cachex.get(
               AdaptorsSupervisor.cache_name(other_sup),
               {:schema, "http", source}
             ) == {:ok, nil}
    end
  end

  describe "not isolated" do
    test "ensure_adaptor raises without an isolated instance" do
      assert_raise RuntimeError, ~r/setup :isolated_adaptors/, fn ->
        ensure_adaptor("@openfn/language-common")
      end
    end
  end
end
