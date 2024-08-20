defmodule Lightning.Storage.ProjectFileDefinition do
  alias Lightning.Projects.File, as: ProjectFile
  alias Lightning.Storage

  def store(source_path, %ProjectFile{} = file) do
    Storage.store(source_path, file.path)
  end

  def get(%ProjectFile{} = file) do
    Storage.get(file.path)
  end

  def storage_path_for_exports(%ProjectFile{} = file, ext \\ ".zip") do
    Path.join(["exports", file.project_id, "#{file.id}#{ext}"])
  end
end
