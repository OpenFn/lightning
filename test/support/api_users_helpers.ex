defmodule LightningWeb.ApiUsersHelpers do
  @moduledoc """
  Setup and builders shared by the users API tests.
  """
  import Lightning.ServiceAccountHelpers, only: [service_account_with_key: 0]
  import Plug.Conn, only: [put_req_header: 3]

  alias LightningWeb.UserAuth

  @password "a long enough password"

  def password, do: @password

  @doc """
  A setup that makes a service account, configures it as the instance's one,
  and asks for JSON. Adds `:account` to the context.
  """
  def json_conn_with_service_account(%{conn: conn}) do
    {account, _private_key} = service_account_with_key()
    Mox.stub(Lightning.MockConfig, :service_account, fn -> account end)

    %{
      conn: put_req_header(conn, "accept", "application/json"),
      account: account
    }
  end

  def user_url(id), do: "#{LightningWeb.Endpoint.url()}/api/users/#{id}"

  def watch_sockets(user) do
    LightningWeb.Endpoint.subscribe(UserAuth.user_socket_topic(user))
    LightningWeb.Endpoint.subscribe(UserAuth.live_socket_topic(user))
  end
end
