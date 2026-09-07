defmodule Lightning.Adaptors.NPM do
  @moduledoc """
  Production implementation of `Lightning.Adaptors.Strategy` that talks
  to the public NPM registry and the OpenFn adaptors monorepo on GitHub.

  Implements the four `Lightning.Adaptors.Strategy` callbacks:

    * `c:Lightning.Adaptors.Strategy.list_adaptors/0` — merges the
      `@openfn` org's authoritative package listing with the search API's
      cheap version lookup, returning `name + latest_version` for every
      `@openfn/language-*` package. See
      `Lightning.Adaptors.NPM.Registry` for why this is two calls, not
      one.
    * `c:Lightning.Adaptors.Strategy.fetch_adaptor/1` — packument fetch +
      per-version decode and latest-version schema retrieval via
      jsDelivr. Icon fields are **not** stamped here; the Scheduler
      joins them on after a bulk
      `c:Lightning.Adaptors.Strategy.fetch_icons/1` pass.
    * `c:Lightning.Adaptors.Strategy.fetch_icon/2` — single icon raw GET
      against `raw.githubusercontent.com`, used by the Store's rare
      lazy-miss fallback.
    * `c:Lightning.Adaptors.Strategy.fetch_icons/1` — bulk fan-out over
      the adaptor listing, one HTTP request per `(name, shape)`. Threads
      `:prior_etags` from the caller down into the per-request
      `If-None-Match` headers.

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
  (`packument` for `fetch_adaptor/1`, the org package listing for
  `list_adaptors/0` and `fetch_icons/1`) surface as `{:error, term()}`
  unchanged. The schema fetch inside `fetch_adaptor/1` and each icon
  fetch inside `fetch_icons/1` are best-effort instead: a miss there
  degrades to a nil schema or an absent icon shape, rather than failing
  the whole record or batch.

  ## Configuration

  Each sub-module reads `:registry_url`, `:jsdelivr_url`, `:github_url`,
  `:github_ref`, and `:http_timeout` via
  `Lightning.Adaptors.Config.strategy_opts(Lightning.Adaptors.NPM)` — all
  three share this module's own config key rather than each having their
  own — with defaults baked in so the module works even when no
  Application env block is set.
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
      base = %{
        name: Map.get(packument, "name", name),
        description: Map.get(packument, "description"),
        homepage: Map.get(packument, "homepage"),
        repository: Registry.repository_url(Map.get(packument, "repository")),
        license: Map.get(packument, "license"),
        latest_version: latest_version,
        deprecated: Registry.deprecated?(packument, latest_version),
        versions: Registry.build_versions(packument)
      }

      {:ok, put_schema(base, Schema.schema(name, latest_version))}
    end
  end

  # A transient schema-fetch failure must leave `schema_data`/`schema_sha256`
  # absent from the record entirely, not merely `nil` — `Ecto.Changeset.cast/3`
  # overwrites a column whenever its key is present in `attrs`, even with a
  # nil value, so an absent key is the only way to signal "leave the
  # previously-persisted schema untouched."
  defp put_schema(record, {nil, :fetch_failed}), do: record

  defp put_schema(record, {schema_data, schema_sha}) do
    record
    |> Map.put(:schema_data, encode_schema(schema_data))
    |> Map.put(:schema_sha256, schema_sha)
  end

  # Strategy boundary: re-encode the decoded schema map to a JSON binary
  # so the row is persisted as text and `Jason.decode!(_,
  # objects: :ordered_objects)` re-engages downstream. `Schema.schema/2`
  # always decodes via `Jason.decode/1`, so `data` is a map (or nil) here,
  # never a raw binary — the Local strategy's own raw-binary schema text
  # takes a separate path (`Local.read_schema/1`) and never reaches this
  # function.
  defp encode_schema(nil), do: nil
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
