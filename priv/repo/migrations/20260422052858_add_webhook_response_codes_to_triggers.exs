defmodule Lightning.Repo.Migrations.AddWebhookResponseCodesToTriggers do
  use Ecto.Migration

  def change do
    alter table(:triggers) do
      add :webhook_response_success_code, :integer, null: true
      add :webhook_response_error_code, :integer, null: true
    end
  end
end
