defmodule LightningWeb.ProjectFileController do
  use LightningWeb, :controller

  alias Lightning.Repo
  alias Lightning.Storage.ProjectFileDefinition

  def download(conn, %{"id" => id}) do
    project_file = Repo.get!(Lightning.Projects.File, id)

    with {:ok, file_content} <- ProjectFileDefinition.get(project_file) do
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
