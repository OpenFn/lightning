defmodule LightningWeb.ConnHelpers do
  @moduledoc false

  alias Lightning.Accounts
  alias Lightning.Accounts.User

  @doc """
  Prepares a conn for plugs that read or write the session.

  `Phoenix.ConnTest.build_conn/0` leaves the endpoint and its signing salt
  unset, so a session write raises unless both are put back on the conn first.
  """
  def browser_conn(conn) do
    conn
    |> Map.replace!(
      :secret_key_base,
      LightningWeb.Endpoint.config(:secret_key_base)
    )
    |> Plug.Conn.put_private(:phoenix_endpoint, LightningWeb.Endpoint)
    |> Plug.Test.init_test_session(%{})
  end

  def assign_bearer(conn, %User{} = user) do
    token = Accounts.generate_api_token(user)

    conn |> Plug.Conn.put_req_header("authorization", "Bearer #{token}")
  end

  def assign_bearer(conn, token) do
    conn |> Plug.Conn.put_req_header("authorization", "Bearer #{token}")
  end
end
