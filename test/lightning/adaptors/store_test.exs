defmodule Lightning.Adaptors.StoreTest do
  use Lightning.DataCase, async: true

  import Lightning.AdaptorTestHelpers

  import Mox

  alias Lightning.Adaptors.Catalogue
  alias Lightning.Adaptors.Store
  alias Lightning.Adaptors.Supervisor, as: AdaptorsSupervisor
  alias LightningWeb.AdaptorIconURL

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
        {:ok, ~s({"type":"object"})}
      )

      assert {:ok, ~s({"type":"object"})} =
               Store.schema(sup, "@openfn/language-http")

      assert Catalogue.get_adaptor("@openfn/language-http", source) == nil
    end

    test "cache miss + DB hit returns DB value without calling Strategy", %{
      sup: sup
    } do
      expect(Lightning.Adaptors.StrategyMock, :fetch_adaptor, 0, fn _ ->
        :unreachable
      end)

      {:ok, _} =
        Catalogue.upsert_adaptor(
          adaptor_record(schema_data: ~s({"type":"object"}))
        )

      assert {:ok, ~s({"type":"object"})} =
               Store.schema(sup, "@openfn/language-http")
    end

    test "a row with no schema answers an empty one without calling Strategy",
         %{sup: sup, cache: cache} do
      source = AdaptorsSupervisor.source(sup)
      name = "@openfn/language-http"

      {:ok, _} = Catalogue.upsert_adaptor(adaptor_record(schema_data: nil))

      expect(Lightning.Adaptors.StrategyMock, :fetch_adaptor, 0, fn _ ->
        :unreachable
      end)

      assert {:ok, "{}"} = Store.schema(sup, name)
      assert {:ok, "{}"} = Store.schema(sup, name)
      assert {:ok, {:ok, "{}"}} = Cachex.get(cache, {:schema, name, source})
    end

    test "unknown adaptor returns {:error, :not_found} without calling Strategy or minting a row",
         %{sup: sup, cache: cache} do
      expect(Lightning.Adaptors.StrategyMock, :fetch_adaptor, 0, fn _ ->
        :unreachable
      end)

      source = AdaptorsSupervisor.source(sup)

      assert {:error, :not_found} = Store.schema(sup, "@openfn/never-existed")
      assert Catalogue.get_adaptor("@openfn/never-existed", source) == nil

      assert {:ok, nil} =
               Cachex.get(cache, {:schema, "@openfn/never-existed", source})
    end

    test "preserves JSON property order from the stored row",
         %{sup: sup} do
      expect(Lightning.Adaptors.StrategyMock, :fetch_adaptor, 0, fn _ ->
        :unreachable
      end)

      ordered_body = ~s({"a":1,"z":2,"m":3})

      {:ok, _} =
        Catalogue.upsert_adaptor(adaptor_record(schema_data: ordered_body))

      assert {:ok, ^ordered_body} = Store.schema(sup, "@openfn/language-http")
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
      {:ok, _} = Catalogue.upsert_adaptor(adaptor_record())

      assert {:ok, [pkg]} = Store.packages(sup)
      assert pkg.name == "@openfn/language-http"

      source = AdaptorsSupervisor.source(sup)
      assert {:ok, {:ok, [_]}} = Cachex.get(cache, {:packages, source})
    end

    test "the catalogue's excluded adaptors never reach the cache", %{
      sup: sup,
      cache: cache
    } do
      {:ok, _} =
        Catalogue.upsert_adaptor(
          adaptor_record(name: "@openfn/language-collections")
        )

      {:ok, _} = Catalogue.upsert_adaptor(adaptor_record())

      assert {:ok, [%{name: "@openfn/language-http"}]} = Store.packages(sup)

      source = AdaptorsSupervisor.source(sup)

      assert {:ok, {:ok, [%{name: "@openfn/language-http"}]}} =
               Cachex.get(cache, {:packages, source})
    end
  end

  describe "catalogue/1" do
    test "empty DB returns an empty payload but does NOT cache it", %{
      sup: sup,
      cache: cache
    } do
      assert {:ok, {{nil, 0}, []}} = Store.catalogue(sup)

      source = AdaptorsSupervisor.source(sup)
      assert {:ok, nil} = Cachex.get(cache, {:catalogue, source})
    end

    test "caches the stamp and the rendered payload as one entry", %{
      sup: sup,
      cache: cache
    } do
      square_sha = :crypto.hash(:sha256, "square")

      {:ok, _} =
        Catalogue.upsert_adaptor(
          adaptor_record(
            repository: "https://github.com/openfn/language-http",
            icon_square_ext: "png",
            icon_square_sha256: square_sha
          )
        )

      assert {:ok, {{%DateTime{}, 1}, [entry]}} = Store.catalogue(sup)

      assert entry == %{
               name: "@openfn/language-http",
               latest_version: "1.0.0",
               versions: ["1.0.0"],
               repository: "https://github.com/openfn/language-http",
               icon_urls: %{
                 square:
                   AdaptorIconURL.build(
                     "@openfn/language-http",
                     %{icon_square_ext: "png", icon_square_sha256: square_sha},
                     :square
                   ),
                 rectangle: nil
               }
             }

      source = AdaptorsSupervisor.source(sup)

      assert {:ok, {:ok, {{%DateTime{}, 1}, [^entry]}}} =
               Cachex.get(cache, {:catalogue, source})
    end

    test "a second call is served from cache, without re-reading the projection",
         %{sup: sup} do
      {:ok, _} = Catalogue.upsert_adaptor(adaptor_record())

      assert {:ok, first} = Store.catalogue(sup)

      {:ok, _} =
        Catalogue.upsert_adaptor(adaptor_record(name: "@openfn/language-late"))

      assert {:ok, ^first} = Store.catalogue(sup)
    end

    test "local-source entries render latest_version and versions as \"local\", not the real on-disk semver" do
      local_sup = :"store_test_local_#{System.unique_integer([:positive])}"

      start_supervised!(
        Supervisor.child_spec(
          {AdaptorsSupervisor,
           name: local_sup, strategy: Lightning.Adaptors.Local},
          id: local_sup
        )
      )

      {:ok, _} =
        Catalogue.upsert_adaptor(
          adaptor_record(
            source: :local,
            latest_version: "1.4.2",
            versions: [version_record("1.4.2")]
          )
        )

      assert {:ok, {_stamp, [entry]}} = Store.catalogue(local_sup)

      assert entry.latest_version == "local"
      assert entry.versions == ["local"]
    end

    test "npm-source entries keep the real semver untouched", %{sup: sup} do
      {:ok, _} =
        Catalogue.upsert_adaptor(
          adaptor_record(
            latest_version: "1.4.2",
            versions: [version_record("1.4.2")]
          )
        )

      assert {:ok, {_stamp, [entry]}} = Store.catalogue(sup)

      assert entry.latest_version == "1.4.2"
      assert entry.versions == ["1.4.2"]
    end
  end

  describe "icon/3" do
    # Each test uses a unique adaptor name so the on-disk cache (shared
    # default {:tmp, "lightning/adaptor_icons"} path) does not collide
    # across this `async: true` suite. Directories created here are not
    # cleaned up — they live under System.tmp_dir! and are namespaced
    # per-name so they cannot collide.
    defp unique_name(prefix) do
      "@openfn/language-#{prefix}-#{System.unique_integer([:positive])}"
    end

    test "disk hit returns path without calling Strategy", %{sup: sup} do
      source = AdaptorsSupervisor.source(sup)
      name = unique_name("disk-hit")

      {:ok, _} =
        Catalogue.upsert_adaptor(
          adaptor_record(
            name: name,
            icon_square_ext: "png",
            icon_square_sha256: :crypto.hash(:sha256, "PRE_WARMED")
          )
        )

      Lightning.Adaptors.IconCache.write!(
        source,
        name,
        :square,
        "png",
        "PRE_WARMED",
        :crypto.hash(:sha256, "PRE_WARMED")
      )

      expect(Lightning.Adaptors.StrategyMock, :fetch_icon, 0, fn _, _ ->
        :unreachable
      end)

      assert {:ok, path} = Store.icon(sup, name, :square)
      assert File.read!(path) == "PRE_WARMED"
    end

    test "stale disk cache (sha mismatch) self-heals by re-fetching", %{
      sup: sup
    } do
      source = AdaptorsSupervisor.source(sup)
      name = unique_name("stale")

      {:ok, _} =
        Catalogue.upsert_adaptor(
          adaptor_record(
            name: name,
            icon_square_ext: "png",
            icon_square_sha256: :crypto.hash(:sha256, "FRESH_BYTES")
          )
        )

      Lightning.Adaptors.IconCache.write!(
        source,
        name,
        :square,
        "png",
        "STALE_BYTES",
        :crypto.hash(:sha256, "STALE_BYTES")
      )

      expect(Lightning.Adaptors.StrategyMock, :fetch_icon, 1, fn ^name,
                                                                 :square ->
        {:ok, %{data: "FRESH_BYTES", ext: "png"}}
      end)

      assert {:ok, path} = Store.icon(sup, name, :square)
      assert File.read!(path) == "FRESH_BYTES"
    end

    test "Strategy returns bytes that don't match the row's expected sha", %{
      sup: sup,
      cache: cache
    } do
      source = AdaptorsSupervisor.source(sup)
      name = unique_name("corrupt")

      {:ok, _} =
        Catalogue.upsert_adaptor(
          adaptor_record(
            name: name,
            icon_square_ext: "png",
            icon_square_sha256: :crypto.hash(:sha256, "EXPECTED_BYTES")
          )
        )

      expect(Lightning.Adaptors.StrategyMock, :fetch_icon, 1, fn ^name,
                                                                 :square ->
        {:ok, %{data: "WRONG_BYTES", ext: "png"}}
      end)

      assert {:error, {:icon_sha_mismatch, _}} = Store.icon(sup, name, :square)

      assert {:ok, {:error, {:icon_sha_mismatch, _}}} =
               Cachex.get(cache, {:icon_bytes, source, name, :square})

      assert {:error, {:icon_sha_mismatch, _}} = Store.icon(sup, name, :square)
    end

    test "Strategy returns an extension the row doesn't claim", %{
      sup: sup,
      cache: cache
    } do
      source = AdaptorsSupervisor.source(sup)
      name = unique_name("wrong-ext")

      {:ok, _} =
        Catalogue.upsert_adaptor(
          adaptor_record(
            name: name,
            icon_square_ext: "png",
            icon_square_sha256: :crypto.hash(:sha256, "EXPECTED_BYTES")
          )
        )

      expect(Lightning.Adaptors.StrategyMock, :fetch_icon, 1, fn ^name,
                                                                 :square ->
        {:ok, %{data: "EXPECTED_BYTES", ext: "svg"}}
      end)

      assert {:error, {:ext_mismatch, expected: "png", got: "svg"}} =
               Store.icon(sup, name, :square)

      assert {:ok, {:error, {:ext_mismatch, _}}} =
               Cachex.get(cache, {:icon_bytes, source, name, :square})

      assert {:error, {:ext_mismatch, _}} = Store.icon(sup, name, :square)
    end

    test "disk miss + Strategy success writes to disk and returns path", %{
      sup: sup,
      cache: cache
    } do
      source = AdaptorsSupervisor.source(sup)
      name = unique_name("disk-miss")

      {:ok, _} =
        Catalogue.upsert_adaptor(
          adaptor_record(
            name: name,
            icon_square_ext: "png",
            icon_square_sha256: :crypto.hash(:sha256, "LAZY_BYTES")
          )
        )

      expect(Lightning.Adaptors.StrategyMock, :fetch_icon, 1, fn ^name,
                                                                 :square ->
        {:ok, %{data: "LAZY_BYTES", ext: "png"}}
      end)

      assert {:ok, path} = Store.icon(sup, name, :square)
      assert File.read!(path) == "LAZY_BYTES"

      # Courier returned {:ignore, _} → no committed entry on the bytes key.
      assert {:ok, nil} =
               Cachex.get(cache, {:icon_bytes, source, name, :square})
    end

    test "Strategy error returns {:error, _} and does not commit", %{
      sup: sup,
      cache: cache
    } do
      source = AdaptorsSupervisor.source(sup)
      name = unique_name("err")

      {:ok, _} =
        Catalogue.upsert_adaptor(
          adaptor_record(
            name: name,
            icon_square_ext: "png",
            icon_square_sha256: :crypto.hash(:sha256, "UNUSED")
          )
        )

      expect(Lightning.Adaptors.StrategyMock, :fetch_icon, 2, fn _, _ ->
        {:error, :upstream_5xx}
      end)

      assert {:error, :upstream_5xx} = Store.icon(sup, name, :square)

      assert {:ok, nil} =
               Cachex.get(cache, {:icon_bytes, source, name, :square})

      assert {:error, :upstream_5xx} = Store.icon(sup, name, :square)
    end

    test "concurrent first-callers coalesce onto one Strategy fetch", %{
      sup: sup
    } do
      test_pid = self()
      name = unique_name("coalesce")

      {:ok, _} =
        Catalogue.upsert_adaptor(
          adaptor_record(
            name: name,
            icon_square_ext: "png",
            icon_square_sha256: :crypto.hash(:sha256, "COALESCED")
          )
        )

      # Single Mox expectation → if both callers reach the strategy
      # the second hits "no expectation" and Mox raises.
      expect(Lightning.Adaptors.StrategyMock, :fetch_icon, 1, fn ^name,
                                                                 :square ->
        send(test_pid, :fetch_started)
        # Block long enough for the second caller to also reach the
        # Cachex courier and coalesce onto this call.
        Process.sleep(150)
        {:ok, %{data: "COALESCED", ext: "png"}}
      end)

      t1 = Task.async(fn -> Store.icon(sup, name, :square) end)
      assert_receive :fetch_started, 1000
      t2 = Task.async(fn -> Store.icon(sup, name, :square) end)

      assert {:ok, p1} = Task.await(t1, 5000)
      assert {:ok, p2} = Task.await(t2, 5000)
      assert p1 == p2
      assert File.read!(p1) == "COALESCED"
    end

    test "different (name, shape) misses fetch in parallel without false coalescing",
         %{sup: sup} do
      test_pid = self()
      name_a = unique_name("parA")
      name_b = unique_name("parB")

      {:ok, _} =
        Catalogue.upsert_adaptor(
          adaptor_record(
            name: name_a,
            icon_square_ext: "png",
            icon_square_sha256: :crypto.hash(:sha256, "A_BYTES")
          )
        )

      {:ok, _} =
        Catalogue.upsert_adaptor(
          adaptor_record(
            name: name_b,
            icon_square_ext: "png",
            icon_square_sha256: :crypto.hash(:sha256, "B_BYTES")
          )
        )

      # Single multi-clause expectation with count: 2 — Mox routes by
      # pattern within one slot, so the two parallel courier calls can
      # arrive in either order. Two separate `expect/3` calls would
      # queue FIFO and crash with FunctionClauseError when the task
      # arrival order doesn't match the expectation insertion order.
      expect(Lightning.Adaptors.StrategyMock, :fetch_icon, 2, fn
        ^name_a, :square -> {:ok, %{data: "A_BYTES", ext: "png"}}
        ^name_b, :square -> {:ok, %{data: "B_BYTES", ext: "png"}}
      end)

      t_a =
        Task.async(fn ->
          receive do
            :go -> Store.icon(sup, name_a, :square)
          end
        end)

      t_b =
        Task.async(fn ->
          receive do
            :go -> Store.icon(sup, name_b, :square)
          end
        end)

      Mox.allow(Lightning.Adaptors.StrategyMock, test_pid, t_a.pid)
      Mox.allow(Lightning.Adaptors.StrategyMock, test_pid, t_b.pid)

      send(t_a.pid, :go)
      send(t_b.pid, :go)

      assert {:ok, p1} = Task.await(t_a, 5000)
      assert {:ok, p2} = Task.await(t_b, 5000)

      assert File.read!(p1) == "A_BYTES"
      assert File.read!(p2) == "B_BYTES"
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
        Catalogue.upsert_adaptor(
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
    test "populates the {:packages}, {:icon_meta} and {:catalogue} keys", %{
      sup: sup,
      cache: cache
    } do
      {:ok, _} = Catalogue.upsert_adaptor(adaptor_record())

      assert :ok = Store.warm_from_repo(sup)

      source = AdaptorsSupervisor.source(sup)

      assert {:ok, {:ok, [pkg]}} = Cachex.get(cache, {:packages, source})
      assert pkg.name == "@openfn/language-http"

      assert {:ok, {:ok, icon_meta}} =
               Cachex.get(cache, {:icon_meta, "@openfn/language-http", source})

      assert Map.has_key?(icon_meta, :icon_square_ext)
      assert Map.has_key?(icon_meta, :icon_rectangle_ext)

      assert {:ok, {:ok, {{%DateTime{}, 1}, [entry]}}} =
               Cachex.get(cache, {:catalogue, source})

      assert entry.name == "@openfn/language-http"
      assert entry.icon_urls == %{square: nil, rectangle: nil}
    end

    test "leaves {:catalogue, source} uncached when the catalogue is empty", %{
      sup: sup,
      cache: cache
    } do
      assert :ok = Store.warm_from_repo(sup)

      source = AdaptorsSupervisor.source(sup)
      assert {:ok, nil} = Cachex.get(cache, {:catalogue, source})
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

      {:ok, _} = Catalogue.upsert_adaptor(adaptor_record())
      assert :ok = Store.warm_from_repo(sup)

      assert {:ok, {:ok, %{"kept" => true}}} =
               Cachex.get(cache, {:schema, "pre-existing", source})
    end
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
