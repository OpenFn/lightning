defmodule LightningWeb.ProjectFileController do
  use LightningWeb, :controller

  alias Lightning.Policies.Exports
  alias Lightning.Policies.Permissions
  alias Lightning.Repo
  alias Lightning.Storage.ProjectFileDefinition

  def download(conn, %{"id" => id}) do
    project_file = Repo.get!(Lightning.Projects.File, id)

    with :ok <-
           Permissions.can(
             Exports,
             :download,
             conn.assigns.current_user,
             project_file
           ),
         {:ok, file_content} <- ProjectFileDefinition.get(project_file) do
      conn
      |> put_resp_content_type("application/zip")
      |> put_resp_header(
        "Content-Disposition",
        "attachment; filename=\"#{Path.basename(project_file.path)}\""
      )
      |> send_resp(200, file_content)
    end
  end
end
