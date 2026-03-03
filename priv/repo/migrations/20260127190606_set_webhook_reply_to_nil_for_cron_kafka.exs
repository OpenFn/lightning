defmodule Lightning.Repo.Migrations.SetWebhookReplyToNilForCronKafka do
  use Ecto.Migration

  def change do
    alter table("triggers") do
      modify :webhook_reply, :string,
        null: true,
        default: nil,
        from: {:string, null: true, default: "before_start"}
    end

    execute(
      "UPDATE triggers SET webhook_reply = (CASE WHEN type = 'webhook' THEN webhook_reply ELSE NULL END)",
      "SELECT true"
    )
  end
end
