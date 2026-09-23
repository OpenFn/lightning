defmodule Lightning.Adaptors.NPM.Schema do
  @moduledoc """
  jsDelivr CDN client for adaptor configuration schemas.

  Fetches `/npm/<name>@<version>/configuration-schema.json` from
  `cdn.jsdelivr.net`, checks it decodes, and keeps the body as the bytes
  served.

  Base URL via `Lightning.Adaptors.Config.strategy_opts(Lightning.Adaptors.NPM)[:jsdelivr_url]`,
  default `https://cdn.jsdelivr.net`.
  """

  alias Lightning.Adaptors.Config

  @default_jsdelivr_url "https://cdn.jsdelivr.net"
  @default_http_timeout :timer.seconds(30)

  @doc """
  Fetch the configuration schema for `name@version` from jsDelivr.

  Returns `{:ok, {schema_data, schema_sha256}}` on success and
  `{:ok, {nil, nil}}` on a 404. jsDelivr answers 404 both for a package
  with no schema and for a version it has not mirrored yet, so the
  Scheduler decides what a `nil` means. Any other failure (timeout, other status, undecodable body) is
  `{:error, reason}`, so callers that persist the result never mistake a
  transient failure for absence.
  """
  @spec schema(String.t(), String.t()) ::
          {:ok, {String.t(), String.t()}} | {:ok, {nil, nil}} | {:error, term()}
  def schema(name, version) do
    case fetch_schema_bytes(name, version) do
      {:ok, body} -> Lightning.Adaptors.Strategy.digest_schema(body)
      {:error, {:http_status, 404}} -> {:ok, {nil, nil}}
      {:error, _} = err -> err
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
