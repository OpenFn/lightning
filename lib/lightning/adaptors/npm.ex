defmodule Lightning.Adaptors.NPM do
  @moduledoc """
  Production implementation of `Lightning.Adaptors.Strategy` that talks
  to the public NPM registry.

  Consolidates the legacy `Lightning.AdaptorRegistry`,
  `Mix.Tasks.Lightning.InstallSchemas`, and
  `Mix.Tasks.Lightning.InstallAdaptorIcons` into one stateless module:

    * `c:list_adaptors/0` — single search-API call returning
      `name + latest_version` for every `@openfn/language-*` package.
    * `c:fetch_adaptor/1` — packument fetch + per-version decode,
      latest-version schema retrieval via jsDelivr, and in-memory icon
      hashing from the tarball.
    * `c:fetch_icon/2` — pulls icon bytes from the latest version's
      tarball; no caching here, the Store owns disk persistence.

  ## HTTP

  This module is a thin orchestrator. The actual HTTP work is delegated
  to three sub-modules, each of which owns its own Tesla client and
  upstream base URL:

    * `Lightning.Adaptors.NPM.Registry` — npm registry search + packument.
    * `Lightning.Adaptors.NPM.Schema` — jsDelivr `configuration-schema.json`.
    * `Lightning.Adaptors.NPM.Tarball` — per-package tarball fetch + icon
      extraction.

  Each sub-module issues at most a handful of single-shot Tesla requests
  bounded by `http_timeout`. No retry, no backoff, no circuit-breaker —
  transient failures (5xx, timeout, nxdomain) of the *primary* request
  (`packument` for `fetch_adaptor/1` and `fetch_icon/2`, `search` for
  `list_adaptors/0`) surface as `{:error, term()}` unchanged. Schema and
  tarball fetches inside `fetch_adaptor/1` are best-effort: a failure
  degrades the affected field to `nil` rather than failing the whole
  record (matches the `Local` strategy's behaviour for missing files).

  ## Configuration

  Each sub-module reads `:registry_url`, `:jsdelivr_url`, and
  `:http_timeout` via `Lightning.Adaptors.Config.strategy_opts(__MODULE__)`,
  with defaults baked in so the module works even when no Application env
  block is set. `:max_concurrency` is reserved by §5.1 for cross-invocation
  cold-miss capping at the Store layer; it is intentionally not consumed
  inside a single `fetch_adaptor/1` call (see PRD §10 #19).
  """

  @behaviour Lightning.Adaptors.Strategy

  alias Lightning.Adaptors.NPM.Registry
  alias Lightning.Adaptors.NPM.Schema
  alias Lightning.Adaptors.NPM.Tarball

  @impl Lightning.Adaptors.Strategy
  def list_adaptors, do: Registry.list_adaptors()

  @impl Lightning.Adaptors.Strategy
  def fetch_adaptor(name) when is_binary(name) do
    with {:ok, packument} <- Registry.get_packument(name),
         {:ok, latest_version} <- Registry.latest_version(packument) do
      tarball_url =
        get_in(packument, ["versions", latest_version, "dist", "tarball"])

      {sq_ext, sq_sha, rect_ext, rect_sha} = Tarball.icon_hashes(tarball_url)
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
         schema_data: schema_data,
         schema_sha256: schema_sha,
         icon_square_ext: sq_ext,
         icon_rectangle_ext: rect_ext,
         icon_square_sha256: sq_sha,
         icon_rectangle_sha256: rect_sha,
         versions: Registry.build_versions(packument)
       }}
    end
  end

  @impl Lightning.Adaptors.Strategy
  def fetch_icon(name, shape)
      when is_binary(name) and shape in [:square, :rectangle] do
    with {:ok, packument} <- Registry.get_packument(name),
         {:ok, latest_version} <- Registry.latest_version(packument),
         {:ok, url} <- Registry.require_tarball_url(packument, latest_version) do
      Tarball.fetch_icon(url, shape)
    end
  end
end
