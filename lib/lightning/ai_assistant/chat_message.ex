defmodule Lightning.AiAssistant.ChatMessage do
  @moduledoc false

  use Lightning.Schema
  import Ecto.Changeset
  import Lightning.Validators, only: [validate_required_assoc: 2]

  @type role() :: :user | :assistant
  @type status() :: :success | :error | :cancelled

  @type t() :: %__MODULE__{
          id: Ecto.UUID.t(),
          content: String.t() | nil,
          role: role(),
          status: status(),
          is_deleted: boolean(),
          is_public: boolean(),
          rag_results: map() | nil,
          prompt: String.t() | nil
        }

  schema "ai_chat_messages" do
    field :content, :string
    field :role, Ecto.Enum, values: [:user, :assistant]
    field :rag_results, :map
    field :prompt, :string

    field :status, Ecto.Enum,
      values: [:success, :error, :cancelled],
      default: :success

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
      :status,
      :is_deleted,
      :is_public,
      :chat_session_id,
      :rag_results,
      :prompt
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
