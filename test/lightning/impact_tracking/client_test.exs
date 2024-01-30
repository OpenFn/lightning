defmodule Lightning.ImpactTracking.ClientTest do
  use ExUnit.Case, async: false

  import Tesla.Mock

  alias Lightning.ImpactTracking.Client

  @host "https://foo.bar"

  describe ".submit_metrics" do
    test "sends supplied metrics to impact tracker" do
      url = "#{@host}/api/metrics"
      serialised_metrics = Jason.encode!(%{some: :metrics})

      mock(fn
        %{
          method: :post,
          url: ^url,
          body: ^serialised_metrics,
          headers: [{"content-type", "application/json"}]
        } ->
          %Tesla.Env{status: 200, body: %{status: "great"}}

        _ ->
          flunk("Unrecognised call")
      end)

      assert {:ok, %Tesla.Env{status: 200, body: %{status: "great"}}} =
               Client.submit_metrics(%{some: :metrics}, @host)
    end
  end
end
