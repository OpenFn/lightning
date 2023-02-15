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
  def expect_token(bypass, wellknown, token \\ nil) do
    path = URI.new!(wellknown.token_endpoint).path

    Bypass.expect(bypass, "POST", path, fn conn ->
      Plug.Conn.resp(
        conn,
        200,
        token ||
          %{"access_token" => "blah", "refresh_token" => "blerg"}
          |> Jason.encode!()
      )
    end)
  end

  def expect_token_failure(bypass, wellknown, error) do
    path = URI.new!(wellknown.token_endpoint).path

    Bypass.expect_once(bypass, "POST", path, fn conn ->
      Plug.Conn.resp(conn, 401, error |> Jason.encode!())
    end)
  end

  @doc """
  Add a userinfo endpoint expectation. Used to test AuthProviders
  """
  def expect_userinfo(bypass, wellknown, userinfo) do
    path = URI.new!(wellknown.userinfo_endpoint).path

    Bypass.expect_once(bypass, "GET", path, fn conn ->
      Plug.Conn.resp(conn, 200, userinfo |> Jason.encode!())
    end)
  end

  @doc """
  Generate an http url for use with a Bypass test process
  """
  def endpoint_url(bypass) do
    "http://localhost:#{bypass.port}"
  end
end
