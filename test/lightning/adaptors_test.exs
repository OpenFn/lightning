defmodule Lightning.AdaptorsTest do
  use Lightning.DataCase, async: false

  import Eventually
  import Mox

  alias Lightning.Adaptors
  alias Lightning.Adaptors.Catalogue
  alias Lightning.Adaptors.Scheduler
  alias Lightning.Adaptors.Supervisor, as: AdaptorsSupervisor

  setup :set_mox_global
  setup :verify_on_exit!

  setup do
    sup = :"adaptors_test_#{System.unique_integer([:positive])}"

    start_supervised!(
      {AdaptorsSupervisor, name: sup, strategy: Lightning.Adaptors.StrategyMock}
    )

    Lightning.AdaptorTestHelpers.clear_global_adaptors_cache()

    {:ok, sup: sup}
  end

  defp adaptor_record(overrides \\ []) do
    overrides = Map.new(overrides)

    %{
      name: "@openfn/language-http",
      source: :npm,
      latest_version: "1.0.0",
      description: "HTTP adaptor",
      homepage: nil,
      repository: nil,
      license: "LGPL-3.0",
      deprecated: false,
      schema_data: nil,
      schema_sha256: nil,
      icon_square_ext: nil,
      icon_rectangle_ext: nil,
      icon_square_sha256: nil,
      icon_rectangle_sha256: nil,
      versions: [version_record("1.0.0")]
    }
    |> Map.merge(overrides)
  end

  defp version_record(version) do
    %{
      version: version,
      integrity: "sha512-#{version}",
      tarball_url: "https://example.com/x/-/x-#{version}.tgz",
      size_bytes: 1024,
      dependencies: %{},
      peer_dependencies: %{},
      published_at: nil,
      deprecated: false
    }
  end

  defp start_scheduler(sup) do
    original_env = Application.get_env(:lightning, Lightning.Adaptors, [])

    Application.put_env(
      :lightning,
      Lightning.Adaptors,
      Keyword.put(original_env, :refresh_interval, 99_999_999)
    )

    # Stop the supervisor's auto-started HighlanderPG (and its wrapped
    # Scheduler) so we can start a replacement under the controlled
    # interval without name collision. The test-owned Scheduler registers
    # directly under the same `{:global, …}` name production callers use.
    :ok =
      Supervisor.terminate_child(sup, AdaptorsSupervisor.highlander_name(sup))

    pid =
      start_supervised!({
        Scheduler,
        name: AdaptorsSupervisor.global_scheduler_name(sup),
        sup: sup,
        lock_key: AdaptorsSupervisor.lock_key(sup),
        cache: AdaptorsSupervisor.cache_name(sup),
        tasks: AdaptorsSupervisor.tasks_name(sup),
        source_topic: AdaptorsSupervisor.source_topic(sup)
      })

    Application.put_env(:lightning, Lightning.Adaptors, original_env)

    pid
  end

  describe "packages/1" do
    test "returns packages from DB", %{sup: sup} do
      stub(Lightning.Adaptors.StrategyMock, :fetch_adaptor, fn _ ->
        {:error, :unreachable}
      end)

      {:ok, _} = Catalogue.upsert_adaptor(adaptor_record())

      assert {:ok, [%Adaptors.Package{} = pkg]} =
               Adaptors.packages(sup)

      assert pkg.name == "@openfn/language-http"
      assert pkg.source == :npm
    end

    test "returns {:ok, []} when DB is empty", %{sup: sup} do
      assert {:ok, []} = Adaptors.packages(sup)
    end
  end

  describe "packages/0 delegates to packages(Lightning.Adaptors)" do
    test "packages/0 and packages(Lightning.Adaptors) return identical results" do
      # The production `Lightning.Adaptors.Supervisor` is started under the
      # name `Lightning.Adaptors` in `application.ex`; in test it uses
      # `Lightning.Adaptors.StrategyMock` per `config/test.exs`. Both forms
      # resolve to `Store.packages(Lightning.Adaptors)`; equality is always
      # guaranteed regardless of cache state.
      assert Adaptors.packages() ==
               Adaptors.packages(Lightning.Adaptors)
    end
  end

  describe "schema/2" do
    test "delegates to Store.schema/2 and returns schema", %{sup: sup} do
      stub(Lightning.Adaptors.StrategyMock, :fetch_adaptor, fn _ ->
        {:error, :unreachable}
      end)

      {:ok, _} =
        Catalogue.upsert_adaptor(
          adaptor_record(schema_data: ~s({"type":"object"}))
        )

      assert {:ok, ~s({"type":"object"})} =
               Adaptors.schema(sup, "@openfn/language-http")
    end

    test "preserves JSON property order across the DB round-trip", %{sup: sup} do
      stub(Lightning.Adaptors.StrategyMock, :fetch_adaptor, fn _ ->
        {:error, :unreachable}
      end)

      ordered_body = ~s({"a":1,"z":2,"m":3})

      {:ok, _} =
        Catalogue.upsert_adaptor(adaptor_record(schema_data: ordered_body))

      assert {:ok, ^ordered_body} =
               Adaptors.schema(sup, "@openfn/language-http")
    end
  end

  describe "get_adaptor/1" do
    test "returns a Package for an adaptor in the active source" do
      {:ok, _} =
        Catalogue.upsert_adaptor(adaptor_record(latest_version: "4.1.0"))

      assert %Adaptors.Package{
               name: "@openfn/language-http",
               source: :npm,
               latest_version: "4.1.0"
             } = Adaptors.get_adaptor("@openfn/language-http")
    end

    test "returns nil for an adaptor absent from the catalogue" do
      {:ok, _} = Catalogue.upsert_adaptor(adaptor_record())

      assert Adaptors.get_adaptor("@openfn/never-existed") == nil
    end

    test "returns nil when the catalogue is empty, without triggering a refresh" do
      stub(Lightning.Adaptors.StrategyMock, :list_adaptors, fn ->
        flunk("get_adaptor/1 must not trigger a load")
      end)

      assert Adaptors.get_adaptor("@openfn/language-http") == nil
    end

    test "still resolves a name the catalogue listing excludes" do
      {:ok, _} =
        Catalogue.upsert_adaptor(
          adaptor_record(name: "@openfn/language-collections")
        )

      assert %Adaptors.Package{name: "@openfn/language-collections"} =
               Adaptors.get_adaptor("@openfn/language-collections")

      assert {:ok, %Adaptors.Package{name: "@openfn/language-collections"}} =
               Adaptors.fetch_adaptor("@openfn/language-collections")
    end

    test "returns nil for a row under a different source than the active one" do
      {:ok, _} = Catalogue.upsert_adaptor(adaptor_record(source: :local))

      assert Adaptors.get_adaptor("@openfn/language-http") == nil
    end
  end

  describe "to_wire/1" do
    test "resolves @latest against the catalogue and passes semver through" do
      {:ok, _} =
        Catalogue.upsert_adaptor(adaptor_record(latest_version: "2.0.0"))

      assert Adaptors.to_wire("@openfn/language-http@latest") ==
               {:ok, "@openfn/language-http@2.0.0"}

      assert Adaptors.to_wire("@openfn/language-http@1.0.0") ==
               {:ok, "@openfn/language-http@1.0.0"}

      assert Adaptors.to_wire(nil) == {:ok, ""}
    end

    test "returns the lookup error for an unresolvable @latest" do
      {:ok, _} = Catalogue.upsert_adaptor(adaptor_record())

      assert Adaptors.to_wire("@openfn/never-existed@latest") ==
               {:error, :not_found}
    end

    test "preserves the @local literal" do
      assert Adaptors.to_wire("@openfn/language-http@local") ==
               {:ok, "@openfn/language-http@local"}
    end
  end

  describe "parse_spec/1" do
    test "splits a spec carrying a version" do
      assert Adaptors.parse_spec("@openfn/language-http@1.2.3") ==
               {"@openfn/language-http", "1.2.3"}

      assert Adaptors.parse_spec("@openfn/language-http@latest") ==
               {"@openfn/language-http", "latest"}

      assert Adaptors.parse_spec("common@1.0.0") == {"common", "1.0.0"}
    end

    test "returns a nil version for a spec without one" do
      assert Adaptors.parse_spec("@openfn/language-http") ==
               {"@openfn/language-http", nil}
    end

    test "returns {nil, nil} for a string that isn't a well-formed spec" do
      assert Adaptors.parse_spec("@openfn/language-http; rm -rf /") ==
               {nil, nil}

      assert Adaptors.parse_spec("@openfn/x\npwd\nb@1.0.0") == {nil, nil}
      assert Adaptors.parse_spec("") == {nil, nil}
    end
  end

  describe "valid_format?/1" do
    test "true for well-formed specs" do
      [
        "@openfn/language-http",
        "@openfn/language-http@1.2.3",
        "@openfn/language-http@1.2.3-pre",
        "@openfn/language-http@latest",
        "@openfn/language-http@local",
        "common",
        "common@1.0.0"
      ]
      |> Enum.each(fn spec ->
        assert Adaptors.valid_format?(spec), "expected #{inspect(spec)} to pass"
      end)
    end

    test "false for malformed / injection-shaped strings" do
      [
        "@openfn/x\npwd\nb@1.0.0",
        "@openfn/language-http@7.3.2; touch /tmp/x",
        "@openfn/language-common@latest and stuff",
        "@openfn/a/b/c@1.0.0",
        ""
      ]
      |> Enum.each(fn spec ->
        refute Adaptors.valid_format?(spec),
               "expected #{inspect(spec)} to be rejected"
      end)
    end
  end

  describe "refresh/1" do
    test "delegates to Scheduler.refresh_now via global_scheduler_name/1", %{
      sup: sup
    } do
      test_pid = self()

      # list_adaptors is called by the background Task that :tick spawns.
      # With an empty DB the scheduler fires an init-tick immediately, so
      # we must stub before start_scheduler and drain that first tick before
      # calling refresh (which triggers a second tick).
      stub(Lightning.Adaptors.StrategyMock, :list_adaptors, fn ->
        send(test_pid, :tick_ran)
        {:ok, []}
      end)

      stub(Lightning.Adaptors.StrategyMock, :fetch_icons, fn _opts ->
        {:ok, %{}}
      end)

      start_scheduler(sup)
      assert_receive :tick_ran, 2000

      # Let the init tick's cycle clear so refresh starts a new one instead
      # of coalescing.
      {:global, gname} = AdaptorsSupervisor.global_scheduler_name(sup)
      pid = :global.whereis_name(gname)
      assert_eventually(:sys.get_state(pid).refresh == nil, 2000)

      assert :ok = Adaptors.refresh(sup)
      assert_receive :tick_ran, 2000
      assert_eventually(:sys.get_state(pid).refresh == nil, 2000)
    end

    test "await: true returns the awaited cycle's counts", %{sup: sup} do
      stub(Lightning.Adaptors.StrategyMock, :list_adaptors, fn ->
        {:ok, []}
      end)

      stub(Lightning.Adaptors.StrategyMock, :fetch_icons, fn _opts ->
        {:ok, %{}}
      end)

      start_scheduler(sup)

      assert {:ok, %{listed: 0, changed: 0, fetched: 0, errors: 0}} =
               Adaptors.refresh(sup, await: true)
    end
  end

  describe "refresh/1 with a bare keyword list" do
    test "defaults the supervisor when given only opts" do
      stub(Lightning.Adaptors.StrategyMock, :list_adaptors, fn -> {:ok, []} end)

      stub(Lightning.Adaptors.StrategyMock, :fetch_icons, fn _opts ->
        {:ok, %{}}
      end)

      assert {:ok, _counts} = Adaptors.refresh(await: true, timeout: 2_000)

      Lightning.AdaptorTestHelpers.clear_global_adaptors_cache()
    end
  end

  describe "refresh_package/2" do
    test "delegates to Scheduler.refresh_package via global_scheduler_name/1", %{
      sup: sup
    } do
      stub(Lightning.Adaptors.StrategyMock, :list_adaptors, fn -> {:ok, []} end)

      stub(Lightning.Adaptors.StrategyMock, :fetch_icons, fn _opts ->
        {:ok, %{}}
      end)

      stub(Lightning.Adaptors.StrategyMock, :fetch_adaptor, fn _name ->
        {:ok, adaptor_record(latest_version: "2.0.0")}
      end)

      pid = start_scheduler(sup)

      assert :ok =
               Adaptors.refresh_package(sup, "@openfn/language-http")

      assert_eventually(:sys.get_state(pid).refresh == nil, 2000)
    end

    test "returns {:error, :unavailable} when no Scheduler is running", %{
      sup: sup
    } do
      :ok =
        Supervisor.terminate_child(sup, AdaptorsSupervisor.highlander_name(sup))

      assert {:error, :unavailable} =
               Adaptors.refresh_package(sup, "@openfn/language-http")
    end
  end

  describe "refresh_icons/1" do
    test "returns {:error, :unavailable} when no Scheduler is running", %{
      sup: sup
    } do
      :ok =
        Supervisor.terminate_child(sup, AdaptorsSupervisor.highlander_name(sup))

      assert {:error, :unavailable} = Adaptors.refresh_icons(sup)
    end
  end

  describe "icon_meta/1,2" do
    test "icon_meta is documented (it has callers in lightning_web)" do
      {:docs_v1, _, :elixir, _, _, _, docs} = Code.fetch_docs(Lightning.Adaptors)

      icon_meta_docs =
        Enum.filter(docs, fn
          {{:function, :icon_meta, _}, _, _, _, _} -> true
          _ -> false
        end)

      refute Enum.empty?(icon_meta_docs)

      Enum.each(icon_meta_docs, fn doc ->
        assert {{:function, :icon_meta, _}, _, _, %{"en" => _}, _} = doc
      end)
    end

    test "icon_meta/2 delegates to Store.icon_meta/2 for known adaptor", %{
      sup: sup
    } do
      {:ok, _} =
        Catalogue.upsert_adaptor(
          adaptor_record(
            icon_square_ext: "svg",
            icon_square_sha256: :crypto.hash(:sha256, "fake-svg-bytes")
          )
        )

      assert {:ok, meta} =
               Adaptors.icon_meta(sup, "@openfn/language-http")

      assert meta.icon_square_ext == "svg"
    end

    test "icon_meta/2 returns {:error, :not_found} for unknown adaptor", %{
      sup: sup
    } do
      assert {:error, :not_found} =
               Adaptors.icon_meta(sup, "@openfn/never-existed")
    end
  end
end
