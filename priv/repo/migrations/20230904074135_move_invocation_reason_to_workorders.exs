defmodule Lightning.Repo.Migrations.MoveInvocationReasonToWorkorders do
  use Ecto.Migration

  def change do
    alter table(:work_orders) do
      add :trigger_id, references(:triggers, type: :binary_id, on_delete: :nilify_all), null: true

      add :dataclip_id, references(:dataclips, type: :binary_id, on_delete: :nilify_all),
        null: true

      modify :reason_id, :binary_id, null: true, from: {:binary_id, null: false}
    end

    execute """
              UPDATE work_orders
              SET trigger_id = invocation_reasons.trigger_id,
                  dataclip_id = invocation_reasons.dataclip_id
              FROM invocation_reasons
              WHERE work_orders.reason_id = invocation_reasons.id
            """,
            ""

    alter table(:work_orders) do
      modify :dataclip_id, :binary_id, null: true, from: {:binary_id, null: false}
    end
  end
end
