defmodule LightningWeb.ProjectFileController do
  use LightningWeb, :controller

  alias Lightning.Repo

  def download(conn, %{"id" => id}) do
    project_file = Repo.get!(Lightning.Projects.File, id)

    file_url =
      Lightning.Storage.ProjectFileDefinition.url(
        {project_file.file, project_file},
        :original
      )

    conn
    |> redirect(external: file_url)
  end
end
