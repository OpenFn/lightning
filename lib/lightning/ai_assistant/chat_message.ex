defmodule Lightning.AiAssistant.ChatMessage do
  @moduledoc false

  use Lightning.Schema
  import Ecto.Changeset
  import Lightning.Validators, only: [validate_required_assoc: 2]

  @type role() :: :user | :assistant
  @type t() :: %__MODULE__{
          id: Ecto.UUID.t(),
          content: String.t() | nil,
          role: role(),
          is_deleted: boolean(),
          is_public: boolean()
        }

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
      :chat_session_id
    ])
    |> validate_required([:content, :role])
    |> maybe_put_user_assoc(attrs[:user] || attrs["user"])
    |> maybe_require_user()
  end

  defp maybe_put_user_assoc(changeset, user) do
    if user do
      put_assoc(changeset, :user, user)
    else
      changeset
    end
  end

  defp maybe_require_user(changeset) do
    if get_field(changeset, :role) == :user do
      validate_required_assoc(changeset, :user)
    else
      changeset
    end
  end
end
