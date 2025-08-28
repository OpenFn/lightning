defmodule Lightning.Collaboration.Session do
  use GenServer
  alias Lightning.Collaboration
  alias Yex.Sync.SharedDoc
  require Logger

  defstruct [:cleanup_timer, :parent_pid, :shared_doc_pid, :user, :workflow_id]

  @pg_scope :workflow_collaboration

  def start(user, workflow_id) do
    GenServer.start_link(__MODULE__,
      user: user,
      workflow_id: workflow_id,
      parent_pid: self()
    )
  end

  def stop(session_pid) do
    GenServer.stop(session_pid)
  end

  # ----------------------------------------------------------------------------

  @impl true
  def init(opts) do
    workflow_id = Keyword.fetch!(opts, :workflow_id)
    user = Keyword.fetch!(opts, :user)

    parent_pid =
      Keyword.get(opts, :parent_pid, Process.info(self(), :parent) |> elem(1))

    Logger.info("Starting session for workflow #{workflow_id}")

    # Just initialize the state, defer SharedDoc creation
    state = %__MODULE__{
      cleanup_timer: nil,
      parent_pid: parent_pid,
      shared_doc_pid: nil,
      user: user,
      workflow_id: workflow_id
    }

    case setup_shared_doc(workflow_id, user) do
      {:ok, shared_doc_pid} ->
        {:ok, %{state | shared_doc_pid: shared_doc_pid}}

      {:error, :shared_doc_start_failed} ->
        {:stop, {:error, "Failed to setup SharedDoc"}}
    end
  end

  @impl true
  def terminate(reason, _state) do
    Logger.warning("going down: #{inspect({reason})}")
    :ok
  end

  @doc """
  Check if the session is ready.

  Sessions handle the creation or joining of the SharedDoc process after startup.
  We can check if the session is ready by checking if there is a SharedDoc process
  associated with the session.

  This function will return {:ok, session_pid} if the session is ready, or
  {:error, :not_ready} if the session is not ready.

  If given a pid, it will return a boolean.

      iex> Session.ready?(session_pid)
      true

  You can also pipe from the start function:

      iex> Session.start(workflow_id) |> Session.ready?()
      {:ok, session_pid}


  This is useful during tests where other sessions are created quickly and there
  is a high chance that subsequent sessions will think there are no other
  SharedDocs available and start their own.
  """
  @spec ready?({:ok, pid()} | pid()) ::
          {:ok, pid()} | {:error, :not_ready} | boolean()
  def ready?({:ok, session_pid}) do
    if GenServer.call(session_pid, :ready?) do
      {:ok, session_pid}
    else
      {:error, :not_ready}
    end
  end

  def ready?(session_pid) do
    GenServer.call(session_pid, :ready?)
  end

  def lookup_shared_doc(workflow_id) do
    case :pg.get_members(@pg_scope, workflow_id) do
      [] -> nil
      [shared_doc_pid | _] -> shared_doc_pid
    end
  end

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker
    }
  end

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  # ----------------------------------------------------------------------------

  @doc """
  Get the current document.
  """
  def get_doc(session_pid) do
    GenServer.call(session_pid, :get_doc)
  end

  def update_doc(session_pid, fun) do
    GenServer.call(session_pid, {:update_doc, fun})
  end

  def start_sync(session_pid, chunk) do
    GenServer.call(session_pid, {:start_sync, chunk})
  end

  def send_yjs_message(session_pid, chunk) do
    GenServer.call(session_pid, {:send_yjs_message, chunk})
  end

  # ----------------------------------------------------------------------------

  @impl true
  def handle_call(:ready?, _from, %{shared_doc_pid: shared_doc_pid} = state) do
    {:reply, !is_nil(shared_doc_pid), state}
  end

  @impl true
  def handle_call(:get_doc, _from, %{shared_doc_pid: shared_doc_pid} = state) do
    {:reply, SharedDoc.get_doc(shared_doc_pid), state}
  end

  @impl true
  def handle_call(
        {:update_doc, fun},
        _from,
        %{shared_doc_pid: shared_doc_pid} = state
      ) do
    SharedDoc.update_doc(shared_doc_pid, fun)
    {:reply, :ok, state}
  end

  @impl true
  def handle_call(
        {:send_yjs_message, chunk},
        _from,
        %{shared_doc_pid: shared_doc_pid} = state
      ) do
    SharedDoc.send_yjs_message(shared_doc_pid, chunk)
    {:reply, :ok, state}
  end

  @impl true
  def handle_call(
        {:start_sync, chunk},
        from,
        %{shared_doc_pid: shared_doc_pid} = state
      ) do
    Logger.debug({:start_sync, from} |> inspect)
    SharedDoc.start_sync(shared_doc_pid, chunk)
    {:reply, :ok, state}
  end

  @impl true
  def handle_info({:yjs, reply, _shared_doc_pid}, state) do
    Map.get(state, :parent_pid) |> send({:yjs, reply})
    {:noreply, state}
  end

  # TODO: we need to have a strategy for handling the shared doc process crashing.
  # What should we do? We can't have all the sessions try and create a new one all at once.
  # and we want the front end to be able to still work, but show there is a problem?
  # @impl true
  # def handle_info(
  #       {:DOWN, _ref, :process, _pid, _reason},
  #       state
  #     ) do
  #   {:stop, {:error, "remote process crash"}, state}
  # end

  @impl true
  def handle_info(any, state) do
    Logger.debug("Session received unknown message: #{inspect(any)}")
    {:noreply, state}
  end

  # ----------------------------------------------------------------------------

  @doc false
  defp setup_shared_doc(workflow_id, user) do
    case lookup_shared_doc(workflow_id) do
      nil ->
        Logger.info("No existing SharedDoc found for workflow #{workflow_id}")

        case Collaboration.Supervisor.start_shared_doc("workflow:#{workflow_id}") do
          {:ok, pid} ->
            :pg.join(@pg_scope, workflow_id, pid)
            initialize_workflow_document(pid, workflow_id)
            join_shared_doc(pid, user, workflow_id)
            {:ok, pid}

          {:error, {:already_started, pid}} ->
            {:ok, pid}

          error ->
            Logger.error(
              "Failed to start SharedDoc for workflow #{workflow_id}: #{inspect(error)}"
            )

            {:error, :shared_doc_start_failed}
        end

      shared_doc_pid ->
        Logger.info("Existing SharedDoc found for workflow #{workflow_id}")
        join_shared_doc(shared_doc_pid, user, workflow_id)
        {:ok, shared_doc_pid}
    end
  end

  defp join_shared_doc(shared_doc_pid, user, workflow_id) do
    SharedDoc.observe(shared_doc_pid)

    # We track the user presence here so the the original WorkflowLive.Edit
    # can be stopped from editing the workflow when someone else is editing it.
    Lightning.Workflows.Presence.track_user_presence(
      user,
      workflow_id,
      self()
    )
  end

  # Private function to initialize SharedDoc with workflow data
  defp initialize_workflow_document(shared_doc_pid, workflow_id) do
    Logger.info("Initializing SharedDoc with workflow data for #{workflow_id}")

    # Fetch workflow from database
    case Lightning.Workflows.get_workflow(workflow_id,
           include: [:jobs, :edges, :triggers]
         ) do
      nil ->
        Logger.warning(
          "Workflow #{workflow_id} not found, initializing empty document"
        )

        :ok

      workflow ->
        # Initialize the document with workflow data
        SharedDoc.update_doc(shared_doc_pid, fn doc ->
          workflow_map = Yex.Doc.get_map(doc, "workflow")
          jobs_array = Yex.Doc.get_array(doc, "jobs")
          edges_array = Yex.Doc.get_array(doc, "edges")
          triggers_array = Yex.Doc.get_array(doc, "triggers")
          positions = Yex.Doc.get_map(doc, "positions")

          IO.inspect(length(workflow.jobs || []), label: "jobs")

          Yex.Doc.transaction(doc, "initialize_workflow_document", fn ->
            # Set workflow properties
            Yex.Map.set(workflow_map, "id", workflow.id)
            Yex.Map.set(workflow_map, "name", workflow.name || "")

            Enum.each(workflow.jobs || [], fn job ->
              job_map =
                Yex.MapPrelim.from(%{
                  "id" => job.id,
                  "name" => job.name || "",
                  "body" => Yex.TextPrelim.from(job.body || ""),
                  "adaptor" => job.adaptor,
                  "project_credential_id" => job.project_credential_id,
                  "keychain_credential_id" => job.keychain_credential_id
                })

              Yex.Array.push(jobs_array, job_map)
            end)

            Enum.each(workflow.edges || [], fn edge ->
              edge_map =
                Yex.MapPrelim.from(%{
                  "condition_expression" => edge.condition_expression,
                  "condition_label" => edge.condition_label,
                  "condition_type" => edge.condition_type |> to_string(),
                  "enabled" => edge.enabled,
                  # "errors" => edge.errors,
                  "id" => edge.id,
                  "source_job_id" => edge.source_job_id,
                  "source_trigger_id" => edge.source_trigger_id,
                  "target_job_id" => edge.target_job_id
                })

              Yex.Array.push(edges_array, edge_map)
            end)

            Enum.each(workflow.triggers || [], fn trigger ->
              trigger_map =
                Yex.MapPrelim.from(%{
                  "cron_expression" => trigger.cron_expression,
                  "enabled" => trigger.enabled,
                  "has_auth_method" => trigger.has_auth_method,
                  "id" => trigger.id,
                  "type" => trigger.type |> to_string()
                })

              Yex.Array.push(triggers_array, trigger_map)
            end)

            Enum.each(workflow.positions || [], fn {id, position} ->
              Yex.Map.set(positions, id, position)
            end)

            Logger.debug(
              "Initialized workflow document with #{length(workflow.jobs || [])} jobs and their Y.Text bodies"
            )
          end)
        end)
    end
  end
end
