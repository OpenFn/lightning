defmodule Lightning.Projects.FileTest do
  use Lightning.DataCase, async: true

  alias Lightning.Projects.File

  test "new with valid data" do
    user = insert(:user)
    project = insert(:project)

    changeset =
      File.new(%{
        path: "path/to/file",
        size: 123,
        created_by: user,
        project: project
      })

    assert changeset.valid?
  end

  test "new with invalid data" do
    changeset =
      File.new(%{
        path: "path/to/file",
        size: 123
      })

    assert {:created_by, {"can't be blank", [validation: :required]}} in changeset.errors

    assert {:project, {"can't be blank", [validation: :required]}} in changeset.errors

    refute changeset.valid?
  end
end
