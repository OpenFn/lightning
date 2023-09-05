defmodule Lightning.Repo.Migrations.TriggerJobsIntoNodes do
  use Ecto.Migration

  def change do
    alter table(:attempts) do
      add :starting_trigger_id, references(:triggers, type: :binary_id, on_delete: :delete_all),
        null: true

      add :starting_job_id, references(:jobs, type: :binary_id, on_delete: :delete_all),
        null: true

      add :dataclip_id, references(:dataclips, type: :binary_id, on_delete: :delete_all),
        null: true

      add :created_by_id, references(:users, type: :binary_id, on_delete: :delete_all), null: true
    end

    create(
      constraint(
        :attempts,
        :validate_job_or_trigger,
        check: "(starting_job_id IS NOT NULL) OR (starting_trigger_id IS NOT NULL)"
      )
    )

    execute """
            UPDATE attempts
            SET starting_trigger_id = invocation_reasons.trigger_id,
                starting_job_id = runs.job_id,
                dataclip_id = invocation_reasons.dataclip_id
            FROM invocation_reasons
            JOIN runs ON runs.id = invocation_reasons.run_id
            WHERE attempts.reason_id = invocation_reasons.id
            """,
            ""

    # execute """
    #   UPDATE work_orders
    #   SET trigger_id = invocation_reasons.trigger_id,
    #       dataclip_id = invocation_reasons.dataclip_id
    #   FROM invocation_reasons
    #   WHERE work_orders.reason_id = invocation_reasons.id
    # """, ""

    alter table(:attempts) do
      modify :dataclip_id, :binary_id, null: true, from: {:binary_id, null: false}
      modify :reason_id, :binary_id, null: true, from: {:binary_id, null: false}
    end
  end
end
