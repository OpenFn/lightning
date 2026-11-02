defmodule LightningWeb.Plugs.ApiAuth do
  @moduledoc """
  Authenticates api calls based on JWT bearer token.
  """
  import Plug.Conn

  alias LightningWeb.Auth

  def init(opts) do
    opts
  end

  def call(conn, _opts) do
    with {:ok, bearer_token} <- Auth.bearer_token(conn),
         {:ok, claims} <- Lightning.Tokens.verify(bearer_token) do
      conn
      |> assign(:claims, claims)
      |> put_subject()
    else
      {:error, _reason} ->
        Auth.refuse(conn, :bearer)
    end
  end

  defp put_subject(conn) do
    case Lightning.Tokens.get_subject(conn.assigns.claims) do
      nil -> Auth.refuse(conn, :bearer)
      subject -> assign(conn, :subject, subject)
    end
  end
end
