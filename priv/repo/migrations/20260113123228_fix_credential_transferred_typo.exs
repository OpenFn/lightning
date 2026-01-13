defmodule Lightning.Repo.Migrations.FixCredentialTransferredTypo do
  use Ecto.Migration

  def change do
    execute(
      "UPDATE audit_events SET event = 'transferred' WHERE event = 'transfered' AND item_type = 'credential'",
      "UPDATE audit_events SET event = 'transfered' WHERE event = 'transferred' AND item_type = 'credential'"
    )
  end
end
