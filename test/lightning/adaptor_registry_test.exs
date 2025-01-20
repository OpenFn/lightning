defmodule Lightning.AdaptorRegistryTest do
  use Lightning.DataCase, async: false

  use Mimic

  alias Lightning.AdaptorRegistry

  describe "start_link/1" do
    # AdaptorRegistry is a GenServer, and so stubbed (external) functions must
    # be mocked globally. See: https://github.com/edgurgel/mimic#private-and-global-mode
    setup :set_mimic_from_context

    setup do
      stub(:hackney)

      :ok
    end

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
      # :hackney.request(request.method, request.url, request.headers, request.body, hn_options)
      expect(:hackney, :request, fn
        :get,
        "https://registry.npmjs.org/-/user/openfn/package",
        [],
        "",
        [recv_timeout: 15_000, pool: :default] ->
          {:ok, 200, "headers", :client}
      end)

      expect(:hackney, :body, fn :client, _timeout ->
        {:ok, File.read!("test/fixtures/openfn-packages-npm.json")}
      end)

      expected_adaptors = [
        "@openfn/language-asana",
        "@openfn/language-common",
        "@openfn/language-commcare",
        "@openfn/language-dhis2",
        "@openfn/language-http",
        "@openfn/language-salesforce"
      ]

      stub(:hackney, :body, fn :adaptor, _timeout ->
        {:ok, File.read!("test/fixtures/language-common-npm.json")}
      end)

      stub(:hackney, :request, fn
        :get,
        "https://registry.npmjs.org/" <> adaptor,
        [],
        "",
        [recv_timeout: 15_000, pool: :default] ->
          assert adaptor in expected_adaptors
          {:ok, 200, "headers", :adaptor}
      end)

      start_supervised!(
        {AdaptorRegistry, [name: :test_adaptor_registry, use_cache: false]}
      )

      results = AdaptorRegistry.all(:test_adaptor_registry)

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
