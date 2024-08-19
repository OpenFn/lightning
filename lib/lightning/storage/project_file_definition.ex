defmodule Lightning.Storage.ProjectFileDefinition do
  alias Lightning.Projects.File, as: ProjectFile
  alias Lightning.Storage

  def store(source_path, %ProjectFile{} = file) do
    Storage.store(source_path, storage_path(file))
  end

  def get(%ProjectFile{} = file) do
    file |> storage_path() |> Storage.get()
  end

  defp storage_path(%ProjectFile{file: filename, project_id: project_id}) do
    Path.join(["exports", project_id, filename])
  end
end
