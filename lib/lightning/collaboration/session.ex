defmodule Lightning.Collaboration.Session do
  use GenServer
  alias Lightning.Collaboration
  alias Yex.Sync.SharedDoc
  require Logger

  defstruct [:workflow_id, :shared_doc_pid, :cleanup_timer, :parent_pid]

  @pg_scope :workflow_collaboration

  def start(workflow_id) do
    GenServer.start_link(__MODULE__,
      workflow_id: workflow_id,
      parent_pid: self()
    )
  end

  # ---

  def init(opts) do
    workflow_id = Keyword.fetch!(opts, :workflow_id)
    parent_pid = Keyword.fetch!(opts, :parent_pid)

    Logger.info("Starting session for workflow #{workflow_id}")

    # Just initialize the state, defer SharedDoc creation
    state = %__MODULE__{
      workflow_id: workflow_id,
      shared_doc_pid: nil,
      cleanup_timer: nil,
      parent_pid: parent_pid
    }

    {:ok, state, {:continue, :start_shared_doc}}
  end

  def handle_continue(:start_shared_doc, %{workflow_id: workflow_id} = state) do
    case :pg.get_members(@pg_scope, workflow_id) do
      [] ->
        Logger.info("No existing SharedDoc found for workflow #{workflow_id}")

        child_spec =
          {SharedDoc,
           [
             doc_name: "workflow:#{workflow_id}",
             auto_exit: true
           ]}

        case Collaboration.Supervisor.start_child(child_spec) do
          {:ok, pid} ->
            :pg.join(@pg_scope, workflow_id, pid)
            # Initialize the SharedDoc with workflow data
            initialize_workflow_document(pid, workflow_id)
            # Register the SharedDoc with :pg so other sessions can find it
            SharedDoc.observe(pid)
            {:noreply, %{state | shared_doc_pid: pid}}

          {:error, {:already_started, pid}} ->
            {:noreply, %{state | shared_doc_pid: pid}}

          error ->
            Logger.error(
              "Failed to start SharedDoc for workflow #{workflow_id}: #{inspect(error)}"
            )

            {:stop, {:shutdown, :shared_doc_start_failed}, state}
        end

      [shared_doc_pid | _] ->
        Logger.info("Existing SharedDoc found for workflow #{workflow_id}")
        SharedDoc.observe(shared_doc_pid)
        {:noreply, %{state | shared_doc_pid: shared_doc_pid}}
    end
  end

  # TODO: we need to have a strategy for handling the shared doc process crashing.
  # What should we do? We can't have all the sessions try and create a new one all at once.
  # and we want the front end to be able to still work, but show there is a problem?
  # @impl true
  # def handle_info(
  #       {:DOWN, _ref, :process, _pid, _reason},
  #       socket
  #     ) do
  #   {:stop, {:error, "remote process crash"}, socket}
  # end

  def terminate(reason, _state) do
    Logger.debug("Session terminating: #{inspect({reason})}")
    :ok
  end

  def stop(session_pid) do
    GenServer.stop(session_pid)
  end

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
    GenServer.call(session_pid, {:yjs_sync, chunk})
  end

  def send_yjs_message(session_pid, chunk) do
    GenServer.call(session_pid, {:yjs, chunk})
  end

  def handle_call(:get_doc, _from, %{shared_doc_pid: shared_doc_pid} = state) do
    {:reply, SharedDoc.get_doc(shared_doc_pid), state}
  end

  def handle_call(
        {:update_doc, fun},
        _from,
        %{shared_doc_pid: shared_doc_pid} = state
      ) do
    SharedDoc.update_doc(shared_doc_pid, fun)
    {:reply, :ok, state}
  end

  def handle_call(
        {:yjs, chunk},
        _from,
        %{shared_doc_pid: shared_doc_pid} = state
      ) do
    SharedDoc.send_yjs_message(shared_doc_pid, chunk)
    {:reply, :ok, state}
  end

  def handle_call(
        {:yjs_sync, chunk},
        _from,
        %{shared_doc_pid: shared_doc_pid} = state
      ) do
    SharedDoc.start_sync(shared_doc_pid, chunk)
    {:reply, :ok, state}
  end

  def handle_info({:yjs, reply, _shared_doc_pid}, state) do
    Map.get(state, :parent_pid) |> send({:yjs, reply})
    {:noreply, state}
  end

  # Private function to initialize SharedDoc with workflow data
  defp initialize_workflow_document(shared_doc_pid, workflow_id) do
    Logger.info("Initializing SharedDoc with workflow data for #{workflow_id}")

    # Fetch workflow from database
    case Lightning.Workflows.get_workflow(workflow_id, include: [:jobs]) do
      nil ->
        Logger.warning(
          "Workflow #{workflow_id} not found, initializing empty document"
        )

        :ok

      workflow ->
        # Initialize the document with workflow data
        SharedDoc.update_doc(shared_doc_pid, fn doc ->
          # Create the root workflow map
          workflow_map = Yex.Doc.get_map(doc, "workflow")

          # Set workflow properties
          Yex.Map.set(workflow_map, "id", workflow.id)
          Yex.Map.set(workflow_map, "name", workflow.name || "")

          # Create and populate jobs array
          jobs_array = Yex.Doc.get_array(doc, "jobs")

          # Add each job to the array
          Enum.each(workflow.jobs || [], fn job ->
            job_map = %{
              "id" => job.id,
              "name" => job.name || "",
              "body" => job.body || ""
            }

            Yex.Array.push(jobs_array, job_map)
          end)

          Logger.info(
            "Initialized workflow document with #{length(workflow.jobs || [])} jobs"
          )
        end)
    end
  end
end
