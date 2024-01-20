defmodule Lightning.Repo.Migrations.ModifyJobFkInRuns do
  use Ecto.Migration

  def change do
    alter table(:runs) do
      modify :job_id, references(:jobs, on_delete: :nothing, type: :binary_id),
        from: references(:jobs, on_delete: :delete_all, type: :binary_id)
    end
  end
end
