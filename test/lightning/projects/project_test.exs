defmodule Lightning.Projects.ProjectTest do
  use Lightning.DataCase, async: true
  import Lightning.Factories
  alias Lightning.Projects.Project
  alias Lightning.Repo

  describe "changeset/2 validations" do
    test "requires name and enforces slug format" do
      cs = Project.changeset(%Project{}, %{})
      refute cs.valid?
      assert "can't be blank" in errors_on(cs).name

      cs2 = Project.changeset(%Project{}, %{name: "not ok"})
      refute cs2.valid?
      assert "has invalid format" in errors_on(cs2).name
    end

    test "color must be hex and env must be short slug" do
      ok =
        Project.changeset(%Project{}, %{
          name: "p1",
          color: "#a1b2c3",
          env: "staging_1"
        })

      assert ok.valid?

      bad =
        Project.changeset(%Project{}, %{
          name: "p2",
          color: "blue",
          env: "NOPE!!"
        })

      refute bad.valid?
      assert "must be hex" in errors_on(bad).color
      assert "must be a short slug" in errors_on(bad).env
    end

    test "dataclip_retention_period <= history_retention_period" do
      cs =
        Project.changeset(%Project{}, %{
          name: "p3",
          history_retention_period: 7,
          dataclip_retention_period: 14
        })

      refute cs.valid?

      assert "dataclip retention period must be less or equal to the history retention period" in errors_on(
               cs
             ).dataclip_retention_period
    end

    test "dataclip_retention_period is nulled when history is nil or policy is :erase_all" do
      # history nil
      cs1 =
        Project.changeset(%Project{}, %{
          name: "p4",
          history_retention_period: nil,
          dataclip_retention_period: 7
        })

      assert Ecto.Changeset.get_change(cs1, :dataclip_retention_period) == nil

      # erase_all
      cs2 =
        Project.changeset(%Project{}, %{
          name: "p5",
          retention_policy: :erase_all,
          history_retention_period: 30,
          dataclip_retention_period: 7
        })

      assert Ecto.Changeset.get_change(cs2, :dataclip_retention_period) == nil
    end

    test "disallows parent_id == id (self parent)" do
      proj = insert(:project)
      cs = Project.changeset(proj, %{parent_id: proj.id})
      refute cs.valid?
      assert "cannot be self" in errors_on(cs).parent_id
    end
  end

  describe "unique name scoped to parent (sandboxes)" do
    test "allows duplicate names at top-level and across different parents" do
      # two root projects with the same name are allowed
      assert {:ok, _} =
               %Project{} |> Project.changeset(%{name: "same"}) |> Repo.insert()

      assert {:ok, _} =
               %Project{} |> Project.changeset(%{name: "same"}) |> Repo.insert()

      # same sandbox name under different parents is allowed
      p1 = insert(:project, name: "parent-1")
      p2 = insert(:project, name: "parent-2")

      assert {:ok, _} =
               %Project{}
               |> Project.changeset(%{name: "sandbox", parent_id: p1.id})
               |> Repo.insert()

      assert {:ok, _} =
               %Project{}
               |> Project.changeset(%{name: "sandbox", parent_id: p2.id})
               |> Repo.insert()
    end

    test "rejects duplicate child names under the same parent" do
      parent = insert(:project, name: "parent-x")

      assert {:ok, _} =
               %Project{}
               |> Project.changeset(%{name: "sb", parent_id: parent.id})
               |> Repo.insert()

      {:error, cs} =
        %Project{}
        |> Project.changeset(%{name: "sb", parent_id: parent.id})
        |> Repo.insert()

      assert "has already been taken" in errors_on(cs).name
    end
  end

  describe "deletion_changeset/2" do
    test "requires name confirmation to match" do
      p = insert(:project, name: "demo")

      ok =
        Project.deletion_changeset(p, %{
          "name" => "demo",
          "name_confirmation" => "demo"
        })

      assert ok.valid?

      bad =
        Project.deletion_changeset(p, %{
          "name" => "demo",
          "name_confirmation" => "nope"
        })

      refute bad.valid?
      assert "doesn't match the project name" in errors_on(bad).name_confirmation
    end
  end

  describe "sandbox?/1" do
    test "false for root, true for child" do
      root = insert(:project)
      child = insert(:project, parent: root)
      refute Project.sandbox?(root)
      assert Project.sandbox?(child)
    end
  end
end
