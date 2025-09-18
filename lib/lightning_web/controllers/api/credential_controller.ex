defmodule LightningWeb.API.CredentialController do
  use LightningWeb, :controller

  alias Lightning.Credentials
  alias Lightning.Policies.Permissions
  alias Lightning.Policies.ProjectUsers
  alias Lightning.Projects

  action_fallback LightningWeb.FallbackController

  @doc """
  Creates a new credential and optionally grants it access to specified projects.

  The authenticated user must have access to any projects specified in the
  project_credentials list. The created credential will be owned by the
  authenticated user.
  """
  def create(conn, params) do
    current_user = conn.assigns.current_resource

    with {:ok, validated_params} <- validate_and_authorize_projects(params, current_user),
         {:ok, credential} <- Credentials.create_credential(validated_params) do
      conn
      |> put_status(:created)
      |> render("create.json", credential: credential)
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
