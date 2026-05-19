defmodule Lightning.AdaptorTestHelpers do
  @moduledoc """
  Test helpers for seeding the `Lightning.Adaptors.Repo` and clearing the
  global `Lightning.Adaptors.Supervisor` Cachex.

  The production `Lightning.Adaptors` supervisor is started by the
  application and shared across the test suite — its Cachex persists
  across the `Ecto.Adapters.SQL.Sandbox` boundary, so tests that seed
  rows via `Lightning.Factories.adaptor/2` must clear the cache to make
  those rows visible to facade reads.

  See `test/lightning/adaptors_test.exs` and
  `test/lightning/adaptors/store_test.exs` for the canonical patterns
  exercised by per-test isolated supervisors. This module covers the
  complementary case: tests that touch the production-named supervisor
  via `Lightning.Adaptors.{packages, versions, schema, resolve_version}`.
  """

  import Lightning.Factories

  alias Lightning.Adaptors.Supervisor, as: AdaptorsSupervisor

  @doc """
  Clear the production `Lightning.Adaptors` Cachex so subsequent reads
  fall back through the DB.
  """
  @spec clear_global_adaptors_cache() :: :ok
  def clear_global_adaptors_cache do
    cache = AdaptorsSupervisor.cache_name(Lightning.Adaptors)
    Cachex.clear(cache)
    :ok
  end

  @doc """
  Insert one `Adaptors.Repo.Adaptor` row using the factory and clear
  the global Cachex so it's immediately visible to facade reads.

  `attrs` is forwarded to the `:adaptor` factory verbatim.
  """
  @spec seed_adaptor(keyword() | map()) :: Lightning.Adaptors.Repo.Adaptor.t()
  def seed_adaptor(attrs \\ []) do
    row = insert(:adaptor, attrs)
    clear_global_adaptors_cache()
    row
  end

  @doc """
  Seed a credential schema row keyed by short name (e.g. `"postgresql"`),
  reading the JSON body from `test/fixtures/schemas/<name>.json`.

  After `lib/lightning/credentials.ex` was migrated to read schemas via
  `Lightning.Adaptors.schema/1`, schema fixtures live in the adaptor
  registry rather than on disk; tests that exercise
  `Credentials.get_schema/1` must seed them here.
  """
  @spec seed_credential_schema(String.t()) ::
          Lightning.Adaptors.Repo.Adaptor.t()
  def seed_credential_schema(short_name) when is_binary(short_name) do
    schema_data =
      Path.join(["test", "fixtures", "schemas", "#{short_name}.json"])
      |> File.read!()
      |> Jason.decode!()

    row =
      insert(:adaptor, name: short_name, source: :npm, schema_data: schema_data)

    # Cachex's fallback runs in the Courier process — it can't see the
    # test-owned sandbox connection. Pre-populate the cache so reads
    # never need to fall through to a DB lookup from the Courier.
    cache = AdaptorsSupervisor.cache_name(Lightning.Adaptors)
    source = AdaptorsSupervisor.source(Lightning.Adaptors)
    Cachex.put(cache, {:schema, short_name, source}, {:ok, schema_data})

    row
  end

  @doc """
  Seed every credential schema present in `test/fixtures/schemas/`.

  Use from a `setup` block in tests that exercise multiple credential
  types (e.g. `LightningWeb.CredentialLiveTest`).
  """
  @spec seed_all_credential_schemas() :: :ok
  def seed_all_credential_schemas do
    Path.wildcard("test/fixtures/schemas/*.json")
    |> Enum.each(fn path ->
      # Skip empty fixture files (e.g. `asana.json`, `primero.json` are
      # intentional empty placeholders).
      if File.stat!(path).size > 0 do
        short_name = path |> Path.basename(".json")
        seed_credential_schema(short_name)
      end
    end)

    :ok
  end

  @doc """
  Seed an `@openfn/*` adaptor package with a concrete `latest_version`
  so `Lightning.Adaptors.PackageName.to_wire/1` resolves `@latest`
  correctly. The legacy `AdaptorRegistry` fixture
  (`test/fixtures/adaptor_registry_cache.json`) used to provide these
  resolutions for free; the migrated facade reads them from Postgres.
  """
  @spec seed_adaptor_package(String.t(), String.t() | [String.t()]) ::
          Lightning.Adaptors.Repo.Adaptor.t()
  def seed_adaptor_package(name, versions)
      when is_binary(name) and is_list(versions) do
    # Latest is the first entry per legacy registry semantics.
    [latest | _] = versions

    {:ok, row} =
      Lightning.Adaptors.Repo.upsert_adaptor(%{
        name: name,
        source: :npm,
        latest_version: latest,
        description: nil,
        homepage: nil,
        repository: nil,
        license: nil,
        deprecated: false,
        schema_data: nil,
        schema_sha256: nil,
        versions:
          Enum.map(versions, fn v ->
            %{
              version: v,
              integrity: "sha512-#{v}",
              tarball_url: "https://example.com/x-#{v}.tgz",
              size_bytes: 1024,
              dependencies: %{},
              peer_dependencies: %{},
              published_at: nil,
              deprecated: false
            }
          end)
      })

    row
  end

  def seed_adaptor_package(name, latest_version)
      when is_binary(name) and is_binary(latest_version) do
    seed_adaptor_package(name, [latest_version])
  end

  @doc """
  Build a record matching `t:Lightning.Adaptors.Strategy.adaptor_record/0`
  for use in `Mox.stub`/`Mox.expect` setups.
  """
  @spec build_strategy_adaptor_record(String.t(), String.t()) :: map()
  def build_strategy_adaptor_record(name, latest_version) do
    %{
      name: name,
      source: :npm,
      latest_version: latest_version,
      description: nil,
      homepage: nil,
      repository: nil,
      license: nil,
      deprecated: false,
      schema_data: nil,
      schema_sha256: nil,
      versions: [
        %{
          version: latest_version,
          integrity: "sha512-#{latest_version}",
          tarball_url: "https://example.com/x-#{latest_version}.tgz",
          size_bytes: 1024,
          dependencies: %{},
          peer_dependencies: %{},
          published_at: nil,
          deprecated: false
        }
      ]
    }
  end

  @doc """
  Seed the production `Lightning.Adaptors` supervisor's Cachex with a
  pre-built packages map. Useful for tests that exercise
  `AdaptorPicker.get_adaptor_version_options/1` under async mode — the
  picker calls `Lightning.Adaptors.packages/0` and (when the adaptor is
  known) `Lightning.Adaptors.versions/1`, both of which are routed
  through Cachex.

  Returns the supervisor source atom for convenience.
  """
  @spec warm_packages_cache([map()]) :: :npm | :local
  def warm_packages_cache(metas) when is_list(metas) do
    cache = AdaptorsSupervisor.cache_name(Lightning.Adaptors)
    source = AdaptorsSupervisor.source(Lightning.Adaptors)

    Cachex.put(cache, {:packages, source}, {:ok, metas})

    source
  end

  @doc """
  Bulk-seed the common `@openfn/*` packages used across the test suite
  with the versions that the legacy `adaptor_registry_cache.json`
  fixture used to publish.
  """
  @spec seed_common_packages() :: :ok
  def seed_common_packages do
    packages = [
      {"@openfn/language-common", ["1.6.2", "1.2.22", "1.1.0"]},
      {"@openfn/language-http", ["3.1.12", "2.0.0", "1.0.0"]},
      {"@openfn/language-postgresql", ["3.2.0", "2.0.0", "1.0.0"]},
      {"@openfn/language-dhis2", ["3.0.4", "2.0.0", "1.0.0"]},
      {"@openfn/language-salesforce", ["3.0.0", "2.0.0", "1.0.0"]},
      {"@openfn/language-godata", ["2.0.0", "1.0.0"]},
      {"@openfn/language-googlesheets", ["2.0.0", "1.0.0"]}
    ]

    Enum.each(packages, fn {name, versions} ->
      seed_adaptor_package(name, versions)
    end)

    # Warm Cachex for the production supervisor so reads from any
    # process (including the LiveView's caller chain) see the seeded
    # data without falling through to the Cachex Courier's
    # sandbox-blind DB query.
    cache = AdaptorsSupervisor.cache_name(Lightning.Adaptors)
    source = AdaptorsSupervisor.source(Lightning.Adaptors)

    metas =
      Enum.map(packages, fn {name, [latest | _]} ->
        %{
          name: name,
          latest_version: latest,
          description: nil,
          deprecated: false,
          icon_square_ext: nil,
          icon_rectangle_ext: nil,
          icon_square_sha256: nil,
          icon_rectangle_sha256: nil
        }
      end)

    Cachex.put(cache, {:packages, source}, {:ok, metas})

    Enum.each(packages, fn {name, versions} ->
      version_metas =
        Enum.map(versions, fn v ->
          %{
            version: v,
            integrity: "sha512-#{v}",
            size_bytes: 1024,
            published_at: nil,
            deprecated: false
          }
        end)

      Cachex.put(cache, {:versions, name, source}, {:ok, version_metas})
    end)

    :ok
  end
end
