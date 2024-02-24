defmodule Lightning.AuthProviders.GoogleTest do
  use ExUnit.Case, async: false
  import Lightning.BypassHelpers

  alias Lightning.AuthProviders.Common

  describe "get_wellknown/0" do
    setup do
      bypass = Bypass.open()

      wellknown_url = "http://localhost:#{bypass.port}/auth/.well-known"

      expect_wellknown(bypass)

      {:ok,
       bypass: bypass,
       endpoint_url: "http://localhost:#{bypass.port}",
       wellknown_url: wellknown_url}
    end

    test "pulls the .well-known from the path specified in the Application", %{
      bypass: bypass,
      wellknown_url: wellknown_url
    } do
      assert {:ok, %Lightning.AuthProviders.WellKnown{} = wellknown} =
               Common.get_wellknown(wellknown_url)

      assert wellknown.authorization_endpoint ==
               "#{endpoint_url(bypass)}/authorization_endpoint"

      assert wellknown.token_endpoint == "#{endpoint_url(bypass)}/token_endpoint"

      assert wellknown.userinfo_endpoint ==
               "#{endpoint_url(bypass)}/userinfo_endpoint"
    end
  end

  describe "from_oauth2_token/1" do
    test "converts OAuth2.AccessToken to a map" do
      token = %OAuth2.AccessToken{
        access_token: "ya29.a0AWY7CknfkidjXaoDTuNi",
        expires_at: "4786203",
        refresh_token: "1//03dATMQTmE5NSCgYIARAAGAMSNwF"
      }

      result = Common.TokenBody.from_oauth2_token(token)

      assert is_map(result)
      assert Map.get(result, :access_token) == "ya29.a0AWY7CknfkidjXaoDTuNi"
      assert Map.get(result, :expires_at) == 4_786_203
      assert Map.get(result, :refresh_token) == "1//03dATMQTmE5NSCgYIARAAGAMSNwF"
    end
  end
end
