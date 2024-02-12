defmodule LightningWeb.API.ProvisioningController do
  use LightningWeb, :controller

  alias Lightning.Policies.Permissions
  alias Lightning.Policies.Provisioning
  alias Lightning.Projects
  alias Lightning.Projects.Project
  alias Lightning.Projects.Provisioner

  action_fallback(LightningWeb.FallbackController)

  @doc """
  Creates or updates a project based on a JSON payload that may or may not
  contain UUIDs for existing resources.
  """
  def create(conn, params) do
    with project <- get_or_build_project(params),
         :ok <-
           Permissions.can(
             Provisioning,
             :provision_project,
             conn.assigns.current_user,
             project
           ),
         {:ok, project} <-
           Provisioner.import_document(
             project,
             conn.assigns.current_user,
             params
           ) do
      conn
      |> put_status(:created)
      |> put_resp_header("location", ~p"/api/provision/#{project.id}")
      |> render("create.json", project: project)
    end
  end

  @doc """
  Returns a project "state.json", complete with UUIDs to enable idempotent
  project deployments and updates to existing projects via the CLI.
  """
  def show(conn, params) do
    with project = %Project{} <-
           Provisioner.load_project(params["id"]) || {:error, :not_found},
         :ok <-
           Permissions.can(
             Provisioning,
             :describe_project,
             conn.assigns.current_user,
             project
           ) do
      conn
      |> put_status(:ok)
      |> render("create.json", project: project)
    end
  end

  @doc """
  Returns a description of the project as yaml. Same as the export project to
  yaml button (see Downloads Controller) but made for the API.
  """
  def show_yaml(conn, %{"id" => id}) do
    with %Projects.Project{} = project <-
           Lightning.Projects.get_project(id) || {:error, :not_found},
         :ok <-
           Permissions.can(
             Provisioning,
             :describe_project,
             conn.assigns.current_user,
             project
           ) do
      {:ok, yaml} = Projects.export_project(:yaml, id)

      conn
      |> put_resp_content_type("text/yaml")
      |> put_root_layout(false)
      |> send_resp(200, yaml)
    end
  end

  defp get_or_build_project(params) do
    params
    |> case do
      %{"id" => id} -> Projects.get_project(id) || %Project{}
      _ -> %Project{}
    end
  end
end
