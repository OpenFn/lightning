defmodule Lightning.Repo.Migrations.AddTypesToAttemptAndRun do
  use Ecto.Migration

  def change do
    alter table(:attempts) do
      add :error_type, :string
      # TODO: add now or later or never?
      # add :error_message, :string
    end

    alter table(:runs) do
      add :error_type, :string
      # TODO: add now or later or never?
      # add :error_message, :string
    end
  end
end
