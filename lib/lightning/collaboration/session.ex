defmodule Lightning.Collaboration.Session do
  use GenServer, restart: :temporary
  use Lightning.Utils.Logger, color: [:cyan_background]

  alias Lightning.Accounts.User
  alias Lightning.Collaboration.Registry
  alias Yex.Sync.SharedDoc

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

    info("Starting session for workflow #{workflow_id}")

    parent_ref = Process.monitor(parent_pid)

    info("Parent pid: #{inspect(parent_pid)}")

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
        info("Joined SharedDoc for workflow #{workflow_id}")

        # We track the user presence here so the the original WorkflowLive.Edit
        # can be stopped from editing the workflow when someone else is editing it.
        Lightning.Workflows.Presence.track_user_presence(
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

    Lightning.Workflows.Presence.untrack_user_presence(
      state.user,
      state.workflow_id,
      self()
    )

    :ok
  end

  # ----------------------------------------------------------------------------

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
  @deprecated "Not required anymore, the process can be assumed to be ready"
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
  def handle_call(:ready?, _from, %{shared_doc_pid: shared_doc_pid} = state) do
    {:reply, !is_nil(shared_doc_pid), state}
  end

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
    debug({:start_sync, from} |> inspect)
    SharedDoc.start_sync(shared_doc_pid, chunk)
    {:reply, :ok, state}
  end

  # Comes from the SharedDoc, for changes coming from the SharedDoc
  # and we forward it on to the parent process.
  @impl true
  def handle_info({:yjs, reply, shared_doc_pid}, state) do
    debug(
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
    debug("Session received unknown message: #{inspect(any)}")
    {:noreply, state}
  end

  # ----------------------------------------------------------------------------

  def initialize_workflow_document(doc, workflow_id) do
    debug("Initializing SharedDoc with workflow data for #{workflow_id}")

    # Fetch workflow from database
    case Lightning.Workflows.get_workflow(workflow_id,
           include: [:jobs, :edges, :triggers]
         ) do
      nil ->
        warning("Workflow #{workflow_id} not found, initializing empty document")

        doc

      workflow ->
        # Initialize the document with workflow data
        workflow_map = Yex.Doc.get_map(doc, "workflow")
        jobs_array = Yex.Doc.get_array(doc, "jobs")
        edges_array = Yex.Doc.get_array(doc, "edges")
        triggers_array = Yex.Doc.get_array(doc, "triggers")
        positions = Yex.Doc.get_map(doc, "positions")

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

          debug(
            "Initialized workflow document with #{length(workflow.jobs || [])} jobs and their Y.Text bodies"
          )
        end)

        doc
    end
  end
end
