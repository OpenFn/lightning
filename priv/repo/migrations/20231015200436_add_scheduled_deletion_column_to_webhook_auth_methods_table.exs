defmodule Lightning.Repo.Migrations.AddScheduledDeletionColumnToWebhookAuthMethodsTable do
  use Ecto.Migration

  def change do
    alter table(:webhook_auth_methods) do
      add(:scheduled_deletion, :utc_datetime)
    end
  end
end
