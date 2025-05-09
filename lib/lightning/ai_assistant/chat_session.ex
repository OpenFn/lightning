defmodule Lightning.AiAssistant.ChatSession do
  @moduledoc """
  Represents a chat session for AI assistance, including job code and workflow templates.
  This module defines the schema and changeset for chat sessions, including
  relationships to users, jobs, projects, and workflows.
  It also includes custom validation logic to ensure that the correct fields
  """
  use Lightning.Schema
  import Ecto.Changeset

  alias Lightning.Accounts.User
  alias Lightning.AiAssistant.ChatMessage
  alias Lightning.Workflows.Job
  # Add Project import
  alias Lightning.Projects.Project
  # Add Workflow import
  alias Lightning.Workflows.Workflow

  @type t() :: %__MODULE__{
          id: Ecto.UUID.t(),
          # Make nullable
          job_id: Ecto.UUID.t() | nil,
          # Add project_id
          project_id: Ecto.UUID.t() | nil,
          # Add workflow_id
          workflow_id: Ecto.UUID.t() | nil,
          user_id: Ecto.UUID.t(),
          title: String.t(),
          # Add session_type
          session_type: String.t(),
          expression: String.t() | nil,
          adaptor: String.t() | nil,
          is_public: boolean(),
          is_deleted: boolean(),
          meta: map() | nil,
          messages: [ChatMessage.t(), ...] | []
        }

  schema "ai_chat_sessions" do
    field :expression, :string, virtual: true
    field :adaptor, :string, virtual: true
    field :title, :string
    # Add session_type field
    field :session_type, :string, default: "job_code"
    field :meta, :map
    field :is_public, :boolean, default: false
    field :is_deleted, :boolean, default: false
    # Now nullable
    belongs_to :job, Job
    # Add project relationship
    belongs_to :project, Project
    # Add workflow relationship
    belongs_to :workflow, Workflow
    belongs_to :user, User

    has_many :messages, ChatMessage, preload_order: [asc: :inserted_at]

    timestamps()
  end

  def changeset(chat_session, attrs) do
    chat_session
    |> cast(attrs, [
      :title,
      :is_public,
      :is_deleted,
      :job_id,
      # Add project_id
      :project_id,
      # Add workflow_id
      :workflow_id,
      # Add session_type
      :session_type,
      :user_id,
      :meta
    ])
    |> validate_required([:title, :user_id])
    # Add custom validation
    |> validate_session_type_requirements()
    |> cast_assoc(:messages)
  end

  # Add custom validation function to ensure proper fields based on session_type
  defp validate_session_type_requirements(changeset) do
    session_type = get_field(changeset, :session_type)

    case session_type do
      "job_code" ->
        # For job_code sessions, job_id is required
        validate_required(changeset, [:job_id])

      "workflow_template" ->
        # For workflow_template sessions, project_id is required
        validate_required(changeset, [:project_id])

      _ ->
        # Default case, add an error for invalid session_type
        changeset
        |> add_error(
          :session_type,
          "must be either 'job_code' or 'workflow_template'"
        )
    end
  end
end
