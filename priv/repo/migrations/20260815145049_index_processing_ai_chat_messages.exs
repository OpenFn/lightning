defmodule Lightning.Repo.Migrations.IndexProcessingAiChatMessages do
  use Ecto.Migration

  def change do
    # The reaper scans for stale :processing messages every five minutes. That
    # set should be empty almost always, so a partial index keeps the scan off
    # the table.
    create index(:ai_chat_messages, [:processing_started_at],
             where: "status = 'processing'",
             name: :ai_chat_messages_stuck_idx
           )
  end
end
