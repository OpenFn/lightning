defmodule Lightning.Repo.Migrations.AddFinalDataclipToRuns do
  use Ecto.Migration

  def change do
    alter table(:runs) do
      add :final_dataclip_id, references(:dataclips, type: :binary_id), null: true
    end
  end
end
