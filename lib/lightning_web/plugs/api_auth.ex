defmodule LightningWeb.Plugs.ApiAuth do
  @moduledoc """
  Authenticates api calls based on JWT bearer token.
  """
  use Phoenix.Controller
  import Plug.Conn

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
        deny_access(conn)
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
    conn.assigns.claims
    |> Lightning.Tokens.get_subject()
    |> then(fn subject ->
      conn |> assign(:subject, subject)
    end)
  end

  defp deny_access(conn) do
    conn
    |> put_status(:unauthorized)
    |> put_view(LightningWeb.ErrorView)
    |> render(:"401")
    |> halt()
  end
end
