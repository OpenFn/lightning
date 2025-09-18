defmodule LightningWeb.API.CredentialController do
  use LightningWeb, :controller

  alias Lightning.Credentials
  alias Lightning.Policies.Permissions
  alias Lightning.Policies.ProjectUsers
  alias Lightning.Projects

  action_fallback LightningWeb.FallbackController

  @doc """
  Lists all credentials owned by the authenticated user.

  The response excludes the credential body for security reasons.
  """
  def index(conn, _params) do
    current_user = conn.assigns.current_resource
    credentials = Credentials.list_credentials(current_user)

    render(conn, "index.json", credentials: credentials)
  end

  @doc """
  Creates a new credential and optionally grants it access to specified projects.

  The authenticated user must have access to any projects specified in the
  project_credentials list. The created credential will be owned by the
  authenticated user.
  """
  def create(conn, params) do
    current_user = conn.assigns.current_resource

    with {:ok, validated_params} <-
           validate_and_authorize_projects(params, current_user),
         {:ok, credential} <- Credentials.create_credential(validated_params) do
      conn
      |> put_status(:created)
      |> render("create.json", credential: credential)
    end
  end

  @doc """
  Deletes a credential owned by the authenticated user.

  Only the owner of the credential can delete it.
  """
  def delete(conn, %{"id" => id}) do
    current_user = conn.assigns.current_resource

    with :ok <- validate_uuid(id),
         credential when not is_nil(credential) <- Credentials.get_credential(id),
         :ok <- validate_credential_ownership(credential, current_user),
         {:ok, _} <- Credentials.delete_credential(credential) do
      send_resp(conn, :no_content, "")
    else
      {:error, :invalid_uuid} ->
        {:error, :not_found}
      nil ->
        {:error, :not_found}
      {:error, :forbidden} ->
        {:error, :forbidden}
      error ->
        error
    end
  end

  defp validate_uuid(id) do
    case Ecto.UUID.dump(to_string(id)) do
      {:ok, _bin} -> :ok
      :error -> {:error, :invalid_uuid}
    end
  end

  defp validate_credential_ownership(credential, current_user) do
    if credential.user_id == current_user.id do
      :ok
    else
      {:error, :forbidden}
    end
  end

  defp validate_and_authorize_projects(params, current_user) do
    # Ensure user_id is set to the current authenticated user
    params_with_user = Map.put(params, "user_id", current_user.id)

    project_credentials = Map.get(params, "project_credentials", [])

    if Enum.empty?(project_credentials) do
      {:ok, params_with_user}
    else
      case validate_project_access(project_credentials, current_user) do
        :ok -> {:ok, params_with_user}
        {:error, _} = error -> error
      end
    end
  end

  defp validate_project_access(project_credentials, current_user) do
    project_ids =
      project_credentials
      |> Enum.map(&Map.get(&1, "project_id"))
      |> Enum.filter(& &1)

    unauthorized_projects =
      Enum.filter(project_ids, fn project_id ->
        case Projects.get_project(project_id) do
          nil ->
            true

          project ->
            case ProjectUsers
                 |> Permissions.can(
                   :create_project_credential,
                   current_user,
                   project
                 ) do
              :ok -> false
              _ -> true
            end
        end
      end)

    if Enum.empty?(unauthorized_projects) do
      :ok
    else
      {:error, :forbidden}
    end
  end
end
