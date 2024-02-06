defmodule Lightning.BypassHelpers do
  @moduledoc false

  def build_wellknown(bypass, attrs \\ %{}) do
    Map.merge(
      %{
        "authorization_endpoint" =>
          "#{endpoint_url(bypass)}/authorization_endpoint",
        "token_endpoint" => "#{endpoint_url(bypass)}/token_endpoint",
        "userinfo_endpoint" => "#{endpoint_url(bypass)}/userinfo_endpoint"
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

  def expect_introspect(bypass, path, token \\ %{}) do
    %{path: path} = URI.new!(path)

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
      Plug.Conn.resp(conn, code, body)
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
  Generate an http url for use with a Bypass test process
  """
  def endpoint_url(bypass) do
    "http://localhost:#{bypass.port}"
  end
end
