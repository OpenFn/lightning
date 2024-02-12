defmodule Lightning.AuthProviders.WellKnownTest do
  use ExUnit.Case, async: true
  alias Lightning.AuthProviders.WellKnown

  describe "fetch/1" do
    setup do
      bypass = Bypass.open()
      {:ok, bypass: bypass, endpoint_url: "http://localhost:#{bypass.port}"}
    end

    test "retrieves and decodes .well-known", %{
      bypass: bypass,
      endpoint_url: endpoint_url
    } do
      Lightning.BypassHelpers.expect_wellknown(bypass)

      assert {:ok,
              %WellKnown{
                authorization_endpoint: "#{endpoint_url}/authorization_endpoint",
                token_endpoint: "#{endpoint_url}/token_endpoint",
                userinfo_endpoint: "#{endpoint_url}/userinfo_endpoint",
                introspection_endpoint: "#{endpoint_url}/introspection_endpoint"
              }} == WellKnown.fetch("#{endpoint_url}/auth/.well-known")

      Bypass.down(bypass)

      {:error, %HTTPoison.Error{id: nil, reason: :econnrefused}} =
        WellKnown.fetch!("#{endpoint_url}/.not-well-known")
    end
  end
end
