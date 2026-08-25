defmodule Lightning.Adaptors.NPM.Registry do
  @moduledoc """
  NPM registry HTTP client for `Lightning.Adaptors.NPM`.

  Talks to `registry.npmjs.org`. Responsible for the `search` endpoint
  used by `c:Lightning.Adaptors.Strategy.list_adaptors/0` and the
  `packument` endpoint used by `fetch_adaptor/1` and `fetch_icon/2`.

  Base URL via `Lightning.Adaptors.Config.strategy_opts(Lightning.Adaptors.NPM)[:registry_url]`,
  default `https://registry.npmjs.org`.

  Search results are filtered down to `@openfn/language-*` packages,
  matching the legacy `AdaptorRegistry` semantics; non-language packages
  in the `@openfn/` scope (e.g. `@openfn/cli`) are rejected.
  """

  alias Lightning.Adaptors.Config

  @default_registry_url "https://registry.npmjs.org"
  @default_http_timeout :timer.seconds(30)

  @search_scope "openfn"
  @search_size 250

  @language_prefix "@openfn/language-"

  @doc """
  Single `/-/v1/search` call returning `name + latest_version` for every
  `@openfn/language-*` package.
  """
  @spec list_adaptors() ::
          {:ok, [%{name: String.t(), latest_version: String.t()}]}
          | {:error, term()}
  def list_adaptors do
    case Tesla.get(json_client(), "/-/v1/search",
           query: [text: "@" <> @search_scope, size: @search_size]
         ) do
      {:ok, %Tesla.Env{status: 200, body: body}} when is_map(body) ->
        listing =
          body
          |> Map.get("objects", [])
          |> Enum.map(&extract_listing_entry/1)
          |> Enum.reject(&is_nil/1)

        {:ok, listing}

      {:ok, %Tesla.Env{status: status}} ->
        {:error, {:http_status, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Fetch the full packument for a package.
  """
  @spec get_packument(String.t()) ::
          {:ok, map()} | {:error, :not_found} | {:error, term()}
  def get_packument(name) do
    case Tesla.get(json_client(), "/" <> name) do
      {:ok, %Tesla.Env{status: 200, body: body}} when is_map(body) ->
        {:ok, body}

      {:ok, %Tesla.Env{status: 404}} ->
        {:error, :not_found}

      {:ok, %Tesla.Env{status: status}} ->
        {:error, {:http_status, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Extract the `dist-tags.latest` version from a packument.
  """
  @spec latest_version(map()) ::
          {:ok, String.t()} | {:error, :no_latest_version}
  def latest_version(packument) do
    case get_in(packument, ["dist-tags", "latest"]) do
      v when is_binary(v) -> {:ok, v}
      _ -> {:error, :no_latest_version}
    end
  end

  @doc """
  Resolve the tarball URL for `version` in `packument`.
  """
  @spec require_tarball_url(map(), String.t()) ::
          {:ok, String.t()} | {:error, :no_tarball_url}
  def require_tarball_url(packument, version) do
    case get_in(packument, ["versions", version, "dist", "tarball"]) do
      url when is_binary(url) -> {:ok, url}
      _ -> {:error, :no_tarball_url}
    end
  end

  @doc """
  Build the per-version `version_record` list from a packument.
  """
  @spec build_versions(map()) :: [map()]
  def build_versions(packument) do
    versions = Map.get(packument, "versions", %{})
    times = Map.get(packument, "time", %{})

    Enum.map(versions, fn {version, info} ->
      %{
        version: version,
        integrity: get_in(info, ["dist", "integrity"]),
        tarball_url: get_in(info, ["dist", "tarball"]),
        size_bytes: get_in(info, ["dist", "unpackedSize"]),
        dependencies: Map.get(info, "dependencies", %{}),
        peer_dependencies: Map.get(info, "peerDependencies", %{}),
        published_at: parse_time(Map.get(times, version)),
        deprecated: deprecated_marker?(info)
      }
    end)
  end

  @doc """
  Is the given `version` in `packument` flagged as deprecated?
  """
  @spec deprecated?(map(), String.t()) :: boolean()
  def deprecated?(packument, version) do
    deprecated_marker?(get_in(packument, ["versions", version]) || %{})
  end

  @doc """
  Normalise the packument's `repository` field to a plain URL string.
  """
  @spec repository_url(term()) :: String.t() | nil
  def repository_url(%{"url" => url}) when is_binary(url), do: url
  def repository_url(url) when is_binary(url), do: url
  def repository_url(_), do: nil

  defp extract_listing_entry(%{
         "package" => %{"name" => name, "version" => version}
       })
       when is_binary(name) and is_binary(version) do
    if String.starts_with?(name, @language_prefix) do
      %{name: name, latest_version: version}
    end
  end

  defp extract_listing_entry(_), do: nil

  defp deprecated_marker?(%{"deprecated" => v}) when is_binary(v) and v != "",
    do: true

  defp deprecated_marker?(%{"deprecated" => true}), do: true
  defp deprecated_marker?(_), do: false

  defp parse_time(time) when is_binary(time) do
    case DateTime.from_iso8601(time) do
      {:ok, dt, _offset} -> dt
      _ -> nil
    end
  end

  defp parse_time(_), do: nil

  defp json_client do
    build_client([
      {Tesla.Middleware.BaseUrl, registry_url()},
      Tesla.Middleware.JSON,
      Tesla.Middleware.FollowRedirects
    ])
  end

  defp build_client(middleware) do
    case Application.get_env(:tesla, :adapter) do
      {Tesla.Adapter.Finch, _opts} ->
        Tesla.client(
          middleware,
          {Tesla.Adapter.Finch,
           name: Lightning.Finch, receive_timeout: http_timeout()}
        )

      _other ->
        Tesla.client(middleware)
    end
  end

  defp registry_url do
    Config.strategy_opts(Lightning.Adaptors.NPM)[:registry_url] ||
      @default_registry_url
  end

  defp http_timeout do
    Config.strategy_opts(Lightning.Adaptors.NPM)[:http_timeout] ||
      @default_http_timeout
  end
end
