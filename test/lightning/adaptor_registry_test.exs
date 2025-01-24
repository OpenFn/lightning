defmodule Lightning.AdaptorRegistryTest do
  use Lightning.DataCase, async: false

  import Mox
  import Tesla.Test

  setup :set_mox_from_context
  setup :verify_on_exit!

  alias Lightning.AdaptorRegistry

  describe "start_link/1" do
    test "uses cache from a specific location" do
      file_path =
        Briefly.create!(extname: ".json")
        |> tap(fn path ->
          File.write!(path, ~S"""
          [{
            "latest": "3.0.5",
            "name": "@openfn/language-dhis2",
            "repo": "git+https://github.com/openfn/language-dhis2.git",
            "versions": []
          }]
          """)
        end)

      start_supervised!(
        {AdaptorRegistry, [name: :test_adaptor_registry, use_cache: file_path]}
      )

      results = AdaptorRegistry.all(:test_adaptor_registry)
      assert length(results) == 1
    end

    test "retrieves a list of adaptors when caching is disabled" do
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

      expected_adaptors = [
        "@openfn/language-asana",
        "@openfn/language-common",
        "@openfn/language-commcare",
        "@openfn/language-dhis2",
        "@openfn/language-http",
        "@openfn/language-salesforce"
      ]

      start_supervised!(
        {AdaptorRegistry, [name: :test_adaptor_registry, use_cache: false]}
      )

      results = AdaptorRegistry.all(:test_adaptor_registry)

      assert_received_tesla_call(env, [])

      assert_tesla_env(env, %Tesla.Env{
        method: :get,
        url: "https://registry.npmjs.org/-/user/openfn/package"
      })

      1..length(expected_adaptors)
      |> Enum.each(fn _ ->
        assert_received_tesla_call(env, [])

        assert %Tesla.Env{
                 method: :get,
                 url: "https://registry.npmjs.org/" <> adaptor
               } = env

        assert adaptor in expected_adaptors
      end)

      assert length(results) == 6

      versions = [
        %{version: "1.1.0"},
        %{version: "1.1.1"},
        %{version: "1.2.0"},
        %{version: "1.2.1"},
        %{version: "1.2.2"},
        %{version: "1.2.4"},
        %{version: "1.2.5"},
        %{version: "1.2.6"},
        %{version: "1.2.7"},
        %{version: "1.2.8"},
        %{version: "1.4.0"},
        %{version: "1.4.1"},
        %{version: "1.4.2"},
        %{version: "1.5.0"},
        %{version: "1.6.0"},
        %{version: "1.6.1"},
        %{version: "1.6.2"}
      ]

      assert %{
               name: "@openfn/language-common",
               repo: "git+https://github.com/OpenFn/language-common.git",
               latest: "1.6.2",
               versions: versions
             } in results

      assert AdaptorRegistry.versions_for(
               :test_adaptor_registry,
               "@openfn/language-common"
             ) ==
               versions

      assert AdaptorRegistry.versions_for(
               :test_adaptor_registry,
               "@openfn/language-foobar"
             ) ==
               nil
    end

    @tag :tmp_dir
    test "lists directory names of the when local_adaptors_repo is set", %{
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
