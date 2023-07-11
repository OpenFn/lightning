defmodule Lightning.Repo.Migrations.ModifyLogLinesBodyToText do
  use Ecto.Migration

  def change do
    alter table(:log_lines) do
      modify :body, :text, null: false
    end
  end
end
