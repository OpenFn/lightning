defmodule Lightning.Repo.Migrations.AddSandboxUsageCapsToProjects do
  use Ecto.Migration

  def change do
    alter table(:projects) do
      add :run_cap, :integer
      add :ai_tokens_cap, :integer
      add :storage_cap_mb, :integer
    end
  end
end
