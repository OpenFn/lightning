defmodule Lightning.AuthProviders.OauthHTTPClient.PinnedAdapterTest do
  use ExUnit.Case, async: true

  alias Lightning.AuthProviders.OauthHTTPClient.PinnedAdapter

  defp client(opts) do
    Tesla.client([Tesla.Middleware.FormUrlencoded], {PinnedAdapter, opts})
  end

  describe "egress blocking" do
    test "blocks internal and reserved addresses before connecting" do
      client = client(allowed_hosts: [], block_private_networks: true)

      for url <- [
            "http://169.254.169.254/",
            "http://10.0.0.5/",
            "http://[::1]/"
          ] do
        assert {:error, %Tesla.Error{reason: :egress_blocked}} =
                 Tesla.post(client, url, %{grant_type: "authorization_code"})
      end
    end

    test "validates the resolved address, not the hostname string" do
      resolver = fn
        _charlist, :inet -> {:ok, [{169, 254, 169, 254}]}
        _charlist, _family -> {:ok, []}
      end

      client = client(resolver: resolver, allowed_hosts: [])

      assert {:error, %Tesla.Error{reason: :egress_blocked}} =
               Tesla.post(client, "https://rebind.test/", %{
                 grant_type: "refresh_token"
               })
    end
  end

  describe "pinned request" do
    test "connects to the validated IP and returns the response" do
      bypass = Bypass.open()

      response = %{"access_token" => "token123", "token_type" => "bearer"}

      Bypass.expect_once(bypass, "POST", "/token", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(response))
      end)

      resolver = fn
        _charlist, :inet -> {:ok, [{127, 0, 0, 1}]}
        _charlist, _family -> {:ok, []}
      end

      client = client(resolver: resolver, allowed_hosts: ["provider.test"])

      assert {:ok, %Tesla.Env{status: 200, body: body}} =
               Tesla.post(
                 client,
                 "http://provider.test:#{bypass.port}/token",
                 %{grant_type: "authorization_code"}
               )

      assert Jason.decode!(body) == response
    end
  end
end
