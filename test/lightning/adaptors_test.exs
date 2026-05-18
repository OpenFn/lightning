defmodule Lightning.AdaptorsTest do
  use Lightning.DataCase, async: false

  import Mox

  alias Lightning.Adaptors
  alias Lightning.Adaptors.Repo, as: AdaptorsRepo
  alias Lightning.Adaptors.Scheduler
  alias Lightning.Adaptors.Supervisor, as: AdaptorsSupervisor

  setup :set_mox_global
  setup :verify_on_exit!

  setup do
    sup = :"adaptors_test_#{System.unique_integer([:positive])}"

    start_supervised!(
      {AdaptorsSupervisor, name: sup, strategy: Lightning.Adaptors.StrategyMock}
    )

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

      {:ok, _} = AdaptorsRepo.upsert_adaptor(adaptor_record())

      assert {:ok, [pkg]} = Adaptors.packages(sup)
      assert pkg.name == "@openfn/language-http"
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
      assert Adaptors.packages() == Adaptors.packages(Lightning.Adaptors)
    end
  end

  describe "versions/2" do
    test "delegates to Store.versions/2 and returns version list", %{sup: sup} do
      stub(Lightning.Adaptors.StrategyMock, :fetch_adaptor, fn _ ->
        {:error, :unreachable}
      end)

      {:ok, _} = AdaptorsRepo.upsert_adaptor(adaptor_record())

      assert {:ok, [v]} = Adaptors.versions(sup, "@openfn/language-http")
      assert v.version == "1.0.0"
    end

    test "returns {:error, _} for unknown adaptor when strategy unavailable", %{
      sup: sup
    } do
      stub(Lightning.Adaptors.StrategyMock, :fetch_adaptor, fn _ ->
        {:error, :not_found}
      end)

      assert {:error, _} = Adaptors.versions(sup, "@openfn/does-not-exist")
    end
  end

  describe "schema/2" do
    test "delegates to Store.schema/2 and returns schema", %{sup: sup} do
      stub(Lightning.Adaptors.StrategyMock, :fetch_adaptor, fn _ ->
        {:error, :unreachable}
      end)

      {:ok, _} =
        AdaptorsRepo.upsert_adaptor(
          adaptor_record(schema_data: %{"type" => "object"})
        )

      assert {:ok, %{"type" => "object"}} =
               Adaptors.schema(sup, "@openfn/language-http")
    end
  end

  describe "resolve_version/2" do
    test "\"latest\" resolves from DB and returns latest_version" do
      {:ok, _} =
        AdaptorsRepo.upsert_adaptor(adaptor_record(latest_version: "2.3.4"))

      assert {:ok, "2.3.4"} =
               Adaptors.resolve_version("@openfn/language-http", "latest")
    end

    test "\"local\" resolves from DB and returns latest_version" do
      {:ok, _} =
        AdaptorsRepo.upsert_adaptor(adaptor_record(latest_version: "1.5.0"))

      assert {:ok, "1.5.0"} =
               Adaptors.resolve_version("@openfn/language-http", "local")
    end

    test "\"latest\" returns {:error, :not_found} when adaptor absent from DB" do
      assert {:error, :not_found} =
               Adaptors.resolve_version("@openfn/does-not-exist", "latest")
    end

    test "concrete semver passes through without any DB lookup" do
      # No adaptor in DB: if a lookup occurred the result would be :not_found.
      # Pass-through means we get {:ok, version} regardless.
      assert {:ok, "3.0.0"} =
               Adaptors.resolve_version("@openfn/language-http", "3.0.0")
    end
  end

  describe "refresh_now/1" do
    test "delegates to Scheduler.refresh_now via global_scheduler_name/1", %{
      sup: sup
    } do
      test_pid = self()

      # list_adaptors is called by the background Task that :tick spawns.
      # With an empty DB the scheduler fires an init-tick immediately, so
      # we must stub before start_scheduler and drain that first tick before
      # calling refresh_now (which triggers a second tick).
      stub(Lightning.Adaptors.StrategyMock, :list_adaptors, fn ->
        send(test_pid, :tick_ran)
        {:ok, []}
      end)

      start_scheduler(sup)
      assert_receive :tick_ran, 2000

      assert :ok = Adaptors.refresh_now(sup)
      assert_receive :tick_ran, 2000
    end
  end

  describe "refresh_package/2" do
    test "delegates to Scheduler.refresh_package via global_scheduler_name/1", %{
      sup: sup
    } do
      stub(Lightning.Adaptors.StrategyMock, :fetch_adaptor, fn _name ->
        {:ok, adaptor_record(latest_version: "2.0.0")}
      end)

      start_scheduler(sup)

      assert :ok = Adaptors.refresh_package(sup, "@openfn/language-http")
    end
  end

  describe "icon_meta/1,2" do
    test "icon_meta is @doc false for all arities" do
      {:docs_v1, _, :elixir, _, _, _, docs} = Code.fetch_docs(Lightning.Adaptors)

      icon_meta_docs =
        Enum.filter(docs, fn
          {{:function, :icon_meta, _}, _, _, _, _} -> true
          _ -> false
        end)

      refute Enum.empty?(icon_meta_docs)

      Enum.each(icon_meta_docs, fn doc ->
        assert {{:function, :icon_meta, _}, _, _, :hidden, _} = doc
      end)
    end

    test "icon_meta/2 delegates to Store.icon_meta/2 for known adaptor", %{
      sup: sup
    } do
      {:ok, _} =
        AdaptorsRepo.upsert_adaptor(
          adaptor_record(
            icon_square_ext: "svg",
            icon_square_sha256: :crypto.hash(:sha256, "fake-svg-bytes")
          )
        )

      assert {:ok, meta} = Adaptors.icon_meta(sup, "@openfn/language-http")
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
