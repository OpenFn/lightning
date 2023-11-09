defmodule Lightning.Repo.Migrations.CreateTriggerWebhookAuthMethodsTable do
  use Ecto.Migration

  def change do
    create table(:trigger_webhook_auth_methods, primary_key: false) do
      add :trigger_id, references(:triggers, type: :binary_id, primary_key: true)

      add :webhook_auth_method_id,
          references(:webhook_auth_methods, type: :binary_id, primary_key: true)
    end

    create unique_index(:trigger_webhook_auth_methods, [:trigger_id, :webhook_auth_method_id])
  end
end
