defmodule Lightning.Repo.Migrations.ModifyLogLinesBody do
  use Ecto.Migration

  def change do
    alter table(:log_lines) do
      modify :body, :string, null: false
    end
  end
end
