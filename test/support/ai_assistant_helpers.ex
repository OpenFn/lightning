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
end
