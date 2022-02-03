defmodule Lightning.Repo.Migrations.AddJobIdToInvocationEvents do
  use Ecto.Migration

  def change do
    alter table("invocation_events") do
      add :job_id, references(:jobs, on_delete: :nothing, type: :binary_id)
    end

    create index(:invocation_events, [:job_id])
  end
end
