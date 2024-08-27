defmodule Lightning.AiAssistant.ChatMessage do
  use Lightning.Schema
  import Ecto.Changeset

  @type role() :: :user | :assistant
  @type t() :: %__MODULE__{id: Ecto.UUID.t(), content: String.t(), role: role()}

  schema "ai_chat_messages" do
    field :content, :string
    field :role, Ecto.Enum, values: [:user, :assistant]
    field :is_deleted, :boolean, default: false
    field :is_public, :boolean, default: true

    belongs_to :chat_session, Lightning.AiAssistant.ChatSession
    belongs_to :user, Lightning.Accounts.User

    timestamps()
  end

  def changeset(chat_message, attrs) do
    chat_message
    |> cast(attrs, [
      :content,
      :role,
      :is_deleted,
      :is_public,
      :chat_session_id,
      :user_id
    ])
    |> validate_required([:content, :role])
  end
end
