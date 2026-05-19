defmodule Lightning.Adaptors.NPM.GitHub do
  @moduledoc """
  Raw `raw.githubusercontent.com` client for adaptor icons.

  Icons aren't published inside npm tarballs — they live in the
  `OpenFn/adaptors` monorepo. This module fetches them directly via the
  raw GitHub content host, one icon per HTTP GET, no tarball walking.

  ## URL pattern

      <github_url>/OpenFn/adaptors/<github_ref>/packages/<name-suffix>/assets/<shape>.<ext>

  where `<name-suffix>` strips the `@openfn/` scope from the package name.
  Each `(name, shape)` is probed `png` first then `svg` — matching the
  ext order used by `Lightning.Adaptors.Local`.

  ## Configuration

  Both `:github_url` (default `https://raw.githubusercontent.com`) and
  `:github_ref` (default `main`) are read via
  `Lightning.Adaptors.Config.strategy_opts(Lightning.Adaptors.NPM)`,
  symmetric with the existing `:registry_url`, `:jsdelivr_url`, and
  `:http_timeout` keys.
  """

  alias Lightning.Adaptors.Config

  require Logger

  @default_github_url "https://raw.githubusercontent.com"
  @default_github_ref "main"
  @default_http_timeout :timer.seconds(30)

  @default_max_concurrency 20

  @icon_exts ~w(png svg)
  @scope_prefix "@openfn/"
  @language_prefix "language-"

  @doc """
  Fetch a single icon for `(name, shape)`.

  Tries `png` then `svg`. Returns:

    * `{:ok, %{data: binary(), ext: String.t()}}` on success.
    * `{:error, :not_found}` when neither ext yields a 200.
    * `{:error, term()}` on transport-level failure (timeout, nxdomain).
  """
  @spec fetch_one(String.t(), :square | :rectangle) ::
          {:ok, %{data: binary(), ext: String.t()}}
          | {:error, :not_found | term()}
  def fetch_one(name, shape)
      when is_binary(name) and shape in [:square, :rectangle] do
    client = raw_client()
    do_fetch_one(client, name, shape)
  end

  @doc """
  Fetch icons for every `(name, shape)` pair across `names`.

  Returns `{:ok, partial_map}` where each entry is keyed by the
  package name and contains zero, one, or two shape keys. Absence
  is **not** an error — packages with no upstream icon simply do not
  appear (or appear with a missing shape).

  Fans out via `Task.async_stream` with a bounded concurrency. Transport
  failures for a single `(name, shape)` are dropped silently — the whole
  pipeline only fails if every fetch crashes the supervisor, which is
  not surfaced here.
  """
  @spec fetch_all([String.t()]) ::
          {:ok,
           %{
             required(String.t()) => %{
               optional(:square) => %{
                 data: binary(),
                 ext: String.t(),
                 sha256: binary()
               },
               optional(:rectangle) => %{
                 data: binary(),
                 ext: String.t(),
                 sha256: binary()
               }
             }
           }}
  def fetch_all(names) when is_list(names) do
    client = raw_client()

    work =
      for name <- names, shape <- [:square, :rectangle], do: {name, shape}

    {results, counts} =
      work
      |> Task.async_stream(
        fn {name, shape} ->
          case do_fetch_one(client, name, shape) do
            {:ok, %{data: bytes, ext: ext}} ->
              {name, shape,
               {:ok,
                %{
                  data: bytes,
                  ext: ext,
                  sha256: :crypto.hash(:sha256, bytes)
                }}}

            {:error, reason} ->
              {name, shape, {:error, reason}}
          end
        end,
        max_concurrency: max_concurrency(),
        timeout: max(http_timeout() * 2, 5_000),
        on_timeout: :kill_task,
        ordered: false
      )
      |> Enum.reduce({%{}, %{ok: 0, not_found: 0, error: 0}}, fn
        {:ok, {name, shape, {:ok, entry}}}, {acc, c} ->
          {put_entry(acc, name, shape, entry), Map.update!(c, :ok, &(&1 + 1))}

        {:ok, {_name, _shape, {:error, :not_found}}}, {acc, c} ->
          {acc, Map.update!(c, :not_found, &(&1 + 1))}

        {:ok, {_name, _shape, {:error, _reason}}}, {acc, c} ->
          {acc, Map.update!(c, :error, &(&1 + 1))}

        {:exit, _reason}, {acc, c} ->
          {acc, Map.update!(c, :error, &(&1 + 1))}
      end)

    Logger.info(
      "NPM.GitHub: fetch_all names=#{length(names)} pairs=#{length(work)} " <>
        "ok=#{counts.ok} not_found=#{counts.not_found} errors=#{counts.error}"
    )

    {:ok, results}
  end

  defp put_entry(acc, name, shape, entry) do
    Map.update(acc, name, %{shape => entry}, &Map.put(&1, shape, entry))
  end

  defp do_fetch_one(client, name, shape) do
    suffix = strip_scope(name)

    Enum.reduce_while(@icon_exts, {:error, :not_found}, fn ext, _acc ->
      path = build_path(suffix, shape, ext)

      case Tesla.get(client, path) do
        {:ok, %Tesla.Env{status: 200, body: body}} when is_binary(body) ->
          Logger.debug(fn ->
            "NPM.GitHub: GET #{path} → 200 (#{byte_size(body)}B) " <>
              "name=#{name} shape=#{shape}"
          end)

          {:halt, {:ok, %{data: body, ext: ext}}}

        {:ok, %Tesla.Env{status: 404}} ->
          Logger.debug(fn ->
            "NPM.GitHub: GET #{path} → 404 name=#{name} shape=#{shape}"
          end)

          {:cont, {:error, :not_found}}

        {:ok, %Tesla.Env{status: status}} ->
          Logger.debug(fn ->
            "NPM.GitHub: GET #{path} → #{status} name=#{name} shape=#{shape}"
          end)

          {:halt, {:error, {:http_status, status}}}

        {:error, reason} ->
          Logger.debug(fn ->
            "NPM.GitHub: GET #{path} → transport error #{inspect(reason)} " <>
              "name=#{name} shape=#{shape}"
          end)

          {:halt, {:error, reason}}
      end
    end)
  end

  defp build_path(name_suffix, shape, ext) do
    "/OpenFn/adaptors/#{github_ref()}/packages/#{name_suffix}/assets/#{shape}.#{ext}"
  end

  defp strip_scope(@scope_prefix <> @language_prefix <> rest), do: rest
  defp strip_scope(@scope_prefix <> rest), do: rest
  defp strip_scope(name), do: name

  defp raw_client do
    build_client([
      {Tesla.Middleware.BaseUrl, github_url()},
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

  defp github_url do
    Config.strategy_opts(Lightning.Adaptors.NPM)[:github_url] ||
      @default_github_url
  end

  defp github_ref do
    Config.strategy_opts(Lightning.Adaptors.NPM)[:github_ref] ||
      @default_github_ref
  end

  defp http_timeout do
    Config.strategy_opts(Lightning.Adaptors.NPM)[:http_timeout] ||
      @default_http_timeout
  end

  defp max_concurrency do
    Config.strategy_opts(Lightning.Adaptors.NPM)[:icon_max_concurrency] ||
      @default_max_concurrency
  end
end
