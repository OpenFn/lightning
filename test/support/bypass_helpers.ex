defmodule Lightning.BypassHelpers do
  @moduledoc false

  # Stable RSA keypairs for signing/verifying test id_tokens. Generated once at
  # compile time so the public JWKS we serve matches the private key we sign
  # with within (and across) tests.
  @kid "test-signing-key"
  @private_jwk JOSE.JWK.generate_key({:rsa, 2048})
  @other_private_jwk JOSE.JWK.generate_key({:rsa, 2048})

  def test_kid, do: @kid
  def test_private_jwk, do: @private_jwk
  def other_private_jwk, do: @other_private_jwk

  @doc """
  The public JWK (as a plain map, with a `kid`) matching `test_private_jwk/0`.
  """
  def public_jwk_map do
    {_modules, map} =
      @private_jwk |> JOSE.JWK.to_public() |> JOSE.JWK.to_map()

    Map.merge(map, %{"kid" => @kid, "use" => "sig", "alg" => "RS256"})
  end

  @doc """
  The public JWK (as a plain map) matching `other_private_jwk/0`, tagged with the
  given `kid`. Useful for simulating a JWKS key rotation.
  """
  def other_public_jwk_map(kid) do
    {_modules, map} =
      @other_private_jwk |> JOSE.JWK.to_public() |> JOSE.JWK.to_map()

    Map.merge(map, %{"kid" => kid, "use" => "sig", "alg" => "RS256"})
  end

  @doc """
  A JWKS document (`%{"keys" => [...]}`) exposing the test public key.
  """
  def jwks, do: %{"keys" => [public_jwk_map()]}

  @doc """
  Sign a claims map into a compact JWS (id_token). Defaults to the stable test
  key and `kid`; pass a different `jwk`/`kid` to forge a bad signature while
  still pointing the header at the served key.
  """
  def sign_id_token(claims, jwk \\ @private_jwk, kid \\ @kid) do
    jwk
    |> JOSE.JWT.sign(%{"alg" => "RS256", "kid" => kid}, claims)
    |> JOSE.JWS.compact()
    |> elem(1)
  end

  @doc """
  Add a JWKS endpoint expectation serving the test public key set.
  """
  def expect_jwks(bypass, jwks_uri) do
    path = URI.new!(jwks_uri).path

    Bypass.expect(bypass, "GET", path, fn conn ->
      conn
      |> Plug.Conn.put_resp_header("content-type", "application/json")
      |> Plug.Conn.resp(200, Jason.encode!(jwks()))
    end)
  end

  def build_wellknown(bypass, attrs \\ %{}) do
    Map.merge(
      %{
        "authorization_endpoint" =>
          "#{endpoint_url(bypass)}/authorization_endpoint",
        "token_endpoint" => "#{endpoint_url(bypass)}/token_endpoint",
        "userinfo_endpoint" => "#{endpoint_url(bypass)}/userinfo_endpoint",
        "introspection_endpoint" =>
          "#{endpoint_url(bypass)}/introspection_endpoint"
      },
      attrs
    )
  end

  @doc """
  Add a well-known endpoint expectation. Used to test AuthProviders
  """
  def expect_wellknown(bypass, wellknown \\ nil)

  def expect_wellknown(bypass, nil) do
    expect_wellknown(bypass, build_wellknown(bypass))
  end

  def expect_wellknown(bypass, wellknown) do
    Bypass.expect(bypass, "GET", "auth/.well-known", fn conn ->
      Plug.Conn.resp(conn, 200, wellknown |> Jason.encode!())
    end)
  end

  def expect_introspect(bypass, wellknown, token \\ %{}) do
    %{path: path} = URI.new!(wellknown.introspection_endpoint)

    Bypass.expect(bypass, "POST", path, fn conn ->
      Plug.Conn.resp(conn, 200, token |> Jason.encode!())
    end)
  end

  @doc """
  Add a token endpoint expectation. Used to test AuthProviders
  """
  def expect_token(bypass, wellknown, token \\ nil)

  def expect_token(bypass, wellknown, {code, body}) do
    %{path: path} = URI.new!(wellknown.token_endpoint)

    Bypass.expect(bypass, "POST", path, fn conn ->
      conn
      |> Plug.Conn.put_resp_header("content-type", "application/json")
      |> Plug.Conn.resp(code, body)
    end)
  end

  def expect_token(bypass, wellknown, token) do
    token_attrs =
      token ||
        %{
          access_token: "access_token_123",
          refresh_token: "refresh_token_123",
          expires_at: 3600
        }

    body = Jason.encode!(token_attrs)

    expect_token(bypass, wellknown, {200, body})
  end

  @doc """
  Add a userinfo endpoint expectation. Used to test AuthProviders
  """
  def expect_userinfo(bypass, wellknown, {code, body}) do
    path = URI.new!(wellknown.userinfo_endpoint).path

    Bypass.expect(bypass, "GET", path, fn conn ->
      Plug.Conn.put_resp_header(conn, "content-type", "application/json")
      |> Plug.Conn.resp(code, body)
    end)
  end

  def expect_userinfo(bypass, wellknown, userinfo) do
    body =
      unless is_binary(userinfo) do
        Jason.encode!(userinfo)
      else
        userinfo
      end

    expect_userinfo(bypass, wellknown, {200, body})
  end

  @doc """
  Add a user emails endpoint expectation (e.g. GitHub's `/user/emails`). Used to
  test providers that resolve a verified email from a dedicated endpoint.
  """
  def expect_user_emails(bypass, wellknown, emails) do
    path = URI.new!(wellknown.user_emails_endpoint).path

    Bypass.expect(bypass, "GET", path, fn conn ->
      Plug.Conn.put_resp_header(conn, "content-type", "application/json")
      |> Plug.Conn.resp(200, Jason.encode!(emails))
    end)
  end

  @doc """
  Generate an http url for use with a Bypass test process
  """
  def endpoint_url(bypass) do
    "http://localhost:#{bypass.port}"
  end
end
