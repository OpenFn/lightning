defmodule Lightning.Repo.Migrations.AddWebhookResponseConfigToTriggers do
  use Ecto.Migration

  def change do
    alter table(:triggers) do
      add :webhook_response_config, :jsonb, null: true
    end
  end
end
