defmodule Lightning.Adaptors.StoreTest do
  use Lightning.DataCase, async: true

  import Mox

  alias Lightning.Adaptors.Repo, as: AdaptorsRepo
  alias Lightning.Adaptors.Store
  alias Lightning.Adaptors.Supervisor, as: AdaptorsSupervisor

  setup :verify_on_exit!

  setup do
    # Each test owns an isolated `Lightning.Adaptors.Supervisor` instance,
    # parameterised on a unique `name:` so cache table / persistent_term
    # entries don't collide across the async suite. The `:strategy` opt
    # is threaded explicitly — no `Application.put_env` mutation.
    sup = :"store_test_#{System.unique_integer([:positive])}"

    start_supervised!(
      {AdaptorsSupervisor, name: sup, strategy: Lightning.Adaptors.StrategyMock}
    )

    cache = AdaptorsSupervisor.cache_name(sup)

    {:ok, sup: sup, cache: cache}
  end

  describe "schema/2" do
    test "cache hit returns cached value without touching Strategy or DB", %{
      sup: sup,
      cache: cache
    } do
      expect(Lightning.Adaptors.StrategyMock, :fetch_adaptor, 0, fn _ ->
        :unreachable
      end)

      source = AdaptorsSupervisor.source(sup)

      Cachex.put!(
        cache,
        {:schema, "@openfn/language-http", source},
        {:ok, %{"type" => "object"}}
      )

      assert {:ok, %{"type" => "object"}} =
               Store.schema(sup, "@openfn/language-http")

      assert AdaptorsRepo.get_adaptor("@openfn/language-http", source) == nil
    end

    test "cache miss + DB hit returns DB value without calling Strategy", %{
      sup: sup
    } do
      expect(Lightning.Adaptors.StrategyMock, :fetch_adaptor, 0, fn _ ->
        :unreachable
      end)

      {:ok, _} =
        AdaptorsRepo.upsert_adaptor(
          adaptor_record(schema_data: %{"type" => "object"})
        )

      assert {:ok, %{"type" => "object"}} =
               Store.schema(sup, "@openfn/language-http")
    end

    test "cache miss + DB miss calls Strategy once, upserts to DB, caches result",
         %{
           sup: sup,
           cache: cache
         } do
      source = AdaptorsSupervisor.source(sup)

      expect(
        Lightning.Adaptors.StrategyMock,
        :fetch_adaptor,
        1,
        fn "@openfn/language-http" ->
          {:ok, adaptor_record(schema_data: %{"type" => "object"})}
        end
      )

      assert {:ok, %{"type" => "object"}} =
               Store.schema(sup, "@openfn/language-http")

      assert %{schema_data: %{"type" => "object"}} =
               AdaptorsRepo.get_adaptor("@openfn/language-http", source)

      assert {:ok, {:ok, %{"type" => "object"}}} =
               Cachex.get(cache, {:schema, "@openfn/language-http", source})
    end

    test "three concurrent calls coalesce to one Strategy call", %{sup: sup} do
      name = "@openfn/language-http"
      test_pid = self()

      expect(Lightning.Adaptors.StrategyMock, :fetch_adaptor, 1, fn ^name ->
        # Brief sleep so the other two tasks queue up in Cachex's courier.
        Process.sleep(30)
        {:ok, adaptor_record(schema_data: %{"type" => "object"})}
      end)

      tasks =
        Enum.map(1..3, fn _ ->
          Task.async(fn ->
            receive do
              :go -> Store.schema(sup, name)
            end
          end)
        end)

      # Allow all tasks to use the test process's Mox expectations before releasing them.
      Enum.each(
        tasks,
        &Mox.allow(Lightning.Adaptors.StrategyMock, test_pid, &1.pid)
      )

      Enum.each(tasks, &send(&1.pid, :go))

      results = Task.await_many(tasks, 5_000)
      assert Enum.all?(results, &match?({:ok, %{"type" => "object"}}, &1))
    end

    test "Strategy error returns {:error, _} and is not cached — next call retries",
         %{
           sup: sup,
           cache: cache
         } do
      source = AdaptorsSupervisor.source(sup)

      expect(Lightning.Adaptors.StrategyMock, :fetch_adaptor, 1, fn _ ->
        {:error, :upstream_error}
      end)

      assert {:error, :upstream_error} =
               Store.schema(sup, "@openfn/language-http")

      assert {:ok, nil} =
               Cachex.get(cache, {:schema, "@openfn/language-http", source})

      expect(
        Lightning.Adaptors.StrategyMock,
        :fetch_adaptor,
        1,
        fn "@openfn/language-http" ->
          {:ok, adaptor_record(schema_data: %{"type" => "object"})}
        end
      )

      assert {:ok, %{"type" => "object"}} =
               Store.schema(sup, "@openfn/language-http")
    end
  end

  describe "versions/2" do
    test "cache miss + DB hit returns projected versions without calling Strategy",
         %{sup: sup} do
      expect(Lightning.Adaptors.StrategyMock, :fetch_adaptor, 0, fn _ ->
        :unreachable
      end)

      {:ok, _} =
        AdaptorsRepo.upsert_adaptor(
          adaptor_record(
            versions: [version_record("1.0.0"), version_record("1.1.0")]
          )
        )

      assert {:ok, versions} = Store.versions(sup, "@openfn/language-http")
      assert length(versions) == 2
      assert Enum.all?(versions, &Map.has_key?(&1, :version))
      assert Enum.all?(versions, &Map.has_key?(&1, :deprecated))
    end

    test "cache miss + DB miss calls Strategy and caches projected versions", %{
      sup: sup,
      cache: cache
    } do
      source = AdaptorsSupervisor.source(sup)

      expect(
        Lightning.Adaptors.StrategyMock,
        :fetch_adaptor,
        1,
        fn "@openfn/language-http" ->
          {:ok,
           adaptor_record(
             versions: [version_record("1.0.0"), version_record("2.0.0")]
           )}
        end
      )

      assert {:ok, versions} = Store.versions(sup, "@openfn/language-http")
      assert length(versions) == 2

      assert {:ok, {:ok, cached_versions}} =
               Cachex.get(cache, {:versions, "@openfn/language-http", source})

      assert length(cached_versions) == 2
    end
  end

  describe "packages/1" do
    test "empty DB returns {:ok, []} but does NOT cache the empty result", %{
      sup: sup,
      cache: cache
    } do
      expect(Lightning.Adaptors.StrategyMock, :fetch_adaptor, 0, fn _ ->
        :unreachable
      end)

      assert {:ok, []} = Store.packages(sup)

      source = AdaptorsSupervisor.source(sup)
      assert {:ok, nil} = Cachex.get(cache, {:packages, source})
    end

    test "DB with rows returns and caches package metas", %{
      sup: sup,
      cache: cache
    } do
      {:ok, _} = AdaptorsRepo.upsert_adaptor(adaptor_record())

      assert {:ok, [pkg]} = Store.packages(sup)
      assert pkg.name == "@openfn/language-http"

      source = AdaptorsSupervisor.source(sup)
      assert {:ok, {:ok, [_]}} = Cachex.get(cache, {:packages, source})
    end
  end

  describe "icon_meta/2" do
    test "unknown adaptor returns {:error, :not_found} and is not cached", %{
      sup: sup,
      cache: cache
    } do
      assert {:error, :not_found} = Store.icon_meta(sup, "@openfn/never-existed")

      source = AdaptorsSupervisor.source(sup)

      assert {:ok, nil} =
               Cachex.get(cache, {:icon_meta, "@openfn/never-existed", source})
    end

    test "known adaptor returns icon metadata and caches it", %{
      sup: sup,
      cache: cache
    } do
      {:ok, _} =
        AdaptorsRepo.upsert_adaptor(
          adaptor_record(
            icon_square_ext: "svg",
            icon_square_sha256: :crypto.hash(:sha256, "fake-svg-bytes")
          )
        )

      assert {:ok, meta} = Store.icon_meta(sup, "@openfn/language-http")
      assert meta.icon_square_ext == "svg"

      source = AdaptorsSupervisor.source(sup)

      assert {:ok, {:ok, cached}} =
               Cachex.get(cache, {:icon_meta, "@openfn/language-http", source})

      assert cached.icon_square_ext == "svg"
    end
  end

  describe "warm_from_repo/1" do
    test "populates {:packages, source} and {:icon_meta, name, source} keys", %{
      sup: sup,
      cache: cache
    } do
      {:ok, _} = AdaptorsRepo.upsert_adaptor(adaptor_record())

      assert :ok = Store.warm_from_repo(sup)

      source = AdaptorsSupervisor.source(sup)

      assert {:ok, {:ok, [pkg]}} = Cachex.get(cache, {:packages, source})
      assert pkg.name == "@openfn/language-http"

      assert {:ok, {:ok, icon_meta}} =
               Cachex.get(cache, {:icon_meta, "@openfn/language-http", source})

      assert Map.has_key?(icon_meta, :icon_square_ext)
      assert Map.has_key?(icon_meta, :icon_rectangle_ext)
    end

    test "overwrites existing keys without clearing unrelated ones", %{
      sup: sup,
      cache: cache
    } do
      source = AdaptorsSupervisor.source(sup)

      Cachex.put!(
        cache,
        {:schema, "pre-existing", source},
        {:ok, %{"kept" => true}}
      )

      {:ok, _} = AdaptorsRepo.upsert_adaptor(adaptor_record())
      assert :ok = Store.warm_from_repo(sup)

      assert {:ok, {:ok, %{"kept" => true}}} =
               Cachex.get(cache, {:schema, "pre-existing", source})
    end
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
end
