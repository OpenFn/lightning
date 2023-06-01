defmodule Lightning.AuthProviders.GoogleTest do
  use ExUnit.Case, async: false
  import Lightning.BypassHelpers

  alias Lightning.AuthProviders.Google

  setup do
    bypass = Bypass.open()

    Lightning.ApplicationHelpers.put_temporary_env(:lightning, :oauth_clients,
      google: [wellknown_url: "http://localhost:#{bypass.port}/auth/.well-known"]
    )

    expect_wellknown(bypass)

    {:ok, bypass: bypass, endpoint_url: "http://localhost:#{bypass.port}"}
  end

  describe "get_wellknown/0" do
    test "pulls the .well-known from the path specified in the Application", %{
      bypass: bypass
    } do
      assert {:ok, %Lightning.AuthProviders.WellKnown{} = wellknown} =
               Google.get_wellknown()

      assert wellknown.authorization_endpoint ==
               "#{endpoint_url(bypass)}/authorization_endpoint"

      assert wellknown.token_endpoint == "#{endpoint_url(bypass)}/token_endpoint"

      assert wellknown.userinfo_endpoint ==
               "#{endpoint_url(bypass)}/userinfo_endpoint"
    end
  end

  describe "refresh_token" do
    Google.refresh_token(...)
  end
end
