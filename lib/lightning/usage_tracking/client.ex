defmodule Lightning.UsageTracking.Client do
  @moduledoc """
  Client for Usage Tracker service


  """
  alias Lightning.UsageTracking.ResponseProcessor

  defp adapter do
    Application.get_env(:tesla, __MODULE__, [])[:adapter]
  end

  def submit_metrics(metrics, host) do
    response =
      host
      |> build_client()
      |> Tesla.post("/api/metrics", metrics)

    if ResponseProcessor.successful?(response), do: :ok, else: :error
  end

  def reachable?(host) do
    build_head_client(host)
    |> Tesla.head("/")
    |> ResponseProcessor.successful?()
  end

  defp build_client(host) do
    Tesla.client(
      [{Tesla.Middleware.BaseUrl, host}, Tesla.Middleware.JSON],
      adapter()
    )
  end

  defp build_head_client(host) do
    Tesla.client([{Tesla.Middleware.BaseUrl, host}], adapter())
  end
end
