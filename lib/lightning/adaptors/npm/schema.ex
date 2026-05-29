defmodule Lightning.Adaptors.NPM.Schema do
  @moduledoc """
  jsDelivr CDN client for adaptor configuration schemas.

  Fetches `/npm/<name>@<version>/configuration-schema.json` from
  `cdn.jsdelivr.net`, decodes it, and returns
  `{schema_data, schema_sha256}` (or `{nil, nil}` on any failure —
  schema fetch is best-effort).

  Base URL via `Lightning.Adaptors.Config.strategy_opts(Lightning.Adaptors.NPM)[:jsdelivr_url]`,
  default `https://cdn.jsdelivr.net`.
  """

  alias Lightning.Adaptors.Config

  @default_jsdelivr_url "https://cdn.jsdelivr.net"
  @default_http_timeout :timer.seconds(30)

  @doc """
  Fetch the configuration schema for `name@version` from jsDelivr.

  Returns `{schema_data, schema_sha256}` on success, `{nil, nil}` on
  any failure (best-effort — schema absence must not fail the adaptor
  record assembly).
  """
  @spec schema(String.t(), String.t()) ::
          {map() | nil, String.t() | nil}
  def schema(name, version) do
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

  defp jsdelivr_client do
    build_client([
      {Tesla.Middleware.BaseUrl, jsdelivr_url()},
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

  defp jsdelivr_url do
    Config.strategy_opts(Lightning.Adaptors.NPM)[:jsdelivr_url] ||
      @default_jsdelivr_url
  end

  defp http_timeout do
    Config.strategy_opts(Lightning.Adaptors.NPM)[:http_timeout] ||
      @default_http_timeout
  end
end
