defmodule Lightning.Repo.Migrations.AddResponseSegmentsToAiChatMessages do
  use Ecto.Migration

  def change do
    alter table(:ai_chat_messages) do
      # jsonb holding an array of {type, content} segment objects
      # (embeds_many on the schema); nil for flat legacy messages
      add :response_segments, :map, null: true
    end
  end
end
