defmodule Lightning.Workflows.WorkflowVersionTest do
  use Lightning.DataCase, async: true

  import Lightning.Factories
  alias Lightning.Repo
  alias Lightning.Workflows.WorkflowVersion

  describe "changeset validations" do
    test "requires hash, source, workflow_id and validates formats" do
      cs = WorkflowVersion.changeset(%WorkflowVersion{}, %{})
      refute cs.valid?
      assert "can't be blank" in errors_on(cs).hash
      assert "can't be blank" in errors_on(cs).source
      assert "can't be blank" in errors_on(cs).workflow_id

      wf = insert(:workflow)

      # bad: uppercase hex & unknown source
      cs2 =
        WorkflowVersion.changeset(%WorkflowVersion{}, %{
          hash: "ABCDEF123456",
          source: "web",
          workflow_id: wf.id
        })

      refute cs2.valid?
      assert "has invalid format" in errors_on(cs2).hash
      assert "is invalid" in errors_on(cs2).source

      # good
      cs3 =
        WorkflowVersion.changeset(%WorkflowVersion{}, %{
          hash: "deadbeefcafe",
          source: "app",
          workflow_id: wf.id
        })

      assert cs3.valid?
    end

    test "foreign_key_constraint(:workflow_id)" do
      cs =
        WorkflowVersion.changeset(%WorkflowVersion{}, %{
          hash: "aaaaaaaaaaaa",
          source: "cli",
          workflow_id: Ecto.UUID.generate()
        })

      assert {:error, cs} = Repo.insert(cs)
      # foreign_key_constraint(:workflow_id) places error on :workflow
      assert "does not exist" in errors_on(cs).workflow_id
    end
  end

  describe "uniqueness & timestamps" do
    test "hash not unique" do
      wf1 = insert(:workflow)
      wf2 = insert(:workflow)

      # same hash, same workflow -> allowed
      assert {:ok, _} =
               %WorkflowVersion{}
               |> WorkflowVersion.changeset(%{
                 hash: "aaaaaaaaaaaa",
                 source: "app",
                 workflow_id: wf1.id
               })
               |> Repo.insert()

      assert {:ok, _} =
               %WorkflowVersion{}
               |> WorkflowVersion.changeset(%{
                 hash: "aaaaaaaaaaaa",
                 source: "cli",
                 workflow_id: wf1.id
               })
               |> Repo.insert()

      # same hash, different workflow -> allowed
      assert {:ok, _} =
               %WorkflowVersion{}
               |> WorkflowVersion.changeset(%{
                 hash: "aaaaaaaaaaaa",
                 source: "cli",
                 workflow_id: wf2.id
               })
               |> Repo.insert()

      # different hash, same workflow -> allowed
      assert {:ok, _} =
               %WorkflowVersion{}
               |> WorkflowVersion.changeset(%{
                 hash: "bbbbbbbbbbbb",
                 source: "app",
                 workflow_id: wf1.id
               })
               |> Repo.insert()
    end

    test "timestamps: inserted_at is utc with microseconds; no updated_at field" do
      wf = insert(:workflow)

      assert {:ok, v} =
               %WorkflowVersion{}
               |> WorkflowVersion.changeset(%{
                 hash: "cccccccccccc",
                 source: "app",
                 workflow_id: wf.id
               })
               |> Repo.insert()

      # inserted_at present and has microseconds
      assert %DateTime{} = v.inserted_at
      assert match?({_, 6}, v.inserted_at.microsecond)

      # updated_at is disabled in the schema
      refute Map.has_key?(v, :updated_at)
    end
  end
end
