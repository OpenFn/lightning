defmodule Lightning.Repo.Migrations.ChangeRunLogToArrayOfText do
  use Ecto.Migration

  def change do
    alter table(:runs) do
      modify :log, {:array, :text}, from: {:array, :string}
    end
  end
end
