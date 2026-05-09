defmodule Lightning.VersionControl.ProjectRepoConnectionTest do
  use Lightning.DataCase, async: true

  alias Lightning.VersionControl.ProjectRepoConnection

  import Lightning.Factories

  @tree_branch_error "this branch is already linked to another project in the same project family; use a different branch"

  describe "validate_no_tree_branch_conflict in changeset/2" do
    test "rejects sandbox claiming the same (repo, branch) as its direct parent" do
      parent = insert(:project)

      insert(:project_repo_connection,
        project: parent,
        repo: "openfn/example",
        branch: "main"
      )

      sandbox = insert(:project, parent: parent)

      changeset =
        ProjectRepoConnection.changeset(%ProjectRepoConnection{}, %{
          project_id: sandbox.id,
          repo: "openfn/example",
          branch: "main",
          github_installation_id: "1234"
        })

      refute changeset.valid?
      assert {@tree_branch_error, _} = changeset.errors[:branch]
    end

    test "rejects grandchild sandbox claiming a grandparent's (repo, branch)" do
      grandparent = insert(:project)

      insert(:project_repo_connection,
        project: grandparent,
        repo: "openfn/example",
        branch: "main"
      )

      parent = insert(:project, parent: grandparent)
      grandchild = insert(:project, parent: parent)

      changeset =
        ProjectRepoConnection.changeset(%ProjectRepoConnection{}, %{
          project_id: grandchild.id,
          repo: "openfn/example",
          branch: "main",
          github_installation_id: "1234"
        })

      refute changeset.valid?
      assert {@tree_branch_error, _} = changeset.errors[:branch]
    end

    test "rejects sibling sandboxes from sharing the same (repo, branch)" do
      parent = insert(:project)
      sibling_a = insert(:project, parent: parent)
      sibling_b = insert(:project, parent: parent)

      insert(:project_repo_connection,
        project: sibling_a,
        repo: "openfn/example",
        branch: "dev"
      )

      changeset =
        ProjectRepoConnection.changeset(%ProjectRepoConnection{}, %{
          project_id: sibling_b.id,
          repo: "openfn/example",
          branch: "dev",
          github_installation_id: "1234"
        })

      refute changeset.valid?
      assert {@tree_branch_error, _} = changeset.errors[:branch]
    end

    test "rejects a parent claiming a (repo, branch) already taken by its sandbox" do
      parent = insert(:project)
      sandbox = insert(:project, parent: parent)

      insert(:project_repo_connection,
        project: sandbox,
        repo: "openfn/example",
        branch: "feature"
      )

      changeset =
        ProjectRepoConnection.changeset(%ProjectRepoConnection{}, %{
          project_id: parent.id,
          repo: "openfn/example",
          branch: "feature",
          github_installation_id: "1234"
        })

      refute changeset.valid?
      assert {@tree_branch_error, _} = changeset.errors[:branch]
    end

    test "allows a sandbox to share parent's repo on a different branch" do
      parent = insert(:project)

      insert(:project_repo_connection,
        project: parent,
        repo: "openfn/example",
        branch: "main"
      )

      sandbox = insert(:project, parent: parent)

      changeset =
        ProjectRepoConnection.changeset(%ProjectRepoConnection{}, %{
          project_id: sandbox.id,
          repo: "openfn/example",
          branch: "dev",
          github_installation_id: "1234"
        })

      assert changeset.valid?
      refute changeset.errors[:branch]
    end

    test "allows a sandbox to share parent's branch on a different repo" do
      parent = insert(:project)

      insert(:project_repo_connection,
        project: parent,
        repo: "openfn/example",
        branch: "main"
      )

      sandbox = insert(:project, parent: parent)

      changeset =
        ProjectRepoConnection.changeset(%ProjectRepoConnection{}, %{
          project_id: sandbox.id,
          repo: "openfn/other",
          branch: "main",
          github_installation_id: "1234"
        })

      assert changeset.valid?
      refute changeset.errors[:branch]
    end

    test "non-sandbox project (no parent) is unaffected when no other project in its tree uses the (repo, branch)" do
      project = insert(:project)

      changeset =
        ProjectRepoConnection.changeset(%ProjectRepoConnection{}, %{
          project_id: project.id,
          repo: "openfn/example",
          branch: "main",
          github_installation_id: "1234"
        })

      assert changeset.valid?
      refute changeset.errors[:branch]
    end

    test "unrelated projects (separate trees) may share the same (repo, branch)" do
      tree_a = insert(:project)
      tree_b = insert(:project)

      insert(:project_repo_connection,
        project: tree_a,
        repo: "openfn/example",
        branch: "main"
      )

      changeset =
        ProjectRepoConnection.changeset(%ProjectRepoConnection{}, %{
          project_id: tree_b.id,
          repo: "openfn/example",
          branch: "main",
          github_installation_id: "1234"
        })

      assert changeset.valid?
      refute changeset.errors[:branch]
    end

    test "skips validation when one of (project_id, repo, branch) is missing" do
      parent = insert(:project)

      insert(:project_repo_connection,
        project: parent,
        repo: "openfn/example",
        branch: "main"
      )

      sandbox = insert(:project, parent: parent)

      # No branch supplied — validation is skipped (other validations may still fail).
      changeset =
        ProjectRepoConnection.changeset(%ProjectRepoConnection{}, %{
          project_id: sandbox.id,
          repo: "openfn/example",
          github_installation_id: "1234"
        })

      refute changeset.errors[:branch] == {@tree_branch_error, []}
    end
  end

  describe "validate_no_tree_branch_conflict in configure_changeset/2" do
    test "rejects on configure_changeset path too" do
      parent = insert(:project)

      insert(:project_repo_connection,
        project: parent,
        repo: "openfn/example",
        branch: "main"
      )

      sandbox = insert(:project, parent: parent)

      changeset =
        ProjectRepoConnection.configure_changeset(%ProjectRepoConnection{}, %{
          project_id: sandbox.id,
          repo: "openfn/example",
          branch: "main",
          github_installation_id: "1234",
          sync_direction: "pull",
          accept: true
        })

      refute changeset.valid?
      assert {@tree_branch_error, _} = changeset.errors[:branch]
    end
  end

  describe "tree_branch_conflict?/4" do
    test "returns false when no other connection in the tree uses the (repo, branch)" do
      root = insert(:project)

      refute ProjectRepoConnection.tree_branch_conflict?(
               root.id,
               "openfn/example",
               "main"
             )
    end

    test "returns true when another connection in the same tree uses the (repo, branch)" do
      root = insert(:project)

      insert(:project_repo_connection,
        project: root,
        repo: "openfn/example",
        branch: "main"
      )

      assert ProjectRepoConnection.tree_branch_conflict?(
               root.id,
               "openfn/example",
               "main"
             )
    end

    test "returns false when a different branch is used in the tree" do
      root = insert(:project)

      insert(:project_repo_connection,
        project: root,
        repo: "openfn/example",
        branch: "main"
      )

      refute ProjectRepoConnection.tree_branch_conflict?(
               root.id,
               "openfn/example",
               "dev"
             )
    end

    test "excludes self_id so a row doesn't conflict with itself" do
      root = insert(:project)

      conn =
        insert(:project_repo_connection,
          project: root,
          repo: "openfn/example",
          branch: "main"
        )

      refute ProjectRepoConnection.tree_branch_conflict?(
               root.id,
               "openfn/example",
               "main",
               conn.id
             )
    end
  end
end
