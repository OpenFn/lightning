defmodule Lightning.AiAssistantHelpers do
  require Logger

  @apollo_endpoint "http://localhost:4001"

  def stub_online do
    Mox.stub(Lightning.MockConfig, :apollo, fn
      :endpoint -> @apollo_endpoint
      :ai_assistant_api_key -> "ai_assistant_api_key"
    end)

    Mox.stub(Lightning.Tesla.Mock, :call, fn
      %{method: :get, url: @apollo_endpoint <> "/"}, _opts ->
        {:ok, %Tesla.Env{status: 200}}

      %{method: :post} = request, _opts ->
        Logger.warning("""
        Unexpected request sent to Apollo:

        #{inspect(request, pretty: true)}
        """)

        {:error, :unknown}
    end)
  end

  @doc """
  Returns a Tesla response that handles both streaming and non-streaming
  endpoints. For streaming URLs (containing "/stream"), returns an SSE
  `event: complete` response. For other URLs, returns a regular JSON body.

  ## Examples

      stub_ai_response(%{"history" => [%{"role" => "assistant", "content" => "Hi"}]})

  """
  def streaming_or_sync_response(body) do
    fn
      %{method: :post, url: url}, _opts when is_binary(url) ->
        if String.contains?(url, "/stream") do
          {:ok,
           %Tesla.Env{
             status: 200,
             headers: [{"content-type", "text/event-stream"}],
             body: "event: complete\ndata: #{Jason.encode!(body)}\n\n"
           }}
        else
          {:ok, %Tesla.Env{status: 200, body: body}}
        end

      env, _opts ->
        # Fall through for non-POST requests (e.g. health checks)
        raise "Unexpected request: #{inspect(env.method)} #{inspect(env.url)}"
    end
  end

  @doc """
  Stubs the Tesla mock to handle both streaming and non-streaming AI responses,
  plus a health-check GET on the Apollo endpoint.

  ## Examples

      stub_ai_with_health_check(
        "http://localhost:4001",
        %{"history" => [%{"role" => "assistant", "content" => "Hello!"}]}
      )

  """
  def stub_ai_with_health_check(apollo_endpoint, body) do
    Mox.stub(Lightning.Tesla.Mock, :call, fn
      %{method: :get, url: ^apollo_endpoint <> "/"}, _opts ->
        {:ok, %Tesla.Env{status: 200}}

      %{method: :post, url: url}, _opts when is_binary(url) ->
        if String.contains?(url, "/stream") do
          {:ok,
           %Tesla.Env{
             status: 200,
             headers: [{"content-type", "text/event-stream"}],
             body: "event: complete\ndata: #{Jason.encode!(body)}\n\n"
           }}
        else
          {:ok, %Tesla.Env{status: 200, body: body}}
        end
    end)
  end
end
