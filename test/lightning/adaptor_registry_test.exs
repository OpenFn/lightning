defmodule Lightning.AdaptorRegistryTest do
  use Lightning.DataCase, async: false

  import Mox
  import Tesla.Test

  setup :set_mox_from_context
  setup :verify_on_exit!

  alias Lightning.AdaptorRegistry

  describe "start_link/1 in non-local mode" do
    test "reads from DB/ETS cache when data is seeded" do
      # Seed DB with adaptor data
      adaptors = [
        %{
          name: "@openfn/language-dhis2",
          repo: "git+https://github.com/openfn/language-dhis2.git",
          latest: "3.0.5",
          versions: []
        }
      ]

      Lightning.AdaptorData.put("registry", "all", Jason.encode!(adaptors))
      Lightning.AdaptorData.Cache.invalidate("registry")

      start_supervised!(
        {AdaptorRegistry, [name: :test_adaptor_registry, use_cache: false]}
      )

      results = AdaptorRegistry.all(:test_adaptor_registry)
      assert length(results) == 1

      assert %{name: "@openfn/language-dhis2", latest: "3.0.5"} =
               hd(results)
    end

    test "returns empty list when DB has no data" do
      Lightning.AdaptorData.Cache.invalidate("registry")

      start_supervised!(
        {AdaptorRegistry, [name: :test_empty_registry, use_cache: false]}
      )

      results = AdaptorRegistry.all(:test_empty_registry)
      assert results == []
    end

    test "versions_for reads from cache" do
      adaptors = [
        %{
          name: "@openfn/language-common",
          repo: "git+https://github.com/OpenFn/language-common.git",
          latest: "1.6.2",
          versions: [%{version: "1.5.0"}, %{version: "1.6.2"}]
        }
      ]

      Lightning.AdaptorData.put("registry", "all", Jason.encode!(adaptors))
      Lightning.AdaptorData.Cache.invalidate("registry")

      start_supervised!(
        {AdaptorRegistry, [name: :test_versions_registry, use_cache: false]}
      )

      assert [%{version: "1.5.0"}, %{version: "1.6.2"}] =
               AdaptorRegistry.versions_for(
                 :test_versions_registry,
                 "@openfn/language-common"
               )

      assert AdaptorRegistry.versions_for(
               :test_versions_registry,
               "@openfn/language-foobar"
             ) == nil
    end

    test "latest_for reads from cache" do
      adaptors = [
        %{
          name: "@openfn/language-common",
          repo: "git+https://github.com/OpenFn/language-common.git",
          latest: "1.6.2",
          versions: []
        }
      ]

      Lightning.AdaptorData.put("registry", "all", Jason.encode!(adaptors))
      Lightning.AdaptorData.Cache.invalidate("registry")

      start_supervised!(
        {AdaptorRegistry, [name: :test_latest_registry, use_cache: false]}
      )

      assert "1.6.2" =
               AdaptorRegistry.latest_for(
                 :test_latest_registry,
                 "@openfn/language-common"
               )

      assert AdaptorRegistry.latest_for(
               :test_latest_registry,
               "@openfn/language-foobar"
             ) == nil
    end
  end

  describe "start_link/1 in local mode" do
    @tag :tmp_dir
    test "lists directory names when local_adaptors_repo is set", %{
      tmp_dir: tmp_dir,
      test: test
    } do
      expected_adaptors = ["foo", "bar", "baz"]

      Enum.each(expected_adaptors, fn adaptor ->
        [tmp_dir, "packages", adaptor] |> Path.join() |> File.mkdir_p!()
      end)

      start_supervised!(
        {AdaptorRegistry, [name: test, local_adaptors_repo: tmp_dir]}
      )

      results = AdaptorRegistry.all(test)

      for adaptor <- expected_adaptors do
        expected_result = %{
          name: "@openfn/language-#{adaptor}",
          repo: "file://" <> Path.join([tmp_dir, "packages", adaptor]),
          latest: "local",
          versions: []
        }

        assert expected_result in results
      end
    end
  end

  describe "refresh_sync/1" do
    test "fetches from NPM and writes to DB cache" do
      default_npm_response =
        File.read!("test/fixtures/language-common-npm.json") |> Jason.decode!()

      expect_tesla_call(
        times: 7,
        returns: fn env, [] ->
          case env.url do
            "https://registry.npmjs.org/-/user/openfn/package" ->
              {:ok,
               json(
                 %Tesla.Env{status: 200},
                 File.read!("test/fixtures/openfn-packages-npm.json")
                 |> Jason.decode!()
               )}

            "https://registry.npmjs.org/@openfn/" <> _adaptor ->
              {:ok, json(%Tesla.Env{status: 200}, default_npm_response)}
          end
        end
      )

      Lightning.AdaptorData.Cache.invalidate("registry")

      start_supervised!(
        {AdaptorRegistry, [name: :test_refresh_registry, use_cache: false]}
      )

      assert {:ok, 6} = AdaptorRegistry.refresh_sync(:test_refresh_registry)

      # After refresh, data should be readable from cache
      Lightning.AdaptorData.Cache.invalidate("registry")
      assert length(AdaptorRegistry.all(:test_refresh_registry)) == 6
    end

    test "returns error when NPM returns empty results" do
      # Mock npm to return empty package list (simulates offline)
      expect_tesla_call(
        times: 1,
        returns: fn _env, [] ->
          {:ok, json(%Tesla.Env{status: 200}, %{})}
        end
      )

      start_supervised!(
        {AdaptorRegistry, [name: :test_empty_refresh, use_cache: false]}
      )

      assert {:error, :empty_results} =
               AdaptorRegistry.refresh_sync(:test_empty_refresh)
    end

    @tag :tmp_dir
    test "is a no-op in local mode", %{tmp_dir: tmp_dir, test: test} do
      [tmp_dir, "packages", "foo"] |> Path.join() |> File.mkdir_p!()

      start_supervised!(
        {AdaptorRegistry, [name: test, local_adaptors_repo: tmp_dir]}
      )

      assert {:ok, :local_mode} = AdaptorRegistry.refresh_sync(test)
    end
  end

  describe "resolve_package_name/1" do
    test "it can split an NPM style package name" do
      assert AdaptorRegistry.resolve_package_name("@openfn/language-foo@1.2.3") ==
               {"@openfn/language-foo", "1.2.3"}

      assert AdaptorRegistry.resolve_package_name(
               "@openfn/language-foo@1.2.3-pre"
             ) ==
               {"@openfn/language-foo", "1.2.3-pre"}

      assert AdaptorRegistry.resolve_package_name("@openfn/language-foo") ==
               {"@openfn/language-foo", nil}

      assert AdaptorRegistry.resolve_package_name("") ==
               {nil, nil}
    end

    @tag :tmp_dir
    test "returns local as the version when local_adaptors_repo config is set",
         %{tmp_dir: tmp_dir} do
      Mox.stub(Lightning.MockConfig, :adaptor_registry, fn ->
        [local_adaptors_repo: tmp_dir]
      end)

      assert AdaptorRegistry.resolve_package_name("@openfn/language-foo@1.2.3") ==
               {"@openfn/language-foo", "local"}

      assert AdaptorRegistry.resolve_package_name("@openfn/language-foo") ==
               {"@openfn/language-foo", "local"}

      assert AdaptorRegistry.resolve_package_name("") ==
               {nil, nil}
    end
  end
end
