defmodule LightningWeb.API.CredentialController do
  @moduledoc """
  API controller for credential management.

  Handles creation, retrieval, and deletion of credentials. Credentials are
  used to authenticate with external services and can be associated with
  multiple projects.

  ## Security

  - Credential bodies are excluded from responses for security
  - Users can only delete credentials they own
  - Project access is required to view project credentials

  ## Examples

      GET /api/credentials
      GET /api/credentials?project_id=a1b2c3d4-...
      POST /api/credentials
      DELETE /api/credentials/a1b2c3d4-...
  """
  @moduledoc docout: true
  use LightningWeb, :controller

  alias Lightning.Credentials
  alias Lightning.Policies.Permissions
  alias Lightning.Policies.ProjectUsers
  alias Lightning.Projects

  action_fallback LightningWeb.FallbackController

  @doc """
  Lists credentials with optional project filtering.

  This function has two variants:
  - With `project_id`: Returns all credentials for a specific project (regardless of owner)
  - Without `project_id`: Returns only credentials owned by the authenticated user

  Credential bodies are excluded from responses for security.

  ## Parameters

  - `conn` - The Plug connection struct with the current resource assigned
  - `params` - Map containing:
    - `project_id` - Project UUID (optional, filters to specific project)

  ## Returns

  - `200 OK` with list of credentials (bodies excluded)
  - `404 Not Found` if project doesn't exist (when project_id provided)
  - `403 Forbidden` if user lacks project access (when project_id provided)

  ## Examples

      # User's own credentials
      GET /api/credentials

      # All credentials for a project
      GET /api/credentials?project_id=a1b2c3d4-5e6f-7a8b-9c0d-1e2f3a4b5c6d
  """
  @spec index(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def index(conn, %{"project_id" => project_id}) do
    current_user = conn.assigns.current_resource

    with project when not is_nil(project) <- Projects.get_project(project_id),
         :ok <-
           ProjectUsers
           |> Permissions.can(
             :access_project,
             current_user,
             project
           ) do
      credentials = Credentials.list_credentials(project)
      render(conn, "index.json", credentials: credentials)
    else
      nil ->
        {:error, :not_found}

      {:error, :unauthorized} ->
        {:error, :forbidden}
    end
  end

  def index(conn, _params) do
    current_user = conn.assigns.current_resource
    credentials = Credentials.list_credentials(current_user)

    render(conn, "index.json", credentials: credentials)
  end

  @doc """
  Creates a new credential and optionally grants it access to projects.

  Creates a credential owned by the authenticated user. If project_credentials
  are specified, the user must have access to all listed projects. The credential
  body is included in the response only upon creation.

  ## Parameters

  - `conn` - The Plug connection struct with the current resource assigned
  - `params` - Map containing:
    - `name` - Credential name (required)
    - `body` - Credential JSON body with authentication details (required)
    - `project_credentials` - List of project associations (optional)

  ## Returns

  - `201 Created` with credential JSON including body
  - `422 Unprocessable Entity` on validation errors
  - `403 Forbidden` if user lacks access to specified projects

  ## Examples

      # Create credential without project association
      POST /api/credentials
      {
        "name": "My API Key",
        "body": {"apiKey": "secret123"}
      }

      # Create credential with project associations
      POST /api/credentials
      {
        "name": "Shared Credential",
        "body": {"token": "abc123"},
        "project_credentials": [
          {"project_id": "a1b2c3d4-..."}
        ]
      }
  """
  @spec create(Plug.Conn.t(), map()) :: Plug.Conn.t()
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

  Permanently removes a credential. Only the credential owner can delete it.
  Credentials in use by workflows cannot be deleted and will return an error.

  ## Parameters

  - `conn` - The Plug connection struct with the current resource assigned
  - `params` - Map containing:
    - `id` - Credential UUID (required)

  ## Returns

  - `204 No Content` on successful deletion
  - `404 Not Found` if credential doesn't exist or invalid UUID
  - `403 Forbidden` if user is not the credential owner

  ## Examples

      DELETE /api/credentials/a1b2c3d4-5e6f-7a8b-9c0d-1e2f3a4b5c6d
  """
  @spec delete(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def delete(conn, %{"id" => id}) do
    current_user = conn.assigns.current_resource

    with :ok <- validate_uuid(id),
         credential when not is_nil(credential) <-
           Credentials.get_credential(id),
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
