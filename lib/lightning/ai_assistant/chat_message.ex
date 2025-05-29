defmodule Lightning.AiAssistant.ChatMessage do
  @moduledoc false

  use Lightning.Schema
  import Ecto.Changeset
  import Lightning.Validators, only: [validate_required_assoc: 2]

  @type role() :: :user | :assistant
  @type status() :: :pending | :success | :error | :cancelled

  @type t() :: %__MODULE__{
          id: Ecto.UUID.t(),
          content: String.t() | nil,
          workflow_code: String.t() | nil,
          role: role(),
          status: status(),
          is_deleted: boolean(),
          is_public: boolean()
        }

  schema "ai_chat_messages" do
    field :content, :string
    field :workflow_code, :string
    field :role, Ecto.Enum, values: [:user, :assistant]

    field :status, Ecto.Enum, values: [:pending, :success, :error, :cancelled]

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
      :workflow_code,
      :role,
      :status,
      :is_deleted,
      :is_public,
      :chat_session_id
    ])
    |> validate_required([:content, :role])
    |> maybe_put_user_assoc(attrs[:user] || attrs["user"])
    |> maybe_require_user()
    |> set_default_status_by_role()
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

  defp set_default_status_by_role(changeset) do
    role = get_field(changeset, :role)
    current_status = get_field(changeset, :status)

    case {role, current_status} do
      {:user, nil} -> put_change(changeset, :status, :pending)
      {:assistant, nil} -> put_change(changeset, :status, :success)
      _ -> changeset
    end
  end
end
