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
end
