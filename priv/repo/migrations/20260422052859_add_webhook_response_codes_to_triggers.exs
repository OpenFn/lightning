defmodule Lightning.Repo.Migrations.AddWebhookResponseCodesToTriggers do
  use Ecto.Migration

  def change do
    alter table(:triggers) do
      add :sync_webhook_response_config, :jsonb, null: true
    end
  end
end
