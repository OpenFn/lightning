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
    test "lists directory names from a single-element local_adaptors_repos list",
         %{tmp_dir: tmp_dir, test: test} do
      expected_adaptors = ["foo", "bar", "baz"]

      Enum.each(expected_adaptors, fn adaptor ->
        [tmp_dir, "packages", adaptor] |> Path.join() |> File.mkdir_p!()
      end)

      start_supervised!(
        {AdaptorRegistry, [name: test, local_adaptors_repos: [tmp_dir]]}
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

    @tag :tmp_dir
    test "merges adaptors from multiple local_adaptors_repos", %{
      tmp_dir: tmp_dir,
      test: test
    } do
      repo_a = Path.join(tmp_dir, "a")
      repo_b = Path.join(tmp_dir, "b")
      [repo_a, "packages", "alpha"] |> Path.join() |> File.mkdir_p!()
      [repo_b, "packages", "beta"] |> Path.join() |> File.mkdir_p!()

      start_supervised!(
        {AdaptorRegistry, [name: test, local_adaptors_repos: [repo_a, repo_b]]}
      )

      names = AdaptorRegistry.all(test) |> Enum.map(& &1.name) |> Enum.sort()

      assert names == ["@openfn/language-alpha", "@openfn/language-beta"]
    end

    @tag :tmp_dir
    test "first repo wins on collision and emits a warning", %{
      tmp_dir: tmp_dir,
      test: test
    } do
      repo_a = Path.join(tmp_dir, "a")
      repo_b = Path.join(tmp_dir, "b")
      [repo_a, "packages", "http"] |> Path.join() |> File.mkdir_p!()
      [repo_b, "packages", "http"] |> Path.join() |> File.mkdir_p!()

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          start_supervised!(
            {AdaptorRegistry,
             [name: test, local_adaptors_repos: [repo_a, repo_b]]}
          )

          # force the GenServer to finish handle_continue
          AdaptorRegistry.all(test)
        end)

      results = AdaptorRegistry.all(test)
      assert length(results) == 1

      assert hd(results).repo ==
               "file://" <> Path.join([repo_a, "packages", "http"])

      assert log =~ "@openfn/language-http"
      assert log =~ "shadowed"

      assert log =~ "using"
      assert log =~ "file://" <> Path.join([repo_a, "packages", "http"])
      assert log =~ "file://" <> Path.join([repo_b, "packages", "http"])
    end

    @tag :tmp_dir
    test "soft-fails when a repo path is missing or unreadable", %{
      tmp_dir: tmp_dir,
      test: test
    } do
      good_repo = Path.join(tmp_dir, "good")
      missing_repo = Path.join(tmp_dir, "does-not-exist")
      [good_repo, "packages", "alpha"] |> Path.join() |> File.mkdir_p!()

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          start_supervised!(
            {AdaptorRegistry,
             [name: test, local_adaptors_repos: [missing_repo, good_repo]]}
          )

          AdaptorRegistry.all(test)
        end)

      names = AdaptorRegistry.all(test) |> Enum.map(& &1.name)
      assert names == ["@openfn/language-alpha"]
      assert log =~ "Skipping local adaptors repo"
      assert log =~ missing_repo
    end
  end

  describe "local_adaptors_enabled?/0" do
    test "returns true when a non-empty plural list is configured" do
      Mox.stub(Lightning.MockConfig, :adaptor_registry, fn ->
        [local_adaptors_repos: ["/some/path"]]
      end)

      assert AdaptorRegistry.local_adaptors_enabled?()
    end

    test "returns false when the list is empty" do
      Mox.stub(Lightning.MockConfig, :adaptor_registry, fn ->
        [local_adaptors_repos: []]
      end)

      refute AdaptorRegistry.local_adaptors_enabled?()
    end

    test "returns false when the key is absent" do
      Mox.stub(Lightning.MockConfig, :adaptor_registry, fn -> [] end)

      refute AdaptorRegistry.local_adaptors_enabled?()
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

    test "it can split off semver range versions" do
      assert AdaptorRegistry.resolve_package_name("@openfn/language-foo@2.x") ==
               {"@openfn/language-foo", "2.x"}

      assert AdaptorRegistry.resolve_package_name("@openfn/language-foo@2.1.x") ==
               {"@openfn/language-foo", "2.1.x"}

      assert AdaptorRegistry.resolve_package_name("@openfn/language-foo@^2.1.0") ==
               {"@openfn/language-foo", "^2.1.0"}

      assert AdaptorRegistry.resolve_package_name("@openfn/language-foo@~2.1") ==
               {"@openfn/language-foo", "~2.1"}
    end

    @tag :tmp_dir
    test "returns local as the version when local_adaptors_repos config is set",
         %{tmp_dir: tmp_dir} do
      Mox.stub(Lightning.MockConfig, :adaptor_registry, fn ->
        [local_adaptors_repos: [tmp_dir]]
      end)

      assert AdaptorRegistry.resolve_package_name("@openfn/language-foo@1.2.3") ==
               {"@openfn/language-foo", "local"}

      assert AdaptorRegistry.resolve_package_name("@openfn/language-foo") ==
               {"@openfn/language-foo", "local"}

      assert AdaptorRegistry.resolve_package_name("") ==
               {nil, nil}
    end
  end

  describe "resolve_adaptor/1" do
    # The default (application-started) registry uses the test fixture cache,
    # where @openfn/language-common has latest 1.6.2 and versions
    # 1.1.0, 1.1.12, 1.2.3, 1.2.14, 1.2.22, 1.6.2, 1.10.3 and 2.14.0.
    test "resolves @latest to the registry's latest version" do
      assert AdaptorRegistry.resolve_adaptor("@openfn/language-common@latest") ==
               "@openfn/language-common@1.6.2"
    end

    test "resolves semver ranges to the highest matching known version" do
      assert AdaptorRegistry.resolve_adaptor("@openfn/language-common@1.x") ==
               "@openfn/language-common@1.10.3"

      assert AdaptorRegistry.resolve_adaptor("@openfn/language-common@1.2.x") ==
               "@openfn/language-common@1.2.22"

      assert AdaptorRegistry.resolve_adaptor("@openfn/language-common@^1.2.3") ==
               "@openfn/language-common@1.10.3"

      assert AdaptorRegistry.resolve_adaptor("@openfn/language-common@~1.2.14") ==
               "@openfn/language-common@1.2.22"

      assert AdaptorRegistry.resolve_adaptor("@openfn/language-common@~1.1") ==
               "@openfn/language-common@1.1.12"

      assert AdaptorRegistry.resolve_adaptor("@openfn/language-common@2.x") ==
               "@openfn/language-common@2.14.0"
    end

    test "passes exact versions through unchanged" do
      assert AdaptorRegistry.resolve_adaptor("@openfn/language-common@1.2.3") ==
               "@openfn/language-common@1.2.3"

      # even when the exact version is not in the registry
      assert AdaptorRegistry.resolve_adaptor("@openfn/language-common@9.9.9") ==
               "@openfn/language-common@9.9.9"
    end

    test "passes ranges through unchanged when nothing matches" do
      # no known version in range
      assert AdaptorRegistry.resolve_adaptor("@openfn/language-common@9.x") ==
               "@openfn/language-common@9.x"

      # unknown package
      assert AdaptorRegistry.resolve_adaptor("@openfn/language-nope@1.x") ==
               "@openfn/language-nope@1.x"
    end
  end

  describe "resolve_version_range/2" do
    test "resolves each supported range token to the highest match" do
      versions = ["5.9.9", "6.0.1", "6.4.0", "6.4.2", "6.5.0", "7.0.0"]

      assert AdaptorRegistry.resolve_version_range("6.x", versions) == "6.5.0"

      assert AdaptorRegistry.resolve_version_range("6.4.x", versions) ==
               "6.4.2"

      assert AdaptorRegistry.resolve_version_range("^6.4.1", versions) ==
               "6.5.0"

      assert AdaptorRegistry.resolve_version_range("~6.4.1", versions) ==
               "6.4.2"

      assert AdaptorRegistry.resolve_version_range("~6.4", versions) == "6.4.2"
    end

    test "applies floor semantics for ^ and ~ ranges" do
      versions = ["6.4.0", "6.4.1"]

      # nothing >= the floor, despite matching major/minor
      assert AdaptorRegistry.resolve_version_range("^6.4.2", versions) == nil
      assert AdaptorRegistry.resolve_version_range("~6.4.2", versions) == nil
    end

    test "ignores unparseable and pre-release versions" do
      versions = ["garbage", "6.1", "6.2.0-rc.1", "6.2.0", "6.3.0-beta"]

      assert AdaptorRegistry.resolve_version_range("6.x", versions) == "6.2.0"

      # a range covering only pre-releases resolves to nothing
      assert AdaptorRegistry.resolve_version_range("6.3.x", versions) == nil
    end

    test "returns nil for non-range tokens and empty version lists" do
      versions = ["1.2.3"]

      assert AdaptorRegistry.resolve_version_range("1.2.3", versions) == nil
      assert AdaptorRegistry.resolve_version_range("latest", versions) == nil
      assert AdaptorRegistry.resolve_version_range("local", versions) == nil
      assert AdaptorRegistry.resolve_version_range("x", versions) == nil
      assert AdaptorRegistry.resolve_version_range("^1.2", versions) == nil
      assert AdaptorRegistry.resolve_version_range(nil, versions) == nil
      assert AdaptorRegistry.resolve_version_range("1.x", []) == nil
    end
  end
end
