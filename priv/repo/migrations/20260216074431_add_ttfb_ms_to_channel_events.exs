defmodule Lightning.Repo.Migrations.AddTtfbMsToChannelEvents do
  use Ecto.Migration

  def change do
    alter table(:channel_events) do
      add :ttfb_ms, :integer
    end
  end
end
