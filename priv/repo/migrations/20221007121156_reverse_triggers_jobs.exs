defmodule Lightning.Repo.Migrations.ReverseTriggersJobs do
  use Ecto.Migration

  def change do
    alter table(:jobs) do
      add :trigger_id, references(:triggers, on_delete: :nothing, type: :uuid), null: true
    end

    execute(
      fn ->
        repo().query!(
          """
          UPDATE jobs
          SET trigger_id=subquery.trigger_id
          FROM (
            SELECT
              j.id AS job_id,
              t.id AS trigger_id
            FROM triggers t
            LEFT JOIN jobs j ON t.job_id = j.id
          ) AS subquery
          WHERE jobs.id = subquery.job_id;
          """,
          [],
          log: :info
        )
      end,
      fn ->
        repo().query!(
          """
          UPDATE triggers
          SET job_id=subquery.job_id
          FROM (
            SELECT
              t.id AS trigger_id,
              j.id AS job_id,
              j.workflow_id AS workflow_id
            FROM triggers t
            LEFT JOIN jobs j ON t.id = j.trigger_id
          ) AS subquery
          WHERE triggers.id = subquery.trigger_id;
          """,
          [],
          log: :info
        )
      end
    )

    alter table(:triggers) do
      remove :job_id, references(:jobs, on_delete: :delete_all, type: :binary_id), null: false
      add :workflow_id, references(:workflows, on_delete: :delete_all, type: :uuid), null: true
    end

    execute(
      fn ->
        repo().query!(
          """
          UPDATE triggers
          SET workflow_id=subquery.workflow_id
          FROM (
            SELECT
              t.id AS trigger_id,
              j.id AS job_id,
              j.workflow_id AS workflow_id
            FROM triggers t
            LEFT JOIN jobs j ON t.id = j.trigger_id
          ) AS subquery
          WHERE triggers.id = subquery.trigger_id;
          """,
          [],
          log: :info
        )
      end,
      fn -> nil end
    )

    alter table(:jobs) do
      modify :trigger_id, :uuid, null: false, from: {:uuid, null: true}
    end

    alter table(:triggers) do
      modify :workflow_id, :uuid, null: false, from: {:uuid, null: true}
    end

    create index(:triggers, [:workflow_id])
  end
end
