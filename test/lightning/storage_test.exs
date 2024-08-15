defmodule Lightning.StorageTest do
  use Lightning.DataCase, async: true

  # alias Lightning.Storage
  alias Lightning.Storage.ProjectFileDefinition
  alias Lightning.Projects.ProjectFile

  setup do
    %{project: insert(:project)}
  end

  test "store and url", %{project: project} do
    {:ok, path} = touch_temp_zip()

    project_file = %ProjectFile{id: Ecto.UUID.generate(), project_id: project.id}

    {:ok, file} =
      ProjectFileDefinition.store({path, project_file})

    assert ProjectFileDefinition.url({file, project_file}) ==
             "//archives/#{project_file.project_id}/#{project_file.id}.zip"
  end

  test "using ecto", %{project: project} do
    {:ok, path} = touch_temp_zip()

    {:ok, project_file} =
      ProjectFile.new(%{
        project: project,
        created_by: insert(:user),
        type: :archive
      })
      |> Repo.insert!()
      |> ProjectFile.attach_file(path)
      |> Repo.update()

    assert ProjectFileDefinition.url({project_file.file, project_file}) =~
             "//archives/#{project_file.project_id}/#{project_file.id}.zip?"
  end

  defp touch_temp_zip() do
    Briefly.create(extname: ".zip")
    |> tap(fn {:ok, path} ->
      File.write!(path, "Hello, I'm not really a zip")
    end)
  end
end
