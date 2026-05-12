defmodule Lightning.Repo.Migrations.AddClientAuthTrackingToChannelRequests do
  use Ecto.Migration

  def change do
    alter table(:channel_requests) do
      add :client_webhook_auth_method_id,
          references(:webhook_auth_methods, type: :binary_id, on_delete: :nilify_all)

      add :client_auth_type, :string
    end

    create index(:channel_requests, [:client_webhook_auth_method_id])
  end
end
