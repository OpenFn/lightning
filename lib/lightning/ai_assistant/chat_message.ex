defmodule Lightning.AiAssistant.ChatMessage do
  @moduledoc """
  Represents a message within an AI chat session.

  Messages can be from users (role: :user) or from the AI assistant (role: :assistant).
  User messages start with :pending status and are updated based on processing results.
  Assistant messages typically have :success status when created.

  ## Schema Fields

  * `content` - The text content of the message (required, 1-10,000 characters)
  * `workflow_code` - Optional code associated with the message (e.g., generated workflows)
  * `role` - Who sent the message: `:user` or `:assistant`
  * `status` - Processing status: `:pending`, `:success`, `:error`, or `:cancelled`
  * `is_deleted` - Soft deletion flag (defaults to false)
  * `is_public` - Whether the message is publicly visible (defaults to true)
  * `chat_session_id` - Reference to the parent chat session
  * `user_id` - Reference to the user who sent the message (required for user messages)
  """

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
          is_public: boolean(),
          chat_session_id: Ecto.UUID.t(),
          user_id: Ecto.UUID.t() | nil,
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
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

  @doc """
  Creates a changeset for a chat message.

  ## Parameters

  * `chat_message` - The ChatMessage struct to update (typically `%ChatMessage{}`)
  * `attrs` - Map of attributes to set/update

  ## Validation Rules

  * `content` and `role` are required
  * `content` must be between 1 and 10,000 characters
  * User messages (role: `:user`) require an associated user
  * Status defaults based on role: `:pending` for users, `:success` for assistant
  * If status is explicitly provided, it takes precedence over role-based defaults

  ## Examples

      # Valid user message
      ChatMessage.changeset(%ChatMessage{}, %{
        content: "Hello AI",
        role: :user,
        user: %User{id: "123"},
        chat_session_id: "session-456"
      })

      # Valid assistant message
      ChatMessage.changeset(%ChatMessage{}, %{
        content: "Hello! How can I help?",
        role: :assistant,
        chat_session_id: "session-456"
      })

      # With explicit status (overrides default)
      ChatMessage.changeset(%ChatMessage{}, %{
        content: "Processing...",
        role: :assistant,
        status: :pending,
        chat_session_id: "session-456"
      })
  """
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
    |> validate_length(:content, min: 1, max: 10_000)
    |> maybe_put_user_assoc(attrs[:user] || attrs["user"])
    |> maybe_require_user()
    |> set_default_status_by_role()
  end

  @doc """
  Creates a changeset for updating message status.

  This is a focused changeset that only updates the status field,
  useful for updating message state during processing.

  ## Parameters

  * `chat_message` - The existing ChatMessage struct
  * `status` - New status (`:pending`, `:success`, `:error`, or `:cancelled`)

  ## Examples

      # Mark message as successful
      ChatMessage.status_changeset(message, :success)

      # Mark message as failed
      ChatMessage.status_changeset(message, :error)
  """
  def status_changeset(chat_message, status)
      when status in [:pending, :success, :error, :cancelled] do
    chat_message
    |> change(%{status: status})
  end

  defp maybe_put_user_assoc(changeset, user) when not is_nil(user) do
    put_assoc(changeset, :user, user)
  end

  defp maybe_put_user_assoc(changeset, _), do: changeset

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
