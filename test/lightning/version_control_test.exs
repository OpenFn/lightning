defmodule Lightning.VersionControlTest do
  use Lightning.DataCase, async: true
  alias Lightning.VersionControl
  import Lightning.Factories

  describe "Version Control" do
    test "creates a project github repo connection" do
      project = insert(:project)

      attrs = %{
        project_id: project.id,
        github_installation_id: "some id",
        target_id: "some target",
        repo: "s/r",
        branch: "main"
      }

      assert {:ok, repo_connection} =
               VersionControl.create_github_connection(attrs)

      assert repo_connection.project_id == project.id
    end
  end
end
