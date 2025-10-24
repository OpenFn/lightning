defmodule Lightning.Repo.Migrations.AddDelayedResponseToTriggers do
  use Ecto.Migration

  def change do
    alter table(:triggers) do
      add :webhook_reply, :string, default: "before_start", null: false
    end
  end
end
