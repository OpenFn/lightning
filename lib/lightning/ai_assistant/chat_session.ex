defmodule Lightning.AiAssistant.ChatSession do
  @moduledoc """
  Represents a chat session for AI assistance, including job code and workflow templates.

  This module defines the schema and changeset for chat sessions, including
  relationships to users, jobs, projects, and workflows. It also includes custom
  validation logic to ensure that the correct fields are populated based on the session type.
  """

  use Lightning.Schema
  import Ecto.Changeset

  alias Lightning.Accounts.User
  alias Lightning.AiAssistant.ChatMessage
  alias Lightning.Projects.Project
  alias Lightning.Workflows.Job
  alias Lightning.Workflows.Workflow

  @valid_session_types ["job_code", "workflow_template"]

  @type t() :: %__MODULE__{
          id: Ecto.UUID.t(),
          job_id: Ecto.UUID.t() | nil,
          project_id: Ecto.UUID.t() | nil,
          workflow_id: Ecto.UUID.t() | nil,
          user_id: Ecto.UUID.t(),
          title: String.t(),
          session_type: String.t(),
          expression: String.t() | nil,
          adaptor: String.t() | nil,
          is_public: boolean(),
          is_deleted: boolean(),
          meta: map() | nil,
          message_count: integer() | nil,
          messages: [ChatMessage.t()] | []
        }

  schema "ai_chat_sessions" do
    field :title, :string
    field :session_type, :string, default: "job_code"
    field :meta, :map, default: %{}
    field :is_public, :boolean, default: false
    field :is_deleted, :boolean, default: false

    field :expression, :string, virtual: true
    field :adaptor, :string, virtual: true
    field :message_count, :integer, virtual: true

    belongs_to :user, User
    belongs_to :job, Job
    belongs_to :project, Project
    belongs_to :workflow, Workflow

    has_many :messages, ChatMessage, preload_order: [asc: :inserted_at]

    timestamps()
  end

  @doc false
  def changeset(chat_session, attrs) do
    chat_session
    |> cast(attrs, [
      :title,
      :session_type,
      :is_public,
      :is_deleted,
      :job_id,
      :project_id,
      :workflow_id,
      :user_id,
      :meta
    ])
    |> validate_required([:title, :user_id])
    |> validate_inclusion(:session_type, @valid_session_types)
    |> validate_session_type_requirements()
    |> cast_assoc(:messages)
  end

  defp validate_session_type_requirements(changeset) do
    session_type = get_field(changeset, :session_type)

    case session_type do
      "job_code" ->
        validate_required(changeset, [:job_id])

      "workflow_template" ->
        validate_required(changeset, [:project_id])

      invalid_type when invalid_type not in @valid_session_types ->
        add_error(
          changeset,
          :session_type,
          "must be either 'job_code' or 'workflow_template'"
        )
    end
  end
end
