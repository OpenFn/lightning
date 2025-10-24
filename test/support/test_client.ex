defmodule Lightning.Collaboration.TestClient do
  @moduledoc false

  # This is a client for testing the collaboration system.
  # Used to test the collaboration system by simulating a client
  # that can connect to a shared doc and sync data with it.
  #
  # Not used in production.
  #
  # see: test/lightning/collaboration/session_test.exs

  use GenServer
  alias Lightning.Collaboration.Utils
  require Logger

  def init(opts) do
    shared_doc_pid = opts[:shared_doc_pid]
    client_doc = Yex.Doc.new()

    {:ok, monitor_ref} = Yex.Doc.monitor_update(client_doc)

    {:ok,
     %{
       client_doc: client_doc,
       shared_doc_pid: shared_doc_pid,
       monitor_ref: monitor_ref
     }, {:continue, :sync}}
  end

  def handle_continue(:sync, state) do
    # Observe the SharedDoc to receive sync messages
    observe(state.shared_doc_pid)
    start_sync(state.shared_doc_pid, state.client_doc)

    {:noreply, state}
  end

  def add_job(pid, job) do
    GenServer.call(pid, {:add_job, job})
  end

  defp observe(shared_doc_pid) do
    Yex.Sync.SharedDoc.observe(shared_doc_pid)
  end

  defp start_sync(shared_doc_pid, client_doc) do
    {:ok, step1} = Yex.Sync.get_sync_step1(client_doc)
    local_message = Yex.Sync.message_encode!({:sync, step1})
    Yex.Sync.SharedDoc.start_sync(shared_doc_pid, local_message)
  end

  def handle_call(:unobserve, _from, state) do
    Yex.Sync.SharedDoc.unobserve(state.shared_doc_pid)

    {:reply, :ok, %{state | shared_doc_pid: nil}}
  end

  def handle_call({:observe, shared_doc_pid}, _from, state) do
    observe(shared_doc_pid)
    start_sync(shared_doc_pid, state.client_doc)
    {:reply, :ok, %{state | shared_doc_pid: shared_doc_pid}}
  end

  def handle_call({:add_job, job}, _from, state) do
    Logger.debug("Adding job to client doc")

    # Convert the string-keyed map to a Yex.MapPrelim
    job_prelim = Yex.MapPrelim.from(job)

    # Add the job without a transaction to avoid hanging
    Yex.Doc.get_array(state.client_doc, "jobs")
    |> Yex.Array.push(job_prelim)

    {:reply, :ok, state}
  end

  def handle_call(:get_doc, _from, state) do
    {:reply, state.client_doc, state}
  end

  def handle_call(:get_jobs, _from, state) do
    jobs =
      state.client_doc
      |> Yex.Doc.get_array("jobs")
      |> Yex.Array.to_list()

    {:reply, jobs, state}
  end

  def handle_info({:update_v1, update, _origin, _ydoc}, state) do
    %{shared_doc_pid: shared_doc_pid} = state

    with {:ok, s} <- Yex.Sync.get_update(update),
         {:ok, message} <- Yex.Sync.message_encode({:sync, s}) do
      Yex.Sync.SharedDoc.send_yjs_message(shared_doc_pid, message)
    else
      message ->
        Logger.debug(":update_v1 " <> inspect(message))
    end

    {:noreply, state}
  end

  def handle_info({:yjs, msg, from}, state) do
    # from is always from outside of this process
    with {:ok, {:sync, sync_message}} <- Yex.Sync.message_decode(msg),
         {:ok, reply} <-
           Yex.Sync.read_sync_message(
             sync_message,
             state.client_doc,
             state.shared_doc_pid
           ) do
      Logger.debug(
        "handle_info :yjs :reply: #{Utils.decipher_message(msg) |> inspect}"
      )

      Yex.Sync.SharedDoc.send_yjs_message(
        from,
        Yex.Sync.message_encode!({:sync, reply})
      )

      {:noreply, state}
    else
      {:error, message} ->
        Logger.debug(":yjs " <> inspect(message))

      _ ->
        Logger.debug(
          "handle_info :yjs :ok: #{Utils.decipher_message(msg) |> inspect}"
        )
    end

    {:noreply, state}
  end

  def terminate(_reason, state) do
    Yex.Sync.SharedDoc.unobserve(state.shared_doc_pid)
    Yex.Doc.demonitor_update(state.monitor_ref)
    :ok
  end
end
