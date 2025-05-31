defmodule Lightning.AiAssistant.ChatSession do
  @moduledoc """
  Represents a chat session for AI assistance, including job code and workflow templates.

  This module defines the schema and changeset for chat sessions, including
  relationships to users, jobs, projects, and workflows. It also includes custom
  validation logic to ensure that the correct fields are populated based on the session type.

  ## Session Types

  * `"job_code"` - Sessions focused on generating or modifying code for specific jobs
  * `"workflow_template"` - Sessions for creating workflow templates within a project

  ## Schema Fields

  ### Core Fields
  * `title` - Human-readable title for the session (required)
  * `session_type` - Type of session, defaults to "job_code"
  * `meta` - Additional metadata stored as a map
  * `is_public` - Whether the session is publicly visible (defaults to false)
  * `is_deleted` - Soft deletion flag (defaults to false)

  ### Associations
  * `user_id` - The user who owns this session (required)
  * `job_id` - Associated job (required for "job_code" sessions)
  * `project_id` - Associated project (required for "workflow_template" sessions)
  * `workflow_id` - Associated workflow (optional)

  ### Virtual Fields (Runtime Only)
  * `expression` - Current job expression for context
  * `adaptor` - Current job adaptor for context
  * `message_count` - Number of messages in the session

  ## Validation Rules

  ### Session Type Requirements
  * **job_code sessions**: Must have a `job_id`
  * **workflow_template sessions**: Must have a `project_id`

  ## Examples

      # Create a job code session
      %ChatSession{}
      |> ChatSession.changeset(%{
        title: "Debug payment processing job",
        session_type: "job_code",
        user_id: user.id,
        job_id: job.id
      })

      # Create a workflow template session
      %ChatSession{}
      |> ChatSession.changeset(%{
        title: "New data pipeline workflow",
        session_type: "workflow_template",
        user_id: user.id,
        project_id: project.id,
        is_public: true
      })

      # Session with metadata
      %ChatSession{}
      |> ChatSession.changeset(%{
        title: "API integration helper",
        session_type: "job_code",
        user_id: user.id,
        job_id: job.id,
        meta: %{
          "api_version" => "v2",
          "last_error" => "timeout"
        }
      })
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

    # Virtual fields for runtime data
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

  @doc """
  Creates a changeset for a chat session.

  ## Parameters

  * `chat_session` - The ChatSession struct to update (typically `%ChatSession{}`)
  * `attrs` - Map of attributes to set/update

  ## Validation Rules

  * `title` and `user_id` are required
  * `session_type` must be one of: #{inspect(@valid_session_types)}
  * **job_code sessions** require `job_id`
  * **workflow_template sessions** require `project_id`
  * Associated messages are cast and validated

  ## Examples

      # Valid job code session
      ChatSession.changeset(%ChatSession{}, %{
        title: "Fix data transformation",
        session_type: "job_code",
        user_id: user.id,
        job_id: job.id
      })

      # Valid workflow template session
      ChatSession.changeset(%ChatSession{}, %{
        title: "Customer onboarding flow",
        session_type: "workflow_template",
        user_id: user.id,
        project_id: project.id,
        is_public: true
      })

      # With nested messages
      ChatSession.changeset(%ChatSession{}, %{
        title: "Debug session",
        user_id: user.id,
        job_id: job.id,
        messages: [
          %{content: "Help me fix this error", role: :user}
        ]
      })

  ## Errors

  Returns a changeset with errors if:
  * Required fields are missing
  * Invalid session_type is provided
  * Session type requirements aren't met (e.g., job_code without job_id)
  """
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
