defmodule Lightning.Repo.Migrations.SetWebhookReplyToNilForCronKafka do
  use Ecto.Migration

  def change do
    execute(
      "UPDATE triggers SET webhook_reply = (CASE WHEN type = 'webhook' THEN webhook_reply ELSE NULL END)",
      "SELECT true"
    )
  end
end
