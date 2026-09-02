defmodule Lightning.AdaptorTestHelpers do
  @moduledoc """
  Seeds `Lightning.Adaptors.Catalogue` rows and manages the production
  `Lightning.Adaptors` cache for tests that read through it.

  The production cache outlives the SQL sandbox, so a test that seeds
  rows and reads them through the cache must clear it first.
  """

  import Lightning.Factories

  alias Lightning.Adaptors.Supervisor, as: AdaptorsSupervisor

  @doc """
  Seeds a throwaway adaptor row so the catalogue counts as loaded and
  saves do not wait on the production Scheduler.
  """
  @spec seed_ready_catalogue() :: :ok
  def seed_ready_catalogue do
    {:ok, _} =
      Lightning.Adaptors.Catalogue.upsert_adaptor(%{
        name: "@openfn/language-readiness-fixture",
        source: :npm,
        latest_version: "1.0.0",
        description: nil,
        homepage: nil,
        repository: nil,
        license: nil,
        deprecated: false,
        schema_data: nil,
        schema_sha256: nil,
        versions: []
      })

    :ok
  end

  @doc """
  Clears the production `Lightning.Adaptors` cache.
  """
  @spec clear_global_adaptors_cache() :: :ok
  def clear_global_adaptors_cache do
    cache = AdaptorsSupervisor.cache_name(Lightning.Adaptors)
    Cachex.clear(cache)
    :ok
  end

  @doc """
  Seeds the catalogue row an adaptor spec needs to pass
  `Lightning.Workflows.Job` validation, unless it is already there.
  """
  @spec ensure_adaptor(String.t()) :: :ok
  def ensure_adaptor(spec) when is_binary(spec) do
    case Lightning.Adaptors.parse_spec(spec) do
      {name, _version} when is_binary(name) ->
        source = AdaptorsSupervisor.source(Lightning.Adaptors)

        if is_nil(Lightning.Adaptors.Catalogue.get_adaptor(name, source)),
          do: insert(:adaptor, name: name)

        :ok

      _ ->
        raise ArgumentError, "not a well-formed adaptor spec: #{inspect(spec)}"
    end
  end

  @doc """
  Seeds a credential schema row keyed by short name (e.g. `"postgresql"`),
  reading the JSON body from `test/fixtures/schemas/<name>.json`.
  """
  @spec seed_credential_schema(String.t()) ::
          Lightning.Adaptors.Catalogue.Adaptor.t()
  def seed_credential_schema(short_name) when is_binary(short_name) do
    # Raw JSON binary, not a decoded map: `Credentials.Schema.new/2` decodes
    # it with ordered objects.
    schema_body =
      Path.join(["test", "fixtures", "schemas", "#{short_name}.json"])
      |> File.read!()

    row =
      insert(:adaptor, name: short_name, source: :npm, schema_data: schema_body)

    # Cachex fills run in its Courier process, which cannot see the sandbox
    # connection, so populate the cache directly.
    cache = AdaptorsSupervisor.cache_name(Lightning.Adaptors)
    source = AdaptorsSupervisor.source(Lightning.Adaptors)
    Cachex.put(cache, {:schema, short_name, source}, {:ok, schema_body})

    row
  end

  @doc """
  Seeds every credential schema present in `test/fixtures/schemas/`.
  """
  @spec seed_all_credential_schemas() :: :ok
  def seed_all_credential_schemas do
    metas =
      Path.wildcard("test/fixtures/schemas/*.json")
      |> Enum.reject(fn path -> File.stat!(path).size == 0 end)
      |> Enum.map(fn path ->
        short_name = path |> Path.basename(".json")
        row = seed_credential_schema(short_name)

        %{
          name: short_name,
          latest_version: row.latest_version,
          description: nil,
          deprecated: false,
          icon_square_ext: "png",
          icon_rectangle_ext: "png",
          icon_square_sha256: :crypto.hash(:sha256, short_name <> "-square"),
          icon_rectangle_sha256:
            :crypto.hash(:sha256, short_name <> "-rectangle")
        }
      end)

    cache = AdaptorsSupervisor.cache_name(Lightning.Adaptors)
    source = AdaptorsSupervisor.source(Lightning.Adaptors)
    Cachex.put(cache, {:packages, source}, {:ok, metas})

    :ok
  end

  @doc """
  Seeds an adaptor with one version so `@latest` resolves to it.
  """
  @spec seed_adaptor_package(String.t(), String.t()) ::
          Lightning.Adaptors.Catalogue.Adaptor.t()
  def seed_adaptor_package(name, latest_version)
      when is_binary(name) and is_binary(latest_version) do
    {:ok, row} =
      Lightning.Adaptors.Catalogue.upsert_adaptor(%{
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
      })

    row
  end
end
