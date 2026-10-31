defmodule Lightning.Workflows.TriggerCustomPathTest do
  use Lightning.DataCase, async: true

  import Lightning.Factories

  alias Lightning.Workflows.Trigger

  # `Sandboxes` retries an insert without the path when, and only when, this
  # says the path was refused on its shape. Getting it wrong the other way
  # would write a duplicate path back with `update_all`.
  describe "custom_path_shape_error?/1" do
    test "is true for a path refused on its characters" do
      changeset =
        Trigger.changeset(%Trigger{}, %{
          type: :webhook,
          custom_path: "some/legacy/path"
        })

      assert Trigger.custom_path_shape_error?(changeset)
    end

    test "is true for a path refused on its length" do
      changeset =
        Trigger.changeset(%Trigger{}, %{
          type: :webhook,
          custom_path: String.duplicate("a", 256)
        })

      assert Trigger.custom_path_shape_error?(changeset)
    end

    test "is true for a UUID-shaped path" do
      changeset =
        Trigger.changeset(%Trigger{}, %{
          type: :webhook,
          custom_path: Ecto.UUID.generate()
        })

      assert Trigger.custom_path_shape_error?(changeset)
    end

    test "is false for a path already used in the project" do
      project = insert(:project)
      workflow = insert(:workflow, project: project)
      insert(:trigger, type: :webhook, workflow: workflow, custom_path: "taken")

      other_workflow = insert(:workflow, project: project)

      assert {:error, changeset} =
               %Trigger{}
               |> Trigger.changeset(%{
                 type: :webhook,
                 workflow_id: other_workflow.id,
                 custom_path: "taken"
               })
               |> Lightning.Repo.insert()

      assert Keyword.has_key?(changeset.errors, :custom_path)
      refute Trigger.custom_path_shape_error?(changeset)
    end

    test "is false for a path whose trigger has no project" do
      assert {:error, changeset} =
               %Trigger{}
               |> Trigger.changeset(%{
                 type: :webhook,
                 workflow_id: Ecto.UUID.generate(),
                 custom_path: "orphan"
               })
               |> Lightning.Repo.insert()

      assert Keyword.has_key?(changeset.errors, :custom_path)
      refute Trigger.custom_path_shape_error?(changeset)
    end

    test "is false when the failure is on another field" do
      changeset =
        Trigger.changeset(%Trigger{}, %{
          type: :cron,
          cron_expression: "not a cron expression"
        })

      refute changeset.valid?
      refute Keyword.has_key?(changeset.errors, :custom_path)
      refute Trigger.custom_path_shape_error?(changeset)
    end
  end

  describe "changeset/2 trimming and shape" do
    test "a blank path clears a path that was set" do
      stored = %Trigger{type: :webhook, custom_path: "orders"}

      for blank <- ["", "   ", "\t"] do
        changeset = Trigger.changeset(stored, %{custom_path: blank})

        assert changeset.valid?
        assert Ecto.Changeset.fetch_change(changeset, :custom_path) == {:ok, nil}
      end
    end

    test "a blank path on a new trigger leaves it with none" do
      changeset =
        Trigger.changeset(%Trigger{}, %{type: :webhook, custom_path: "   "})

      assert changeset.valid?
      refute Ecto.Changeset.get_field(changeset, :custom_path)
    end

    test "a path is stored trimmed" do
      changeset =
        Trigger.changeset(%Trigger{}, %{
          type: :webhook,
          custom_path: "  facility-001  "
        })

      assert changeset.valid?

      assert Ecto.Changeset.get_change(changeset, :custom_path) ==
               "facility-001"
    end

    test "a 36-character path that is not a UUID is allowed" do
      # The length a UUID happens to be. Only a real one is refused, since only
      # a real one would resolve against a trigger id.
      path = String.duplicate("a", 36)

      changeset =
        Trigger.changeset(%Trigger{}, %{type: :webhook, custom_path: path})

      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :custom_path) == path
    end
  end

  describe "changeset/2 and a grandfathered bare path" do
    setup do
      project = insert(:project)
      workflow = insert(:workflow, project: project)

      trigger =
        insert(:trigger,
          type: :webhook,
          workflow: workflow,
          custom_path: "orders"
        )

      Lightning.Repo.update_all(
        Ecto.Query.from(t in Trigger, where: t.id == ^trigger.id),
        set: [legacy_bare_path: true]
      )

      %{trigger: Lightning.Repo.reload!(trigger)}
    end

    test "survives a write that trims back to the stored path", %{
      trigger: trigger
    } do
      changeset = Trigger.changeset(trigger, %{custom_path: "  orders  "})

      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :legacy_bare_path)
    end

    test "is dropped by a real rename", %{trigger: trigger} do
      changeset = Trigger.changeset(trigger, %{custom_path: "orders-v2"})

      assert changeset.valid?
      refute Ecto.Changeset.get_field(changeset, :legacy_bare_path)
    end
  end
end
