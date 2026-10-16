defmodule LightningWeb.Plugs.ApiAuth do
  @moduledoc """
  Authenticates api calls based on JWT bearer token.
  """
  import Plug.Conn

  alias LightningWeb.API.Unauthenticated

  def init(opts) do
    opts
  end

  def call(conn, _opts) do
    with {:ok, bearer_token} <- get_bearer_token(conn),
         {:ok, claims} <- Lightning.Tokens.verify(bearer_token) do
      conn
      |> assign(:claims, claims)
      |> put_subject()
    else
      {:error, _reason} ->
        Unauthenticated.refuse(conn, :bearer)
    end
  end

  defp get_bearer_token(conn) do
    conn
    |> get_req_header("authorization")
    |> case do
      ["Bearer " <> bearer] -> {:ok, bearer}
      _none_or_many -> {:error, :token_not_found}
    end
  end

  defp put_subject(conn) do
    case Lightning.Tokens.get_subject(conn.assigns.claims) do
      nil -> Unauthenticated.refuse(conn, :bearer)
      subject -> assign(conn, :subject, subject)
    end
  end
end
