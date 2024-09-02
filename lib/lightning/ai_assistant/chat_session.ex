defmodule Lightning.AiAssistant.ChatSession do
  @moduledoc false

  use Lightning.Schema
  import Ecto.Changeset

  alias Lightning.Accounts.User
  alias Lightning.AiAssistant.ChatMessage
  alias Lightning.Workflows.Job

  @type t() :: %__MODULE__{
          id: Ecto.UUID.t(),
          job_id: Ecto.UUID.t(),
          user_id: Ecto.UUID.t(),
          title: String.t(),
          expression: String.t() | nil,
          adaptor: String.t() | nil,
          is_public: boolean(),
          is_deleted: boolean(),
          messages: [ChatMessage.t(), ...] | []
        }

  schema "ai_chat_sessions" do
    field :expression, :string, virtual: true
    field :adaptor, :string, virtual: true
    field :title, :string
    field :is_public, :boolean, default: false
    field :is_deleted, :boolean, default: false
    belongs_to :job, Job
    belongs_to :user, User

    has_many :messages, ChatMessage, preload_order: [asc: :inserted_at]

    timestamps()
  end

  def changeset(chat_session, attrs) do
    chat_session
    |> cast(attrs, [:title, :is_public, :is_deleted, :job_id, :user_id])
    |> validate_required([:title, :job_id, :user_id])
    |> cast_assoc(:messages)
  end
end
