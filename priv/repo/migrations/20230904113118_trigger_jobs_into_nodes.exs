defmodule Lightning.Repo.Migrations.TriggerJobsIntoNodes do
  use Ecto.Migration

  def change do
    create table(:workflow_nodes, primary_key: false) do
      add :id, :binary_id, primary_key: true, default: fragment("gen_random_uuid()")
      add :workflow_id, references(:workflows, type: :binary_id, on_delete: :delete_all),
        null: false

      add :job_id, references(:jobs, type: :binary_id, on_delete: :delete_all), null: true

      add :trigger_id, references(:triggers, type: :binary_id, on_delete: :delete_all),
        null: true
    end

    create index(:workflow_nodes, [:workflow_id, :job_id], unique: true)
    create index(:workflow_nodes, [:workflow_id, :trigger_id], unique: true)

    create(
      constraint(
        :workflow_nodes,
        :validate_job_or_trigger,
        check: "(job_id IS NOT NULL) OR (trigger_id IS NOT NULL)"
      )
    )

    execute """
              INSERT INTO workflow_nodes (workflow_id, job_id, trigger_id)
              SELECT workflow_id, id AS job_id, null AS trigger_id FROM jobs
              UNION
              SELECT workflow_id, null AS job_id, id AS trigger_id FROM triggers;
            """,
            ""

    alter table(:jobs) do
      modify :workflow_id, :binary_id, null: true, from: {:binary_id, null: false}
    end

    alter table(:triggers) do
      modify :workflow_id, :binary_id, null: true, from: {:binary_id, null: false}
    end

    drop unique_index(:jobs, [:id, :workflow_id]), mode: :cascade
    drop unique_index(:triggers, [:id, :workflow_id]), mode: :cascade
  end
end
