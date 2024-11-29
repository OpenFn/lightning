defmodule Lightning.Workflows.AuditTest do
  use Lightning.DataCase, async: true

  alias Lightning.Workflows.Audit

  describe ".snapshot_created/3" do
    test "saves a `snapshot_created` event" do
      %{id: user_id} = user = insert(:user)
      snapshot_id = Ecto.UUID.generate()
      workflow_id = Ecto.UUID.generate()

      changeset = Audit.snapshot_created(workflow_id, snapshot_id, user)

      assert %{
               changes: %{
                 event: "snapshot_created",
                 item_id: ^workflow_id,
                 item_type: "workflow",
                 actor_id: ^user_id,
                 changes: %{
                   changes: %{
                     after: %{
                       snapshot_id: ^snapshot_id
                     }
                   }
                 }
               }
             } = changeset
    end
  end

  describe ".provisioner_event/2" do
    test "returns a changeset for an `insert` event" do
      %{id: user_id} = user = insert(:user)
      workflow_id = Ecto.UUID.generate()

      changeset = Audit.provisioner_event(:insert, workflow_id, user)

      assert %{
               changes: %{
                 event: "inserted_by_provisioner",
                 item_id: ^workflow_id,
                 item_type: "workflow",
                 actor_id: ^user_id,
                 changes: %{
                   changes: changes
                 }
               },
               valid?: true
             } = changeset

      assert changes == %{}
    end

    test "returns a changeset for a `delete` event" do
      %{id: user_id} = user = insert(:user)
      workflow_id = Ecto.UUID.generate()

      changeset = Audit.provisioner_event(:delete, workflow_id, user)

      assert %{
               changes: %{
                 event: "deleted_by_provisioner",
                 item_id: ^workflow_id,
                 item_type: "workflow",
                 actor_id: ^user_id,
                 changes: %{
                   changes: changes
                 }
               },
               valid?: true
             } = changeset

      assert changes == %{}
    end

    test "returns a changeset for a `update` event" do
      %{id: user_id} = user = insert(:user)
      workflow_id = Ecto.UUID.generate()

      changeset = Audit.provisioner_event(:update, workflow_id, user)

      assert %{
               changes: %{
                 event: "updated_by_provisioner",
                 item_id: ^workflow_id,
                 item_type: "workflow",
                 actor_id: ^user_id,
                 changes: %{
                   changes: changes
                 }
               },
               valid?: true
             } = changeset

      assert changes == %{}
    end
  end
end
