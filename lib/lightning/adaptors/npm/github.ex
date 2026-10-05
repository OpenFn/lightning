defmodule Lightning.Adaptors.NPM.GitHub do
  @moduledoc """
  Raw `raw.githubusercontent.com` client for adaptor icons.

  Icons are not published inside npm tarballs. They live in the
  `OpenFn/adaptors` monorepo, so this module fetches them from the raw
  GitHub content host, one icon per GET.

  ## URL pattern

      <github_url>/OpenFn/adaptors/<github_ref>/packages/<name-suffix>/assets/<shape>.<ext>

  where `<name-suffix>` strips the `@openfn/` scope and, when present, the
  `language-` prefix too, so `@openfn/language-common` becomes `common`,
  matching the monorepo's `packages/` directory names. Each `(name,
  shape)` is probed `png` first then `svg`, the same order
  `Lightning.Adaptors.Local` uses.

  ## Configuration

  `:github_url` (default `https://raw.githubusercontent.com`) and
  `:github_ref` (default `main`) come from
  `Lightning.Adaptors.Config.strategy_opts(Lightning.Adaptors.NPM)`.
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

  Tries `png` then `svg`. No conditional GET, since the Store calls this
  when an icon is missing on disk and has no prior etag. Returns:

    * `{:ok, %{data: binary(), ext: String.t(), etag: String.t() | nil}}`
      on success.
    * `{:error, :not_found}` when neither ext yields a 200.
    * `{:error, term()}` on transport-level failure (timeout, nxdomain).
  """
  @spec fetch_one(String.t(), :square | :rectangle) ::
          {:ok, %{data: binary(), ext: String.t(), etag: String.t() | nil}}
          | {:error, :not_found | term()}
  def fetch_one(name, shape)
      when is_binary(name) and shape in [:square, :rectangle] do
    client = raw_client()
    do_fetch_one(client, name, shape, nil)
  end

  @doc """
  Fetch icons for every `(name, shape)` pair across `names`.

  Returns `{:ok, map}` keyed by package name, each holding zero, one or
  two shape keys. A missing shape is not an error. It means upstream had
  no such icon, or the fetch for that pair failed, which is only logged.

  `prior_etags` is `%{name => %{shape => etag}}`. Each etag is sent as
  `If-None-Match` for its `(name, shape)`, and a 304 comes back as
  `:not_modified` in that shape's slot.
  """
  @spec fetch_all([String.t()], %{
          optional(String.t()) => %{
            optional(:square) => String.t(),
            optional(:rectangle) => String.t()
          }
        }) ::
          {:ok,
           %{
             required(String.t()) => %{
               optional(:square) =>
                 %{
                   data: binary(),
                   ext: String.t(),
                   sha256: binary(),
                   etag: String.t() | nil
                 }
                 | :not_modified,
               optional(:rectangle) =>
                 %{
                   data: binary(),
                   ext: String.t(),
                   sha256: binary(),
                   etag: String.t() | nil
                 }
                 | :not_modified
             }
           }}
  def fetch_all(names, prior_etags)
      when is_list(names) and is_map(prior_etags) do
    client = raw_client()

    work =
      for name <- names, shape <- [:square, :rectangle], do: {name, shape}

    {results, counts} =
      work
      |> Task.async_stream(
        fn {name, shape} ->
          prior = prior_etag_for(prior_etags, name, shape)

          case do_fetch_one(client, name, shape, prior) do
            {:ok, %{data: bytes, ext: ext, etag: etag}} ->
              {name, shape,
               {:ok,
                %{
                  data: bytes,
                  ext: ext,
                  sha256: :crypto.hash(:sha256, bytes),
                  etag: etag
                }}}

            :not_modified ->
              {name, shape, :not_modified}

            {:error, reason} ->
              {name, shape, {:error, reason}}
          end
        end,
        max_concurrency: max_concurrency(),
        timeout: max(http_timeout() * 2, 5_000),
        on_timeout: :kill_task,
        ordered: false
      )
      |> Enum.reduce(
        {%{}, %{fetched: 0, not_modified: 0, not_found: 0, error: 0}},
        fn
          {:ok, {name, shape, {:ok, entry}}}, {acc, c} ->
            {put_entry(acc, name, shape, entry),
             Map.update!(c, :fetched, &(&1 + 1))}

          {:ok, {name, shape, :not_modified}}, {acc, c} ->
            {put_entry(acc, name, shape, :not_modified),
             Map.update!(c, :not_modified, &(&1 + 1))}

          {:ok, {_name, _shape, {:error, :not_found}}}, {acc, c} ->
            {acc, Map.update!(c, :not_found, &(&1 + 1))}

          {:ok, {_name, _shape, {:error, _reason}}}, {acc, c} ->
            {acc, Map.update!(c, :error, &(&1 + 1))}

          {:exit, _reason}, {acc, c} ->
            {acc, Map.update!(c, :error, &(&1 + 1))}
        end
      )

    Logger.info(
      "NPM.GitHub: fetch_all names=#{length(names)} pairs=#{length(work)} " <>
        "fetched=#{counts.fetched} not_modified=#{counts.not_modified} " <>
        "not_found=#{counts.not_found} errors=#{counts.error}"
    )

    {:ok, results}
  end

  defp prior_etag_for(prior_etags, name, shape) do
    case Map.get(prior_etags, name) do
      %{} = shapes -> Map.get(shapes, shape)
      _ -> nil
    end
  end

  defp put_entry(acc, name, shape, entry) do
    Map.update(acc, name, %{shape => entry}, &Map.put(&1, shape, entry))
  end

  # GitHub raw doesn't compress PNG/SVG responses, so the sha256 computed
  # in fetch_all/2 is over the exact bytes served. If that ever changes,
  # this needs a decompress middleware to keep the checksum correct.
  defp do_fetch_one(client, name, shape, prior_etag) do
    suffix = strip_scope(name)
    cond_get? = is_binary(prior_etag)

    headers =
      if cond_get?, do: [{"if-none-match", prior_etag}], else: []

    Enum.reduce_while(@icon_exts, {:error, :not_found}, fn ext, _acc ->
      path = build_path(suffix, shape, ext)

      case Tesla.get(client, path, headers: headers) do
        {:ok, %Tesla.Env{status: 200, body: body} = env} when is_binary(body) ->
          etag = response_etag(env)

          Logger.debug(fn ->
            "NPM.GitHub: GET #{path} → 200 (#{byte_size(body)}B) " <>
              "name=#{name} shape=#{shape} cond_get=#{cond_get?}"
          end)

          {:halt, {:ok, %{data: body, ext: ext, etag: etag}}}

        {:ok, %Tesla.Env{status: 304}} ->
          Logger.debug(fn ->
            "NPM.GitHub: GET #{path} → 304 name=#{name} shape=#{shape} " <>
              "cond_get=#{cond_get?}"
          end)

          {:halt, :not_modified}

        {:ok, %Tesla.Env{status: 404}} ->
          Logger.debug(fn ->
            "NPM.GitHub: GET #{path} → 404 name=#{name} shape=#{shape} " <>
              "cond_get=#{cond_get?}"
          end)

          {:cont, {:error, :not_found}}

        {:ok, %Tesla.Env{status: status}} ->
          Logger.debug(fn ->
            "NPM.GitHub: GET #{path} → #{status} name=#{name} shape=#{shape} " <>
              "cond_get=#{cond_get?}"
          end)

          {:halt, {:error, {:http_status, status}}}

        {:error, reason} ->
          Logger.debug(fn ->
            "NPM.GitHub: GET #{path} → transport error #{inspect(reason)} " <>
              "name=#{name} shape=#{shape} cond_get=#{cond_get?}"
          end)

          {:halt, {:error, reason}}
      end
    end)
  end

  defp response_etag(%Tesla.Env{headers: headers}) do
    Enum.find_value(headers, fn {k, v} ->
      if is_binary(k) and String.downcase(k) == "etag", do: v
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
