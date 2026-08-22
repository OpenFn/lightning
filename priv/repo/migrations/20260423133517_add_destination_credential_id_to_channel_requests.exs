defmodule Lightning.Repo.Migrations.AddDestinationCredentialIdToChannelRequests do
  use Ecto.Migration

  def change do
    alter table(:channel_requests) do
      add :destination_credential_id,
          references(:project_credentials,
            type: :binary_id,
            on_delete: :nilify_all
          )
    end

    create index(:channel_requests, [:destination_credential_id])
  end
end
