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
         {:ok, file_url} <- ProjectFileDefinition.get_url(project_file) do
      case URI.parse(file_url) do
        %{scheme: "file", path: path} ->
          send_download(conn, {:file, path})

        _http_url ->
          redirect(conn, external: file_url)
      end
    end
  end
end
