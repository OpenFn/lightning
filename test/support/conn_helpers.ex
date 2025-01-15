defmodule LightningWeb.ConnHelpers do
  @moduledoc false

  alias Lightning.Accounts
  alias Lightning.Accounts.User

  def assign_bearer(conn, %User{} = user) do
    token = Accounts.generate_api_token(user)

    conn |> Plug.Conn.put_req_header("authorization", "Bearer #{token}")
  end

  def assign_bearer(conn, token) do
    conn |> Plug.Conn.put_req_header("authorization", "Bearer #{token}")
  end
end
