defmodule CredentialsServiceWeb.CredentialController do
  @moduledoc """
  REST controller for the Credentials slice. Implements the contract in
  `docs/api.md` (JSON:API envelope). Mirrors the
  `with :ok <- ... ` + `action_fallback` pattern the monolith's `api/*`
  controllers already use.
  """
  use Phoenix.Controller, formats: [:json]

  import Plug.Conn

  alias CredentialsService.Credentials

  action_fallback CredentialsServiceWeb.FallbackController

  def index(conn, params) do
    user_id = conn.assigns.current_user_id

    credentials =
      case params do
        %{"project_id" => project_id} ->
          Credentials.list_credentials_for_project(project_id)

        _ ->
          Credentials.list_credentials(user_id)
      end

    render(conn, :index, credentials: credentials)
  end

  def show(conn, %{"id" => id}) do
    with {:ok, credential} <- fetch(id) do
      render(conn, :show, credential: credential)
    end
  end

  def create(conn, params) do
    attrs = Map.put(params, "user_id", conn.assigns.current_user_id)

    with {:ok, credential} <- Credentials.create_credential(attrs) do
      conn
      |> put_status(:created)
      |> render(:show, credential: credential)
    end
  end

  def delete(conn, %{"id" => id}) do
    with {:ok, credential} <- fetch(id),
         :ok <- authorize_owner(credential, conn.assigns.current_user_id),
         {:ok, _credential} <- Credentials.delete_credential(credential) do
      send_resp(conn, :no_content, "")
    end
  end

  defp fetch(id) do
    case Credentials.get_credential(id) do
      nil -> {:error, :not_found}
      credential -> {:ok, credential}
    end
  end

  defp authorize_owner(%{user_id: user_id}, user_id), do: :ok
  defp authorize_owner(_credential, _user_id), do: {:error, :forbidden}
end
