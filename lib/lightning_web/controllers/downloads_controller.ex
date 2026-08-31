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
           ),
         {:ok, yaml} <- Projects.export_project(:yaml, id) do
      conn
      |> put_resp_content_type("text/yaml")
      |> put_resp_header(
        "content-disposition",
        "attachment; filename=\"project-#{id}.yaml\""
      )
      |> put_root_layout(false)
      |> put_flash(:info, "Project yaml exported successfully")
      |> send_resp(200, yaml)
    else
      # Two names that hyphenate to one spec key stop the whole export. This is
      # the only export path with a person on the other end, and the fallback
      # controller answers a binary error with a 400 JSON body. The export
      # button opens a new tab, so the redirect lands there with the reason.
      {:error, message} when is_binary(message) ->
        conn
        |> put_flash(:error, message)
        |> redirect(to: ~p"/projects/#{id}/settings")

      error ->
        error
    end
  end
end
