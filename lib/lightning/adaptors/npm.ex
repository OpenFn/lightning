defmodule Lightning.Adaptors.NPM do
  @moduledoc """
  Production implementation of `Lightning.Adaptors.Strategy` that talks
  to the public NPM registry.

  Consolidates the legacy `Lightning.AdaptorRegistry`,
  `Mix.Tasks.Lightning.InstallSchemas`, and
  `Mix.Tasks.Lightning.InstallAdaptorIcons` into one stateless module:

    * `c:list_adaptors/0` — single search-API call returning
      `name + latest_version` for every `@openfn/*` package.
    * `c:fetch_adaptor/1` — packument fetch + per-version decode,
      latest-version schema retrieval via jsDelivr, and in-memory icon
      hashing from the tarball.
    * `c:fetch_icon/2` — pulls icon bytes from the latest version's
      tarball; no caching here, the Store owns disk persistence.

  ## HTTP

  Tesla + Finch on top of the already-supervised `Lightning.Finch`
  pool. Each callback issues at most a handful of single-shot Tesla
  requests bounded by `http_timeout`. No retry, no backoff, no
  circuit-breaker — transient failures (5xx, timeout, nxdomain) of
  the *primary* request (`packument` for `fetch_adaptor/1` and
  `fetch_icon/2`, `search` for `list_adaptors/0`) surface as
  `{:error, term()}` unchanged. Schema and tarball fetches inside
  `fetch_adaptor/1` are best-effort: a failure degrades the affected
  field to `nil` rather than failing the whole record (matches the
  `Local` strategy's behaviour for missing files).

  ## Configuration

  Reads `:registry_url` and `:http_timeout` via
  `Lightning.Adaptors.Config.strategy_opts(__MODULE__)`, with the
  defaults from §5.1 of the design doc baked in here so the module
  works even when no Application env block is set. `:max_concurrency`
  is reserved by §5.1 for cross-invocation cold-miss capping at the
  Store layer; it is intentionally not consumed inside a single
  `fetch_adaptor/1` call (see PRD §10 #19).
  """

  @behaviour Lightning.Adaptors.Strategy

  alias Lightning.Adaptors.Config

  @default_registry_url "https://registry.npmjs.org"
  @default_http_timeout :timer.seconds(30)

  @jsdelivr_base "https://cdn.jsdelivr.net"

  @search_scope "openfn"
  @search_size 250

  @square_icon_pattern ~r{(?:^|/)assets/square\.(\w+)$}
  @rectangle_icon_pattern ~r{(?:^|/)assets/rectangle\.(\w+)$}

  @impl Lightning.Adaptors.Strategy
  def list_adaptors do
    case Tesla.get(json_client(), "/-/v1/search",
           query: [text: "scope:" <> @search_scope, size: @search_size]
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

  @impl Lightning.Adaptors.Strategy
  def fetch_adaptor(name) when is_binary(name) do
    with {:ok, packument} <- get_packument(name),
         {:ok, latest_version} <- latest_version(packument) do
      tarball_url =
        get_in(packument, ["versions", latest_version, "dist", "tarball"])

      {sq_ext, sq_sha, rect_ext, rect_sha} = icon_hashes(tarball_url)
      {schema_data, schema_sha} = schema(name, latest_version)

      {:ok,
       %{
         name: Map.get(packument, "name", name),
         description: Map.get(packument, "description"),
         homepage: Map.get(packument, "homepage"),
         repository: repository_url(Map.get(packument, "repository")),
         license: Map.get(packument, "license"),
         latest_version: latest_version,
         deprecated: deprecated?(packument, latest_version),
         schema_data: schema_data,
         schema_sha256: schema_sha,
         icon_square_ext: sq_ext,
         icon_rectangle_ext: rect_ext,
         icon_square_sha256: sq_sha,
         icon_rectangle_sha256: rect_sha,
         versions: build_versions(packument)
       }}
    end
  end

  @impl Lightning.Adaptors.Strategy
  def fetch_icon(name, shape)
      when is_binary(name) and shape in [:square, :rectangle] do
    with {:ok, packument} <- get_packument(name),
         {:ok, latest_version} <- latest_version(packument),
         {:ok, url} <- require_tarball_url(packument, latest_version),
         {:ok, tarball} <- fetch_tarball(url),
         {:ok, entries} <- extract_tarball(tarball),
         {:ok, ext, body} <- find_icon_entry(entries, shape) do
      {:ok, %{data: body, ext: ext}}
    end
  end

  # ==================== Packument & search ====================

  defp get_packument(name) do
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

  defp latest_version(packument) do
    case get_in(packument, ["dist-tags", "latest"]) do
      v when is_binary(v) -> {:ok, v}
      _ -> {:error, :no_latest_version}
    end
  end

  defp require_tarball_url(packument, version) do
    case get_in(packument, ["versions", version, "dist", "tarball"]) do
      url when is_binary(url) -> {:ok, url}
      _ -> {:error, :no_tarball_url}
    end
  end

  defp extract_listing_entry(%{
         "package" => %{"name" => name, "version" => version}
       })
       when is_binary(name) and is_binary(version) do
    %{name: name, latest_version: version}
  end

  defp extract_listing_entry(_), do: nil

  defp build_versions(packument) do
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

  defp deprecated?(packument, version) do
    deprecated_marker?(get_in(packument, ["versions", version]) || %{})
  end

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

  defp repository_url(%{"url" => url}) when is_binary(url), do: url
  defp repository_url(url) when is_binary(url), do: url
  defp repository_url(_), do: nil

  # ==================== Schema (jsDelivr) ====================

  defp schema(name, version) do
    with {:ok, body} <- fetch_schema_bytes(name, version),
         {:ok, data} <- Jason.decode(body) do
      sha = :sha256 |> :crypto.hash(body) |> Base.encode16(case: :lower)
      {data, sha}
    else
      _ -> {nil, nil}
    end
  end

  defp fetch_schema_bytes(name, version) do
    url = "/npm/#{name}@#{version}/configuration-schema.json"

    case Tesla.get(jsdelivr_client(), url) do
      {:ok, %Tesla.Env{status: 200, body: body}} when is_binary(body) ->
        {:ok, body}

      {:ok, %Tesla.Env{status: status}} ->
        {:error, {:http_status, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ==================== Icons & tarball ====================

  defp icon_hashes(nil), do: {nil, nil, nil, nil}

  defp icon_hashes(tarball_url) do
    with {:ok, bytes} <- fetch_tarball(tarball_url),
         {:ok, entries} <- extract_tarball(bytes) do
      {sq_ext, sq_sha} = hash_icon(entries, :square)
      {rect_ext, rect_sha} = hash_icon(entries, :rectangle)
      {sq_ext, sq_sha, rect_ext, rect_sha}
    else
      _ -> {nil, nil, nil, nil}
    end
  end

  defp hash_icon(entries, shape) do
    pattern = icon_path_pattern(shape)

    Enum.find_value(entries, {nil, nil}, fn {path, body} ->
      case Regex.run(pattern, to_string(path)) do
        [_, ext] -> {ext, :crypto.hash(:sha256, body)}
        _ -> nil
      end
    end)
  end

  defp find_icon_entry(entries, shape) do
    pattern = icon_path_pattern(shape)

    Enum.find_value(entries, {:error, :not_found}, fn {path, body} ->
      case Regex.run(pattern, to_string(path)) do
        [_, ext] -> {:ok, ext, body}
        _ -> nil
      end
    end)
  end

  defp icon_path_pattern(:square), do: @square_icon_pattern
  defp icon_path_pattern(:rectangle), do: @rectangle_icon_pattern

  defp fetch_tarball(url) do
    case Tesla.get(raw_client(), url) do
      {:ok, %Tesla.Env{status: 200, body: body}} when is_binary(body) ->
        {:ok, body}

      {:ok, %Tesla.Env{status: status}} ->
        {:error, {:http_status, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp extract_tarball(bytes) do
    case :erl_tar.extract({:binary, bytes}, [:memory, :compressed]) do
      {:ok, entries} -> {:ok, entries}
      :ok -> {:ok, []}
      {:error, reason} -> {:error, reason}
    end
  end

  # ==================== HTTP clients ====================

  defp json_client do
    build_client([
      {Tesla.Middleware.BaseUrl, registry_url()},
      Tesla.Middleware.JSON,
      Tesla.Middleware.FollowRedirects
    ])
  end

  defp jsdelivr_client do
    build_client([
      {Tesla.Middleware.BaseUrl, @jsdelivr_base},
      Tesla.Middleware.FollowRedirects
    ])
  end

  defp raw_client do
    build_client([Tesla.Middleware.FollowRedirects])
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
    Config.strategy_opts(__MODULE__)[:registry_url] || @default_registry_url
  end

  defp http_timeout do
    Config.strategy_opts(__MODULE__)[:http_timeout] || @default_http_timeout
  end
end
