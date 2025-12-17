defmodule LightningWeb.Live.AiAssistant.Modes.JobCode do
  @moduledoc """
  AI mode for job-specific code assistance and debugging.

  Provides context-aware help for job code, including adaptor usage,
  debugging support, and optional log attachment.
  """
  use LightningWeb.Live.AiAssistant.ModeBehavior

  import Phoenix.Component
  import LightningWeb.Components.Icons
  import LightningWeb.Components.NewInputs

  alias Lightning.Accounts.User
  alias Lightning.AiAssistant
  alias Lightning.AiAssistant.ChatSession
  alias Lightning.Invocation
  alias Lightning.Workflows.Job
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

    @spec changeset(map()) :: Ecto.Changeset.t()
    def changeset(params) do
      %__MODULE__{}
      |> cast(params, [:content])
      |> validate_required([:content],
        message: "Please enter a message before sending"
      )
      |> validate_length(:content,
        min: 1,
        message: "Please enter a message before sending"
      )
      |> cast_embed(:options, with: &options_changeset/2)
    end

    @spec options_changeset(Ecto.Schema.t(), map()) :: Ecto.Changeset.t()
    defp options_changeset(schema, params) do
      cast(schema, params, [:code, :input, :output, :logs])
    end

    @spec extract_options(Ecto.Changeset.t()) :: Keyword.t()
    def extract_options(changeset) do
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
  @type session :: ChatSession.t()
  @type assigns :: %{atom() => any()}

  @impl true
  @spec create_session(assigns(), String.t(), Keyword.t()) ::
          {:ok, session()} | {:error, term()}
  def create_session(
        %{selected_job: job, user: user, changeset: changeset} = assigns,
        content,
        opts \\ []
      ) do
    form_options = extract_form_options(changeset)

    meta = %{"message_options" => Enum.into(form_options, %{})}

    meta =
      case assigns do
        %{follow_run: %{id: run_id}} -> Map.put(meta, "follow_run_id", run_id)
        _ -> meta
      end

    final_opts = Keyword.put(opts, :meta, meta)

    AiAssistant.create_session(job, user, content, final_opts)
  end

  @impl true
  @spec get_session!(assigns()) :: session()
  def get_session!(%{chat_session_id: session_id, selected_job: job} = assigns) do
    AiAssistant.get_session!(session_id)
    |> AiAssistant.put_expression_and_adaptor(job.body, job.adaptor)
    |> maybe_add_run_logs(job, assigns[:follow_run])
  end

  @impl true
  @spec list_sessions(assigns(), :asc | :desc, Keyword.t()) :: %{
          sessions: [session()],
          pagination: map()
        }
  def list_sessions(%{selected_job: job, user: user}, sort_direction, opts \\ []) do
    AiAssistant.list_sessions(job, user, sort_direction, opts)
  end

  @impl true
  @spec more_sessions?(assigns(), integer()) :: boolean()
  def more_sessions?(%{selected_job: job, user: user}, current_count) do
    AiAssistant.has_more_sessions?(job, user, current_count)
  end

  @impl true
  @spec save_message(assigns(), String.t()) ::
          {:ok, session()} | {:error, term()}
  def save_message(
        %{session: session, user: user, changeset: changeset} = assigns,
        content
      ) do
    options = extract_form_options(changeset)

    updated_meta =
      session.meta
      |> Kernel.||(%{})
      |> Map.put("message_options", Enum.into(options, %{}))

    updated_meta =
      case assigns do
        %{follow_run: %{id: run_id}} ->
          Map.put(updated_meta, "follow_run_id", run_id)

        _ ->
          updated_meta
      end

    AiAssistant.save_message(
      session,
      %{
        role: :user,
        content: content,
        user: user
      },
      meta: updated_meta
    )
  end

  @impl true
  @spec query(session(), String.t(), Keyword.t()) ::
          {:ok, session()} | {:error, term()}
  def query(session, content, opts) do
    AiAssistant.query(session, content, opts)
  end

  @impl true
  @spec chat_input_disabled?(assigns()) :: boolean()
  def chat_input_disabled?(%{
        selected_job: job,
        can_edit: can_edit,
        ai_limit_result: limit_result,
        endpoint_available: available?,
        pending_message: pending
      }) do
    !can_edit or
      limit_result != :ok or
      !available? or
      !is_nil(pending.loading) or
      job_is_unsaved?(job)
  end

  @impl true
  @spec input_placeholder() :: String.t()
  def input_placeholder do
    "Ask about your job code, debugging, or OpenFn adaptors..."
  end

  @impl true
  @spec chat_title(session()) :: String.t()
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
  @spec metadata() :: map()
  def metadata do
    %{
      name: "Job Code Assistant",
      description: "Get help with job code, debugging, and OpenFn adaptors",
      icon: "hero-cpu-chip",
      chat_param: "j-chat"
    }
  end

  @impl true
  @spec disabled_tooltip_message(assigns()) :: String.t() | nil
  def disabled_tooltip_message(assigns) do
    case {assigns.can_edit, assigns.ai_limit_result, assigns.selected_job} do
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

  @impl true
  @spec form_module() :: module()
  def form_module, do: Form

  @impl true
  @spec validate_form(map()) :: Ecto.Changeset.t()
  def validate_form(params) do
    Form.changeset(params)
  end

  @impl true
  @spec extract_form_options(Ecto.Changeset.t()) :: Keyword.t()
  def extract_form_options(changeset) do
    Form.extract_options(changeset)
  end

  @impl true
  @spec render_config_form(assigns()) :: Phoenix.LiveView.Rendered.t() | nil
  def render_config_form(assigns) do
    if assigns[:handler] && assigns.handler.form_module() == Form do
      ~H"""
      <div class="mt-2 flex gap-2 content-center">
        <span class="place-content-center">
          <.icon name="hero-paper-clip" class="size-4" /> Attach:
        </span>
        <.inputs_for :let={options} field={@form[:options]}>
          <.input type="checkbox" label="Code" field={options[:code]} />
          <.input type="checkbox" label="Logs" field={options[:logs]} />
        </.inputs_for>
      </div>
      """
    else
      nil
    end
  end

  @doc false
  @spec maybe_add_run_logs(session(), job(), map() | nil) :: session()
  defp maybe_add_run_logs(session, _job, nil), do: session

  defp maybe_add_run_logs(session, job, run) do
    logs = Invocation.assemble_logs_for_job_and_run(job.id, run.id)
    %{session | logs: logs}
  end

  @doc false
  @spec job_is_unsaved?(job()) :: boolean()
  defp job_is_unsaved?(%{__meta__: %{state: :built}}), do: true
  defp job_is_unsaved?(_job), do: false
end
