defmodule Lightning.Adaptors.NPM do
  @moduledoc """
  Production implementation of `Lightning.Adaptors.Strategy` that talks
  to the public NPM registry and the OpenFn adaptors monorepo on GitHub.

    * `c:Lightning.Adaptors.Strategy.list_adaptors/0` merges the
      `@openfn` org's package listing with the search API's version
      lookup. See `Lightning.Adaptors.NPM.Registry` for why this is two
      calls, not one. A listing with no `@openfn/language-*` names is an
      error, not an empty catalogue.
    * `c:Lightning.Adaptors.Strategy.fetch_adaptor/1` fetches the
      packument and the latest version's schema from jsDelivr. Icon
      fields are not stamped here. The Scheduler joins them on after a
      bulk `c:Lightning.Adaptors.Strategy.fetch_icons/1` pass.
    * `c:Lightning.Adaptors.Strategy.fetch_icon/2` is a single raw GET
      against `raw.githubusercontent.com`, used when the Store misses an
      icon on disk.
    * `c:Lightning.Adaptors.Strategy.fetch_icons/1` fans out one GET per
      `(name, shape)` and sends `:prior_etags` as `If-None-Match`.

  ## HTTP

  The HTTP work lives in three sub-modules, each with its own Tesla
  client and base URL: `Lightning.Adaptors.NPM.Registry`,
  `Lightning.Adaptors.NPM.Schema` and `Lightning.Adaptors.NPM.GitHub`.

  Every request is single-shot and bounded by `http_timeout`. There is no
  retry, backoff or circuit breaker. A transient failure (5xx, timeout,
  nxdomain) of the primary request (the packument for `fetch_adaptor/1`,
  the org listing for `list_adaptors/0` and `fetch_icons/1`) surfaces as
  `{:error, term()}` unchanged, and a failed schema fetch inside
  `fetch_adaptor/1` as
  `{:error, {:schema_fetch_failed, reason}}`. Icon fetches inside
  `fetch_icons/1` are best-effort instead: a miss degrades to an absent
  icon shape rather than failing the batch.

  ## Configuration

  The sub-modules read `:registry_url`, `:jsdelivr_url`, `:github_url`,
  `:github_ref` and `:http_timeout` from
  `Lightning.Adaptors.Config.strategy_opts(Lightning.Adaptors.NPM)`. All
  three share this module's config key rather than having their own, and
  each key has a default so the module works with no Application env set.
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
         {:ok, latest_version} <- Registry.latest_version(packument),
         {:ok, {schema_data, schema_sha256}} <-
           schema(name, latest_version) do
      {:ok,
       %{
         name: Map.get(packument, "name", name),
         description: Map.get(packument, "description"),
         homepage: Map.get(packument, "homepage"),
         repository: Registry.repository_url(Map.get(packument, "repository")),
         license: Map.get(packument, "license"),
         latest_version: latest_version,
         deprecated: Registry.deprecated?(packument, latest_version),
         versions: Registry.build_versions(packument),
         schema_data: schema_data,
         schema_sha256: schema_sha256
       }}
    end
  end

  defp schema(name, version) do
    case Schema.schema(name, version) do
      {:ok, pair} -> {:ok, pair}
      {:error, reason} -> {:error, {:schema_fetch_failed, reason}}
    end
  end

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
