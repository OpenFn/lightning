defmodule Lightning.Repo.Migrations.AddFinalDataclipToRuns do
  use Ecto.Migration

  def change do
    alter table(:runs) do
      add :final_dataclip_id, references(:dataclips, type: :binary_id, on_delete: :delete_all),
        null: true
    end

    create index(:runs, [:final_dataclip_id])
  end
end
