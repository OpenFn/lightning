defmodule LightningWeb.Live.AiAssistant.Modes.JobCode do
  @moduledoc """
  AI Assistant mode for job-specific code assistance and debugging.

  This mode provides intelligent assistance for developing, debugging, and optimizing
  job code within Lightning workflows. It leverages job-specific context including
  the expression code and adaptor information to provide targeted AI assistance.
  """

  use LightningWeb.Live.AiAssistant.ModeBehavior

  alias Lightning.AiAssistant
  alias Lightning.Invocation
  alias LightningWeb.Live.AiAssistant.ErrorHandler

  defmodule Form do
    @moduledoc false

    use Ecto.Schema
    import Ecto.Changeset

    @primary_key false
    embedded_schema do
      field :content, :string

      embeds_one :options, Options, defaults_to_struct: true do
        field :code, :boolean, default: true
        field :input, :boolean, default: false
        field :output, :boolean, default: false
        field :logs, :boolean, default: false
      end
    end

    def changeset(params) do
      %__MODULE__{}
      |> cast(params, [:content])
      |> cast_embed(:options, with: &options_changeset/2)
    end

    defp options_changeset(schema, params) do
      schema
      |> cast(params, [:code, :logs])
    end

    def get_options(changeset) do
      data = apply_changes(changeset)

      if data.options do
        Map.from_struct(data.options)
      else
        %{}
      end
    end
  end

  @doc """
  Creates a new job-specific AI assistance session.

  Initializes a session with job context, including the job's expression code
  and adaptor information for targeted AI assistance.

  ## Required Assigns

  - `:selected_job` - The job struct to provide assistance for
  - `:current_user` - The user creating the session

  ## Examples

      # Create session for debugging help
      {:ok, session} = JobCode.create_session(
        %{selected_job: job, current_user: user},
        "Help me debug this HTTP request error"
      )
  """
  @impl true
  @spec create_session(map(), String.t()) :: {:ok, map()} | {:error, any()}
  def create_session(%{selected_job: job, current_user: user}, content) do
    AiAssistant.create_session(job, user, content)
  end

  @doc """
  Retrieves and enriches a session with job-specific context.

  Loads the session and adds the current job's expression and adaptor
  information, enabling the AI to provide contextual assistance.

  ## Required Assigns

  - `:selected_job` - The job struct to provide context from

  ## Examples

      session = JobCode.get_session!(session_id, %{selected_job: current_job})
      # session now includes job.body as expression and job.adaptor
  """
  @impl true
  @spec get_session!(map()) :: map()
  def get_session!(%{chat_session_id: session_id, selected_job: job} = assigns) do
    AiAssistant.get_session!(session_id)
    |> AiAssistant.put_expression_and_adaptor(job.body, job.adaptor)
    |> then(fn session ->
      follow_run = assigns[:follow_run]

      if follow_run do
        logs =
          Invocation.assemble_logs_for_job_and_run(job.id, follow_run.id)

        %{session | logs: logs}
      else
        session
      end
    end)
  end

  @doc """
  Lists job-specific AI assistance sessions with pagination.

  Retrieves sessions associated with the currently selected job,
  ordered by recency for easy access to recent conversations.

  ## Required Assigns

  - `:selected_job` - The job to filter sessions by

  ## Examples

      # Load recent sessions for current job
      %{sessions: sessions, pagination: meta} = JobCode.list_sessions(
        %{selected_job: job},
        :desc,
        limit: 10
      )
  """
  @impl true
  @spec list_sessions(map(), atom(), keyword()) :: %{
          sessions: [map()],
          pagination: map()
        }
  def list_sessions(%{selected_job: job}, sort_direction, opts \\ []) do
    AiAssistant.list_sessions(job, sort_direction, opts)
  end

  @doc """
  Checks if more sessions exist for the current job.

  Determines if additional sessions are available beyond the current count
  for implementing "Load More" functionality.

  ## Required Assigns

  - `:selected_job` - The job to check session count for

  ## Examples

      if JobCode.more_sessions?(%{selected_job: job}, 20) do
        # Show "Load More" button
      end
  """
  @impl true
  @spec more_sessions?(map(), integer()) :: boolean()
  def more_sessions?(%{selected_job: job}, current_count) do
    AiAssistant.has_more_sessions?(job, current_count)
  end

  @doc """
  Saves a user message to the job assistance session.

  Adds the user's message to the conversation history with proper
  role and user attribution for AI processing.

  ## Required Assigns

  - `:session` - The target session
  - `:current_user` - The user sending the message

  ## Examples

      {:ok, updated_session} = JobCode.save_message(
        %{session: session, current_user: user},
        "How do I handle this API error?"
      )
  """
  @impl true
  @spec save_message(map(), String.t()) :: {:ok, map()} | {:error, any()}
  def save_message(%{session: session, current_user: user}, content) do
    AiAssistant.save_message(session, %{
      role: :user,
      content: content,
      user: user
    })
  end

  @doc """
  Processes user queries through the job-specific AI assistant.

  Sends the user's question along with job context (expression and adaptor)
  to the AI service for targeted code assistance and debugging help.

  ## Parameters

  - `session` - Session with job context (expression and adaptor)
  - `content` - User's question or request for assistance

  ## Examples

      # Get help with specific code issue
      {:ok, updated_session} = JobCode.query(
        session,
        "Why is my data transformation returning undefined?"
      )

      # Request adaptor-specific guidance
      {:ok, updated_session} = JobCode.query(
        session,
        "What's the best way to handle errors in HTTP requests?"
      )
  """
  @impl true
  @spec query(map(), String.t(), map()) :: {:ok, map()} | {:error, any()}
  def query(session, content, opts) do
    AiAssistant.query(session, content, opts)
  end

  @impl true
  def query_options(changeset) do
    Form.get_options(changeset)
  end

  @doc """
  Determines if the chat input should be disabled for job assistance.

  Evaluates multiple conditions to ensure AI assistance is only available
  when appropriate permissions, limits, and job state allow it.

  ## Examples

      # Input disabled due to unsaved job
      chat_input_disabled?(%{
        selected_job: %{__meta__: %{state: :built}},
        can_edit_workflow: true,
        ai_limit_result: :ok,
        endpoint_available?: true,
        pending_message: %{loading: nil}
      })
      # => true

      # Input enabled for saved job with permissions
      chat_input_disabled?(%{
        selected_job: %{__meta__: %{state: :loaded}},
        can_edit_workflow: true,
        ai_limit_result: :ok,
        endpoint_available?: true,
        pending_message: %{loading: nil}
      })
      # => false
  """
  @impl true
  @spec chat_input_disabled?(map()) :: boolean()
  def chat_input_disabled?(%{
        selected_job: selected_job,
        can_edit_workflow: can_edit_workflow,
        ai_limit_result: ai_limit_result,
        endpoint_available?: endpoint_available?,
        pending_message: pending_message
      }) do
    !can_edit_workflow or
      has_reached_limit?(ai_limit_result) or
      !endpoint_available? or
      !is_nil(pending_message.loading) or
      job_is_unsaved?(selected_job)
  end

  @doc """
  Provides job-specific placeholder text for the chat input.

  Guides users on the types of assistance available for job development
  and debugging.
  """
  @impl true
  @spec input_placeholder() :: String.t()
  def input_placeholder do
    "Ask about your job code, debugging, or OpenFn adaptors..."
  end

  @impl true
  def validate_form_changeset(params) do
    Form.changeset(params)
  end

  @impl true
  def enable_attachment_options_component?, do: true

  @doc """
  Generates contextual titles for job assistance sessions.

  Creates descriptive titles that include job context when available,
  making it easier to identify sessions in lists.

  ## Examples

      # With custom title
      chat_title(%{title: "Debug HTTP 401 error"})
      # => "Debug HTTP 401 error"

      # With job context
      chat_title(%{job: %{name: "Fetch Salesforce Data"}})
      # => "Help with Fetch Salesforce Data"

      # Fallback
      chat_title(%{})
      # => "Job Code Help"
  """
  @impl true
  @spec chat_title(map()) :: String.t()
  def chat_title(session) do
    case session do
      %{title: title} when is_binary(title) and title != "" ->
        title

      %{job: %{name: job_name}} when is_binary(job_name) and job_name != "" ->
        "Help with #{job_name}"

      _ ->
        "Job Code Help"
    end
  end

  @doc """
  Indicates that job assistance doesn't generate templates.

  Job mode focuses on helping with existing code rather than generating
  new templates or workflows.
  """
  @impl true
  @spec supports_template_generation?() :: boolean()
  def supports_template_generation?, do: false

  @doc """
  Provides metadata for the job assistance mode.

  Returns information used by the UI to display mode selection options
  and identify the mode's capabilities.
  """
  @impl true
  @spec metadata() :: map()
  def metadata do
    %{
      name: "Job Code Assistant",
      description: "Get help with job code, debugging, and OpenFn adaptors",
      icon: "hero-cpu-chip"
    }
  end

  @doc """
  Generates appropriate tooltip messages when chat input is disabled.

  Provides specific explanations for why AI assistance is unavailable,
  helping users understand what actions they need to take.

  ## Parameters

  - `assigns` - Map containing permission and state information

  ## Returns

  String explanation or `nil` if input should be enabled.

  ## Examples

      # Permission denied
      disabled_tooltip_message(%{can_edit_workflow: false})
      # => "You are not authorized to use the AI Assistant"

      # Usage limit reached
      disabled_tooltip_message(%{ai_limit_result: {:error, :limit_exceeded}})
      # => "Monthly AI usage limit exceeded"

      # Unsaved job
      disabled_tooltip_message(%{selected_job: %{__meta__: %{state: :built}}})
      # => "Save your workflow first to use the AI Assistant"
  """
  @spec disabled_tooltip_message(map()) :: String.t() | nil
  def disabled_tooltip_message(assigns) do
    case {assigns.can_edit_workflow, assigns.ai_limit_result,
          assigns.selected_job} do
      {false, _, _} ->
        "You are not authorized to use the AI Assistant"

      {_, error, _} when error != :ok ->
        ErrorHandler.format_limit_error(error)

      {_, _, %{__meta__: %{state: :built}}} ->
        "Save your workflow first to use the AI Assistant"

      _ ->
        nil
    end
  end

  @doc """
  Formats errors consistently for job assistance mode.

  Leverages shared error handling to provide user-friendly error messages
  for various failure scenarios.

  ## Parameters

  - `error` - Error to format (changeset, atom, string, etc.)

  ## Returns

  Human-readable error message string.

  ## Examples

      error_message({:error, :timeout})
      # => "Request timed out. Please try again."

      error_message(%Ecto.Changeset{})
      # => "Validation failed: [specific field errors]"
  """
  @spec error_message(any()) :: String.t()
  def error_message(error) do
    ErrorHandler.format_error(error)
  end

  defp has_reached_limit?(ai_limit_result) do
    ai_limit_result != :ok
  end

  defp job_is_unsaved?(%{__meta__: %{state: :built}}), do: true
  defp job_is_unsaved?(_job), do: false
end
