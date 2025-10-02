defmodule Lightning.Collaboration.Session do
  @moduledoc """
  Manages individual user sessions for collaborative workflow editing.

  A Session acts as a bridge between a parent process (typically a Phoenix
  channel) and a SharedDoc process that manages the Y.js CRDT document. Each
  user editing a workflow has their own Session process that handles:

  * User presence tracking via `Lightning.Workflows.Presence`
  * Bi-directional Y.js message routing between parent and SharedDoc
  * Connection management to existing SharedDoc processes via Registry lookup
  * Workflow document initialization with database data when needed
  * Cleanup when the parent process disconnects

  Sessions are temporary processes that monitor their parent and terminate
  when the parent disconnects, ensuring proper cleanup of presence tracking
  and SharedDoc observers.
  """
  use GenServer, restart: :temporary

  alias Lightning.Accounts.User
  alias Lightning.Collaboration.Registry
  alias Lightning.Collaboration.WorkflowSerializer
  alias Lightning.Workflows.Presence
  alias Yex.Sync.SharedDoc

  require Logger

  defstruct [:parent_pid, :parent_ref, :shared_doc_pid, :user, :workflow_id]

  @pg_scope :workflow_collaboration

  @type start_opts :: [
          workflow_id: String.t(),
          user: User.t(),
          parent_pid: pid()
        ]

  @doc """
  Start a new session for a workflow.

  The session will be started as a child of the `Collaboration.Supervisor`.

  ## Options

  - `workflow_id` - The id of the workflow to start the session for.
  - `user` - The user to start the session for.
  - `parent_pid` - The pid of the parent process.
     Defaults to the current process.
  """

  # @spec start(opts :: start_opts()) :: {:ok, pid()} | {:error, any()}
  # def start(opts) do
  #   opts = Keyword.put_new_lazy(opts, :parent_pid, fn -> self() end)

  #   Collaboration.Supervisor.start_child(child_spec(opts))
  # end

  def stop(session_pid) do
    GenServer.stop(session_pid)
  end

  # ----------------------------------------------------------------------------

  def child_spec(opts) do
    {opts, args} =
      Keyword.put_new_lazy(opts, :session_id, fn -> Ecto.UUID.generate() end)
      |> Keyword.split_with(fn {k, _v} -> k in [:session_id, :name] end)

    {session_id, opts} = Keyword.pop!(opts, :session_id)

    %{
      id: {:session, session_id},
      start: {__MODULE__, :start_link, [args, opts]},
      restart: :temporary
    }
  end

  def start_link(args, opt \\ []) do
    GenServer.start_link(__MODULE__, args, opt)
  end

  @impl true
  def init(opts) do
    opts = Keyword.put_new_lazy(opts, :parent_pid, fn -> self() end)
    workflow_id = Keyword.fetch!(opts, :workflow_id)
    user = Keyword.fetch!(opts, :user)
    parent_pid = Keyword.fetch!(opts, :parent_pid)

    Logger.info("Starting session for workflow #{workflow_id}")

    parent_ref = Process.monitor(parent_pid)

    # Just initialize the state, defer SharedDoc creation
    state = %__MODULE__{
      parent_pid: parent_pid,
      parent_ref: parent_ref,
      shared_doc_pid: nil,
      user: user,
      workflow_id: workflow_id
    }

    Registry.whereis({:shared_doc, "workflow:#{workflow_id}"})
    |> case do
      nil ->
        {:stop, {:error, :shared_doc_not_found}}

      shared_doc_pid ->
        SharedDoc.observe(shared_doc_pid)
        Logger.info("Joined SharedDoc for workflow #{workflow_id}")

        # We track the user presence here so the the original WorkflowLive.Edit
        # can be stopped from editing the workflow when someone else is editing it.
        Presence.track_user_presence(
          user,
          workflow_id,
          self()
        )

        {:ok, %{state | shared_doc_pid: shared_doc_pid}}
    end
  end

  @impl true
  def terminate(_reason, %{shared_doc_pid: shared_doc_pid} = state) do
    if state.parent_ref do
      Process.demonitor(state.parent_ref)
    end

    if shared_doc_pid && Process.alive?(shared_doc_pid) do
      SharedDoc.unobserve(shared_doc_pid)
    end

    Presence.untrack_user_presence(
      state.user,
      state.workflow_id,
      self()
    )

    :ok
  end

  # ----------------------------------------------------------------------------

  def lookup_shared_doc(workflow_id) do
    case :pg.get_members(@pg_scope, workflow_id) do
      [] -> nil
      [shared_doc_pid | _] -> shared_doc_pid
    end
  end

  # ----------------------------------------------------------------------------

  @doc """
  Get the current document.
  """
  def get_doc(session_pid) do
    GenServer.call(session_pid, :get_doc)
  end

  def stop_shared_doc(session_pid) do
    GenServer.call(session_pid, :stop_shared_doc)
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
  def handle_call(:get_doc, _from, %{shared_doc_pid: shared_doc_pid} = state) do
    {:reply, SharedDoc.get_doc(shared_doc_pid), state}
  end

  @impl true
  def handle_call(
        :stop_shared_doc,
        _from,
        %{shared_doc_pid: shared_doc_pid} = state
      ) do
    send(shared_doc_pid, {:DOWN, nil, :process, self(), nil})
    {:reply, :ok, %{state | shared_doc_pid: nil}}
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

  # Comes from the parent process, we forward it on to the SharedDoc.
  # The SharedDoc will send a message back via the :yjs message.
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

  # Comes from the SharedDoc, for changes coming from the SharedDoc
  # and we forward it on to the parent process.
  @impl true
  def handle_info({:yjs, reply, shared_doc_pid}, state) do
    Logger.debug(
      {:yjs, reply, shared_doc_pid}
      |> inspect(
        label: "Session :yjs",
        pretty: true,
        syntax_colors: IO.ANSI.syntax_colors()
      )
    )

    Map.get(state, :parent_pid) |> send({:yjs, reply})
    {:noreply, state}
  end

  # TODO: we need to have a strategy for handling the shared doc process crashing.
  # What should we do? We can't have all the sessions try and create a new one all at once.
  # and we want the front end to be able to still work, but show there is a problem?
  @impl true
  def handle_info(
        {:DOWN, ref, :process, _pid, _reason},
        %{parent_ref: parent_ref, shared_doc_pid: shared_doc_pid} = state
      ) do
    if ref == parent_ref do
      Process.demonitor(parent_ref)

      if shared_doc_pid && Process.alive?(shared_doc_pid) do
        SharedDoc.unobserve(shared_doc_pid)
      end

      {:stop, :normal, %{state | parent_ref: nil, shared_doc_pid: nil}}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_info(any, state) do
    Logger.debug("Session received unknown message: #{inspect(any)}")
    {:noreply, state}
  end

  # ----------------------------------------------------------------------------

  def initialize_workflow_document(doc, workflow_id) do
    Logger.debug("Initializing SharedDoc with workflow data for #{workflow_id}")

    # Fetch workflow from database
    case Lightning.Workflows.get_workflow(workflow_id,
           include: [:jobs, :edges, :triggers]
         ) do
      nil ->
        # TODO: this should be an error, but we need to handle it gracefully
        # in the frontend.
        Logger.warning(
          "Workflow #{workflow_id} not found, initializing empty document"
        )

        doc

      workflow ->
        initialize_workflow_data(doc, workflow)
    end
  end

  @doc false
  defp initialize_workflow_data(doc, workflow) do
    WorkflowSerializer.serialize_to_ydoc(doc, workflow)
  end
end
