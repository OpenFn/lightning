defmodule Lightning.AuthProviders.OauthHTTPClientEgressTest do
  # async: false — points OauthHTTPClient at the real PinnedAdapter by mutating
  # global :tesla config, so it must not run alongside the Mox-based tests.
  use ExUnit.Case, async: false

  alias Lightning.AuthProviders.OauthHTTPClient
  alias Lightning.AuthProviders.OauthHTTPClient.PinnedAdapter

  # Exercises the real prod entry point (OauthHTTPClient) through the real egress
  # adapter, the way #193 guards the channel proxy's wiring: an internal endpoint
  # must be refused end to end, not just by the adapter in isolation.
  setup do
    previous = Application.get_env(:tesla, OauthHTTPClient)

    Application.put_env(:tesla, OauthHTTPClient,
      adapter: {PinnedAdapter, block_private_networks: true, allowed_hosts: []}
    )

    on_exit(fn -> Application.put_env(:tesla, OauthHTTPClient, previous) end)
  end

  test "fetch_token refuses a token endpoint on an internal address" do
    client = %{
      client_id: "id",
      client_secret: "secret",
      token_endpoint: "http://169.254.169.254/token"
    }

    assert {:error, %{status: 0, error: "network_error"}} =
             OauthHTTPClient.fetch_token(client, "code")
  end

  test "fetch_userinfo refuses a userinfo endpoint on an internal address" do
    client = %{userinfo_endpoint: "http://10.0.0.5/userinfo"}

    assert {:error, %{status: 0, error: "network_error"}} =
             OauthHTTPClient.fetch_userinfo(client, %{"access_token" => "t"})
  end
end
