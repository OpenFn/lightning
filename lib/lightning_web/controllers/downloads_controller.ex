defmodule LightningWeb.DownloadsController do
  use LightningWeb, :controller

  alias Lightning.Policies.Permissions
  alias Lightning.Policies.ProjectUsers
  alias Lightning.Projects

  action_fallback(LightningWeb.FallbackController)

  def download_project_yaml(conn, %{"id" => id}) do
    with %Projects.Project{} = project <-
           Lightning.Projects.get_project(id) || {:error, :not_found},
         :ok <-
           ProjectUsers
           |> Permissions.can(
             :access_project,
             conn.assigns.current_user,
             project
           ) do
      {:ok, yaml} = Projects.export_project(:yaml, id)

      conn
      |> put_resp_content_type("text/yaml")
      |> put_resp_header(
        "content-disposition",
        "attachment; filename=\"project-#{id}.yaml\""
      )
      |> put_root_layout(false)
      |> put_flash(:info, "Project yaml exported successfully")
      |> send_resp(200, yaml)
    end
  end
end
