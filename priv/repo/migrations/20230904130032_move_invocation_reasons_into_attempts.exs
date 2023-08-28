defmodule Lightning.Repo.Migrations.MoveInvocationReasonsIntoAttempts do
  use Ecto.Migration

  def change do
    alter table(:attempts) do
      add :starting_node_id, references(:workflow_nodes, type: :binary_id, on_delete: :nilify_all)

      modify :reason_id, :binary_id, null: true, from: {:binary_id, null: false}
    end

    # execute """
    #   UPDATE work_orders
    #   SET trigger_id = invocation_reasons.trigger_id,
    #       dataclip_id = invocation_reasons.dataclip_id
    #   FROM invocation_reasons
    #   WHERE work_orders.reason_id = invocation_reasons.id
    # """, ""
  end
end
