defmodule LightningWeb.Live.AiAssistant.Modes.JobCode do
  @moduledoc """
  AI mode for job-specific code assistance and debugging.

  Provides contextual help for job development using expression code,
  adaptor information, and run logs.
  """

  use LightningWeb.Live.AiAssistant.ModeBehavior

  alias Lightning.Accounts.User
  alias Lightning.AiAssistant
  alias Lightning.Invocation
  alias Lightning.Workflows.Job
  alias Lightning.AiAssistant.ChatMessage
  alias Lightning.AiAssistant.ChatSession
  alias LightningWeb.Live.AiAssistant.ErrorHandler

  defmodule Form do
    @moduledoc false

    use Ecto.Schema
    import Ecto.Changeset

    @primary_key false
    embedded_schema do
      field :content, :string

      embeds_one :options, Options, on_replace: :update do
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
      cast(schema, params, [:code, :input, :output, :logs])
    end

    def get_options(changeset) do
      data = apply_changes(changeset)

      if data.options do
        data.options
        |> Map.from_struct()
        |> Map.to_list()
      else
        []
      end
    end
  end

  @type job :: Job.t()
  @type user :: User.t()
  @type session :: AiAssistant.ChatSession.t()

  @doc """
  Creates job-scoped session with expression and adaptor context.
  """
  @impl true
  def create_session(
        %{selected_job: job, current_user: user},
        content,
        opts \\ []
      ) do
    AiAssistant.create_session(job, user, content, opts)
  end

  @doc """
  Enriches session with job expression, adaptor, and optional run logs.
  """
  @impl true
  def get_session!(%{chat_session_id: session_id, selected_job: job} = assigns) do
    AiAssistant.get_session!(session_id)
    |> AiAssistant.put_expression_and_adaptor(job.body, job.adaptor)
    |> maybe_add_run_logs(job, assigns[:follow_run])
  end

  @doc """
  Lists all sessions for the selected job.
  """
  @impl true
  def list_sessions(%{selected_job: job}, sort_direction, opts \\ []) do
    AiAssistant.list_sessions(job, sort_direction, opts)
  end

  @doc """
  Checks for more job-specific sessions.
  """
  @impl true
  def more_sessions?(%{selected_job: job}, current_count) do
    AiAssistant.has_more_sessions?(job, current_count)
  end

  @doc """
  Saves message with user attribution.
  """
  @impl true
  def save_message(%{session: session, current_user: user}, content) do
    AiAssistant.save_message(session, %{
      role: :user,
      content: content,
      user: user
    })
  end

  @doc """
  Queries standard AI endpoint with job context.
  """
  @impl true
  def query(session, content, opts) do
    AiAssistant.query(session, content, opts)
  end

  @doc """
  Extracts attachment options from form changeset.
  """
  @impl true
  def query_options(%{changeset: changeset}) do
    Form.get_options(changeset)
  end

  @doc """
  Validates form with attachment options.
  """
  @impl true
  def validate_form_changeset(params) do
    Form.changeset(params)
  end

  @impl true
  def enable_attachment_options_component?, do: true

  @doc """
  Disabled when: no permission, limit reached, endpoint down, loading, or job unsaved.
  """
  @impl true
  def chat_input_disabled?(%{
        selected_job: job,
        can_edit_workflow: can_edit,
        ai_limit_result: limit_result,
        endpoint_available?: available?,
        pending_message: pending
      }) do
    !can_edit or
      limit_result != :ok or
      !available? or
      !is_nil(pending.loading) or
      job_is_unsaved?(job)
  end

  @doc """
  Prompts for job code questions.
  """
  @impl true
  def input_placeholder do
    "Ask about your job code, debugging, or OpenFn adaptors..."
  end

  @doc """
  Uses job name in title when available.
  """
  @impl true
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

  @impl true
  def supports_template_generation?, do: false

  @doc """
  Job assistance metadata.
  """
  @impl true
  def metadata do
    %{
      name: "Job Code Assistant",
      description: "Get help with job code, debugging, and OpenFn adaptors",
      icon: "hero-code-bracket"
    }
  end

  @doc """
  Returns tooltip explaining why input is disabled.
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

  defp maybe_add_run_logs(session, _job, nil), do: session

  defp maybe_add_run_logs(session, job, run) do
    logs = Invocation.assemble_logs_for_job_and_run(job.id, run.id)
    %{session | logs: logs}
  end

  defp job_is_unsaved?(%{__meta__: %{state: :built}}), do: true
  defp job_is_unsaved?(_job), do: false

  defp extract_job_code(%ChatSession{messages: messages}) do
    messages
    |> Enum.reverse()
    |> Enum.find_value(fn message ->
      if has_job_code?(message.job_code), do: message.job_code
    end)
  end

  defp extract_job_code(%ChatMessage{job_code: code}) do
    if has_job_code?(code), do: code
  end

  defp has_job_code?(code) when is_binary(code), do: code != ""
  defp has_job_code?(_), do: false

  def apply_changes(socket, session_or_message) do
    case extract_job_code(session_or_message) do
      nil ->
        socket

      code ->
        send(
          socket.assigns.parent_id,
          {:code_assistant, code, socket.assigns.selected_job}
        )

        socket
    end
  end
end
