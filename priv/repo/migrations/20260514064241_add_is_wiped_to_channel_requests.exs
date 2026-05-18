defmodule Lightning.Repo.Migrations.AddIsWipedToChannelRequests do
  use Ecto.Migration

  def change do
    alter table(:channel_requests) do
      add :is_wiped, :boolean, null: false, default: false
    end
  end
end
