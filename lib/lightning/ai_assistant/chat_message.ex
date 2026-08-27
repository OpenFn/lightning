defmodule Lightning.AiAssistant.ChatMessage do
  @moduledoc """
  Represents a message within an AI chat session.

  Messages can be from users (role: :user) or from the AI assistant (role: :assistant).
  User messages start with :pending status and are updated based on processing results.
  Assistant messages typically have :success status when created.

  ## Schema Fields

  * `content` - The text content of the message (required, 1-10,000 characters)
  * `code` - Optional code associated with the message (e.g., generated workflows)
  * `response_segments` - Optional display timeline of text and status segments
    for assistant messages (global chat); `[]` for flat messages (the column
    is NULL, which `embeds_many` loads as an empty list)
  * `role` - Who sent the message: `:user` or `:assistant`
  * `status` - Processing status: `:pending`, `:success`, `:error`, or `:cancelled`
  * `is_deleted` - Soft deletion flag (defaults to false)
  * `is_public` - Whether the message is publicly visible (defaults to true)
  * `meta` - Additional metadata (e.g., `"unsaved_job"` for job data not yet saved)
  * `chat_session_id` - Reference to the parent chat session
  * `user_id` - Reference to the user who sent the message (required for user messages)
  """

  use Lightning.Schema
  import Ecto.Changeset
  import Lightning.Validators, only: [validate_required_assoc: 2]

  alias Lightning.Workflows.Job

  defmodule Segment do
    @moduledoc """
    One entry in an assistant reply's display timeline: a chunk of answer
    text, or a completed-action status ("Added step send-to-gmail...") woven
    between texts in stream order. Display-only — the flat `content` field
    stays the canonical answer.
    """

    defmodule Step do
      @moduledoc """
      A workflow step a status segment acted on, recorded as data rather
      than left implicit in the status sentence.

      This is what lets the client attach per-step detail to the status
      that produced it without pattern-matching English prose. `key` is
      the workflow YAML's key for the step and is the stable identifier;
      `name` is the display name at the time the action ran, kept so a
      reloaded transcript reads the way it did live even if the step has
      since been renamed.
      """

      use Ecto.Schema
      import Ecto.Changeset

      @max_field_length 500

      @type t() :: %__MODULE__{key: String.t(), name: String.t() | nil}

      @derive {Jason.Encoder, only: [:key, :name]}
      @primary_key false
      embedded_schema do
        field :key, :string
        field :name, :string
      end

      @doc false
      def changeset(step, attrs) do
        step
        |> cast(attrs, [:key, :name])
        |> validate_required([:key])
        |> validate_length(:key, max: @max_field_length)
        |> validate_length(:name, max: @max_field_length)
      end
    end

    use Ecto.Schema
    import Ecto.Changeset

    @max_content_length 10_000
    # A single action touches a handful of steps; this only guards against a
    # malformed payload bloating the row.
    @max_steps 100

    @type t() :: %__MODULE__{
            type: :text | :status,
            content: String.t(),
            summary: String.t() | nil,
            steps: [Step.t()]
          }

    @derive {Jason.Encoder, only: [:type, :content, :summary, :steps]}
    @primary_key false
    embedded_schema do
      field :type, Ecto.Enum, values: [:text, :status]
      field :content, :string
      # Shorter line for clients that render the steps themselves, so the
      # step names are not printed once in the sentence and again on the
      # detail. Clients that render prose only keep using `content`.
      field :summary, :string
      embeds_many :steps, Step, on_replace: :delete
    end

    @doc false
    def changeset(segment, attrs) do
      segment
      |> cast(attrs, [:type, :content, :summary])
      |> cast_embed(:steps)
      |> validate_required([:type, :content])
      |> validate_length(:content, max: @max_content_length)
      |> validate_length(:summary, max: @max_content_length)
      |> validate_length(:steps, max: @max_steps)
    end

    @doc "Maximum length of a single segment's content (matches `content`'s cap)."
    def max_content_length, do: @max_content_length

    @doc "Maximum number of steps recorded against one status segment."
    def max_steps, do: @max_steps
  end

  # A reply's segment count is naturally bounded by the model's output size;
  # this cap only guards against a runaway or buggy Apollo response bloating
  # rows that get re-serialized on every channel join.
  @max_response_segments 200

  @type role() :: :user | :assistant
  @type status() :: :pending | :processing | :success | :error | :cancelled

  @type t() :: %__MODULE__{
          id: Ecto.UUID.t(),
          content: String.t() | nil,
          code: String.t() | nil,
          response_segments: [Segment.t()],
          role: role(),
          status: status(),
          job_id: Ecto.UUID.t() | nil,
          is_deleted: boolean(),
          is_public: boolean(),
          meta: map() | nil,
          processing_started_at: DateTime.t() | nil,
          processing_completed_at: DateTime.t() | nil,
          chat_session_id: Ecto.UUID.t(),
          user_id: Ecto.UUID.t() | nil,
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  schema "ai_chat_messages" do
    field :content, :string
    field :code, :string
    field :role, Ecto.Enum, values: [:user, :assistant]

    embeds_many :response_segments, Segment, on_replace: :delete

    field :status, Ecto.Enum,
      values: [:pending, :processing, :success, :error, :cancelled]

    field :is_deleted, :boolean, default: false
    field :is_public, :boolean, default: true
    field :meta, :map, default: %{}
    field :processing_started_at, :utc_datetime_usec
    field :processing_completed_at, :utc_datetime_usec

    belongs_to :chat_session, Lightning.AiAssistant.ChatSession
    belongs_to :job, Job
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
  * `response_segments`, when present, must be `#{@max_response_segments}` or
    fewer segments, each with a `type` of `text` or `status` and a `content`
    string of at most `#{Segment.max_content_length()}` characters
  * User messages (role: `:user`) require an associated user
  * Status defaults based on role: `:pending` for users, `:success` for assistant
  * If status is explicitly provided, it takes precedence over role-based defaults
  """
  def changeset(chat_message, attrs) do
    chat_message
    |> cast(attrs, [
      :content,
      :code,
      :role,
      :status,
      :is_deleted,
      :is_public,
      :meta,
      :chat_session_id,
      :processing_started_at,
      :processing_completed_at
    ])
    |> cast_embed(:response_segments)
    |> validate_length(:response_segments, max: @max_response_segments)
    |> validate_required([:content, :role])
    |> validate_length(:content, min: 1, max: 10_000)
    |> maybe_put_user_assoc(attrs[:user] || attrs["user"])
    |> maybe_put_job_assoc(attrs[:job] || attrs["job"])
    |> maybe_require_user()
    |> set_default_status_by_role()
  end

  @doc "Maximum number of segments accepted on a message."
  def max_response_segments, do: @max_response_segments

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
      when status in [:pending, :processing, :success, :error, :cancelled] do
    chat_message
    |> change(%{status: status})
  end

  defp maybe_put_user_assoc(changeset, user) when not is_nil(user) do
    put_assoc(changeset, :user, user)
  end

  defp maybe_put_user_assoc(changeset, _), do: changeset

  defp maybe_put_job_assoc(changeset, job) when not is_nil(job) do
    put_assoc(changeset, :job, job)
  end

  defp maybe_put_job_assoc(changeset, _), do: changeset

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
