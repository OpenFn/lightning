defmodule LightningWeb.ProjectFileController do
  use LightningWeb, :controller

  alias Lightning.Repo
  alias Lightning.Storage.ProjectFileDefinition

  def download(conn, %{"id" => id}) do
    project_file = Repo.get!(Lightning.Projects.File, id)

    if ProjectFileDefinition.__storage() == Waffle.Storage.Local do
      file_path =
        ProjectFileDefinition.file_path(
          {project_file.file, project_file},
          :original
        )
        |> Path.expand()

      conn
      |> send_file(200, file_path)
    else
      file_url =
        ProjectFileDefinition.url(
          {project_file.file, project_file},
          :original
        )

      conn
      |> redirect(external: file_url)
    end
  end
end
