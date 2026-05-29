defmodule Lightning.Adaptors.NPM do
  @moduledoc """
  Production implementation of `Lightning.Adaptors.Strategy` that talks
  to the public NPM registry and the OpenFn adaptors monorepo on GitHub.

  Consolidates the legacy `Lightning.AdaptorRegistry`,
  `Mix.Tasks.Lightning.InstallSchemas`, and
  `Mix.Tasks.Lightning.InstallAdaptorIcons` into one stateless module:

    * `c:list_adaptors/0` — single search-API call returning
      `name + latest_version` for every `@openfn/language-*` package.
    * `c:fetch_adaptor/1` — packument fetch + per-version decode and
      latest-version schema retrieval via jsDelivr. Icon fields are
      **not** stamped here; the Scheduler joins them on after a bulk
      `c:fetch_icons/1` pass.
    * `c:fetch_icon/2` — single icon raw GET against
      `raw.githubusercontent.com`, used by the Store's rare lazy-miss
      fallback.
    * `c:fetch_icons/1` — bulk fan-out over the search listing, one
      HTTP request per `(name, shape)`. Threads `:prior_etags` from
      the caller down into the per-request `If-None-Match` headers.

  ## HTTP

  This module is a thin orchestrator. The actual HTTP work is delegated
  to three sub-modules, each of which owns its own Tesla client and
  upstream base URL:

    * `Lightning.Adaptors.NPM.Registry` — npm registry search + packument.
    * `Lightning.Adaptors.NPM.Schema` — jsDelivr `configuration-schema.json`.
    * `Lightning.Adaptors.NPM.GitHub` — `raw.githubusercontent.com`
      icon fetches (one GET per `(name, shape)`).

  Each sub-module issues at most a handful of single-shot Tesla requests
  bounded by `http_timeout`. No retry, no backoff, no circuit-breaker —
  transient failures (5xx, timeout, nxdomain) of the *primary* request
  (`packument` for `fetch_adaptor/1`, `search` for `list_adaptors/0` and
  `fetch_icons/1`) surface as `{:error, term()}` unchanged. Schema and
  icon fetches inside `fetch_adaptor/1` and `fetch_icons/1` are
  best-effort: a single icon miss degrades that entry to absence rather
  than failing the whole record.

  ## Configuration

  Each sub-module reads `:registry_url`, `:jsdelivr_url`, `:github_url`,
  `:github_ref`, and `:http_timeout` via
  `Lightning.Adaptors.Config.strategy_opts(__MODULE__)`, with defaults
  baked in so the module works even when no Application env block is
  set.
  """

  @behaviour Lightning.Adaptors.Strategy

  alias Lightning.Adaptors.NPM.GitHub
  alias Lightning.Adaptors.NPM.Registry
  alias Lightning.Adaptors.NPM.Schema

  @impl Lightning.Adaptors.Strategy
  def list_adaptors, do: Registry.list_adaptors()

  @impl Lightning.Adaptors.Strategy
  def fetch_adaptor(name) when is_binary(name) do
    with {:ok, packument} <- Registry.get_packument(name),
         {:ok, latest_version} <- Registry.latest_version(packument) do
      {schema_data, schema_sha} = Schema.schema(name, latest_version)

      {:ok,
       %{
         name: Map.get(packument, "name", name),
         description: Map.get(packument, "description"),
         homepage: Map.get(packument, "homepage"),
         repository: Registry.repository_url(Map.get(packument, "repository")),
         license: Map.get(packument, "license"),
         latest_version: latest_version,
         deprecated: Registry.deprecated?(packument, latest_version),
         schema_data: encode_schema(schema_data),
         schema_sha256: schema_sha,
         versions: Registry.build_versions(packument)
       }}
    end
  end

  # Strategy boundary: re-encode the decoded schema map to a JSON binary
  # so the row is persisted as text and `Jason.decode!(_,
  # objects: :ordered_objects)` re-engages downstream. NPM's upstream
  # Schema sub-module already decoded into a regular map, so field order
  # is whatever map iteration yields — the round-trip preserves it for
  # the Local strategy (raw binary in) and is a no-op for NPM data.
  defp encode_schema(nil), do: nil
  defp encode_schema(data) when is_binary(data), do: data
  defp encode_schema(data) when is_map(data), do: Jason.encode!(data)

  @impl Lightning.Adaptors.Strategy
  def fetch_icon(name, shape)
      when is_binary(name) and shape in [:square, :rectangle] do
    GitHub.fetch_one(name, shape)
  end

  @impl Lightning.Adaptors.Strategy
  def fetch_icons(opts \\ []) when is_list(opts) do
    prior_etags = Keyword.get(opts, :prior_etags, %{})

    with {:ok, listing} <- Registry.list_adaptors() do
      names = Enum.map(listing, & &1.name)
      GitHub.fetch_all(names, prior_etags)
    end
  end
end
