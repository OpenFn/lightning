defmodule Lightning.BypassHelpers do
  @moduledoc false

  @doc """
  Add a well-known endpoint expectation. Used to test AuthProviders
  """
  def expect_wellknown(bypass) do
    Bypass.expect(bypass, "GET", "auth/.well-known", fn conn ->
      Plug.Conn.resp(
        conn,
        200,
        %{
          "authorization_endpoint" =>
            "#{endpoint_url(bypass)}/authorization_endpoint",
          "token_endpoint" => "#{endpoint_url(bypass)}/token_endpoint",
          "userinfo_endpoint" => "#{endpoint_url(bypass)}/userinfo_endpoint"
        }
        |> Jason.encode!()
      )
    end)
  end

  @doc """
  Add a token endpoint expectation. Used to test AuthProviders
  """
  def expect_token(bypass, wellknown, token \\ nil)

  def expect_token(bypass, wellknown, {code, body}) do
    path = URI.new!(wellknown.token_endpoint).path

    Bypass.expect(bypass, "POST", path, fn conn ->
      Plug.Conn.resp(conn, code, body)
    end)
  end

  def expect_token(bypass, wellknown, token) do
    body =
      token ||
        %{"access_token" => "blah", "refresh_token" => "blerg"}
        |> Jason.encode!()

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
