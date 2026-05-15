defmodule Lightning.Adaptors.NPM.Tarball do
  @moduledoc """
  Per-package tarball client + icon matcher.

  Fetches a published npm tarball by its absolute URL (from the
  packument `dist.tarball` field), extracts it in-memory via
  `:erl_tar`, and matches `assets/square.*` / `assets/rectangle.*`
  paths for icon bytes.

  > **Deferred refactor**: per the smoke-test findings
  > (`~/projects/context/lightning/adaptors/01-phase-a-smoke-test-findings.md`
  > §Defect #2), icons are not actually present in published npm
  > tarballs — they live in the OpenFn monorepo on GitHub. The per-package
  > tarball flow is preserved here for now; a follow-up plan will replace
  > it with a `Lightning.Adaptors.NPM.GitHub` sub-module fed by a bulk
  > `c:fetch_icons/0` Strategy callback.
  """

  alias Lightning.Adaptors.Config

  @default_http_timeout :timer.seconds(30)

  @square_icon_pattern ~r{(?:^|/)assets/square\.(\w+)$}
  @rectangle_icon_pattern ~r{(?:^|/)assets/rectangle\.(\w+)$}

  @doc """
  Fetch and extract the tarball at `tarball_url`, returning hashes for
  any matching `assets/square.*` and `assets/rectangle.*` icons.

  Returns `{sq_ext, sq_sha, rect_ext, rect_sha}` as a 4-tuple of
  binary-or-nil. Any failure (nil URL, 5xx, malformed gzip) collapses
  to `{nil, nil, nil, nil}` — icon hashing is best-effort and must not
  fail the adaptor record assembly.
  """
  @spec icon_hashes(String.t() | nil) ::
          {String.t() | nil, binary() | nil, String.t() | nil, binary() | nil}
  def icon_hashes(nil), do: {nil, nil, nil, nil}

  def icon_hashes(tarball_url) do
    with {:ok, bytes} <- fetch_tarball(tarball_url),
         {:ok, entries} <- extract_tarball(bytes) do
      {sq_ext, sq_sha} = hash_icon(entries, :square)
      {rect_ext, rect_sha} = hash_icon(entries, :rectangle)
      {sq_ext, sq_sha, rect_ext, rect_sha}
    else
      _ -> {nil, nil, nil, nil}
    end
  end

  @doc """
  Fetch and extract the tarball at `tarball_url`, returning the bytes
  and extension for the requested icon `shape`.

  Surfaces tarball fetch failures (`{:error, term}`) and an explicit
  `{:error, :not_found}` when the tarball does not contain a matching
  icon path.
  """
  @spec fetch_icon(String.t(), :square | :rectangle) ::
          {:ok, %{data: binary(), ext: String.t()}}
          | {:error, :not_found}
          | {:error, term()}
  def fetch_icon(tarball_url, shape)
      when is_binary(tarball_url) and shape in [:square, :rectangle] do
    with {:ok, bytes} <- fetch_tarball(tarball_url),
         {:ok, entries} <- extract_tarball(bytes),
         {:ok, ext, body} <- find_icon_entry(entries, shape) do
      {:ok, %{data: body, ext: ext}}
    end
  end

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

  defp http_timeout do
    Config.strategy_opts(Lightning.Adaptors.NPM)[:http_timeout] ||
      @default_http_timeout
  end
end
