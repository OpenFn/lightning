defmodule Lightning.Repo.Migrations.CascadeDeleteOnTriggerWebhookAuthMethods do
  use Ecto.Migration

  def change do
    execute "ALTER TABLE trigger_webhook_auth_methods DROP CONSTRAINT trigger_webhook_auth_methods_trigger_id_fkey"

    execute "ALTER TABLE trigger_webhook_auth_methods DROP CONSTRAINT trigger_webhook_auth_methods_webhook_auth_method_id_fkey"

    alter table(:trigger_webhook_auth_methods) do
      modify :trigger_id,
             references(:triggers, type: :binary_id, on_delete: :delete_all),
             null: false

      modify :webhook_auth_method_id,
             references(:webhook_auth_methods, type: :binary_id, on_delete: :delete_all),
             null: false
    end
  end
end
