defmodule Lightning.Projects.EnvironmentTest do
  use Lightning.DataCase, async: true

  alias Lightning.Projects.Environment

  describe "fetch/1" do
    test "answers from whatever carries a project, without loading one twice" do
      project = insert(:project, env: "staging")

      # a project
      assert {:ok, "staging"} = Environment.fetch(project)
      # its id
      assert {:ok, "staging"} = Environment.fetch(project.id)
      # anything holding the id, which is what lets the channel proxy ask
      # without preloading a project it does not otherwise need
      assert {:ok, "staging"} = Environment.fetch(%{project_id: project.id})
    end

    test "a sandbox with no environment is refused, not guessed" do
      root = insert(:project, env: "main")
      sandbox = insert(:project, parent_id: root.id, env: nil)

      assert {:error, :environment_not_configured} = Environment.fetch(sandbox)
    end

    test "a root project with no environment falls back, since nothing sits above it" do
      root = insert(:project, env: nil)

      assert {:ok, "main"} = Environment.fetch(root)
    end

    test "an unknown project is an error rather than a default" do
      assert {:error, :project_not_found} =
               Environment.fetch(Ecto.UUID.generate())

      assert {:error, :project_not_found} = Environment.fetch(nil)
    end

    test "a malformed id is refused rather than raising" do
      # Repo.get raises on a bad binary_id, which would turn this refusal into a
      # 500 at whichever caller passed it on.
      assert {:error, :project_not_found} = Environment.fetch("not-a-uuid")
      assert {:error, :project_not_found} = Environment.fetch(%{project_id: "x"})
    end

    test "a run resolves through its project" do
      project = insert(:project, env: "staging")
      workflow = insert(:workflow, project: project)

      run =
        insert(:run,
          work_order: insert(:workorder, workflow: workflow),
          dataclip: insert(:dataclip, project: project),
          starting_job: insert(:job, workflow: workflow)
        )

      assert {:ok, "staging"} = Environment.fetch(run)
    end
  end
end
