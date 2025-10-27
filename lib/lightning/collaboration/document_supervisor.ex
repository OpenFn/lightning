defmodule Lightning.Collaboration.DocumentSupervisor do
  @moduledoc """
  Manages the lifecycle of collaborative workflow document processes.

  This GenServer coordinates a SharedDoc and PersistenceWriter for each
  collaborative workflow document. It starts both processes with proper
  dependencies, registers the SharedDoc with the `:pg` process group for
  cluster-wide coordination, and handles graceful shutdown by ensuring
  the SharedDoc flushes data to the PersistenceWriter before termination.

  Uses a transient restart strategy, only restarting if the supervisor
  itself crashes, not when child processes exit normally. Monitors both
  child processes and stops itself if either child crashes.
  """
  use GenServer

  import Lightning.Collaboration.Registry, only: [via: 1]

  alias Lightning.Collaboration.Persistence
  alias Lightning.Collaboration.PersistenceWriter

  require Logger

  @pg_scope :workflow_collaboration

  def start_link(args, opts \\ []) do
    GenServer.start_link(__MODULE__, args, opts)
  end

  @impl true
  def init(opts) do
    workflow = Keyword.fetch!(opts, :workflow)
    document_name = Keyword.fetch!(opts, :document_name)

    {:ok, persistence_writer_pid} =
      PersistenceWriter.start_link(
        document_name: document_name,
        workflow_id: workflow.id,
        name: via({:persistence_writer, document_name})
      )

    persistence_writer_ref = Process.monitor(persistence_writer_pid)

    {:ok, shared_doc_pid} =
      Yex.Sync.SharedDoc.start_link(
        [
          doc_name: document_name,
          auto_exit: true,
          persistence:
            {Persistence,
             %{
               workflow: workflow,
               persistence_writer: persistence_writer_pid
             }}
        ],
        name: via({:shared_doc, document_name})
      )

    # Register with :pg using document_name so versioned rooms are isolated
    :ok = register_shared_doc_with_pg(document_name, shared_doc_pid)

    shared_doc_ref = Process.monitor(shared_doc_pid)

    {:ok,
     %{
       workflow: workflow,
       persistence_writer_pid: persistence_writer_pid,
       persistence_writer_ref: persistence_writer_ref,
       shared_doc_pid: shared_doc_pid,
       shared_doc_ref: shared_doc_ref
     }}
  end

  def child_spec(opts) do
    {id, opts} =
      opts
      |> Keyword.put_new_lazy(:id, fn -> Ecto.UUID.generate() end)
      |> Keyword.pop!(:id)

    {opts, args} = Keyword.split_with(opts, fn {k, _v} -> k in [:name] end)

    %{
      id: id,
      start: {__MODULE__, :start_link, [args, opts]},
      type: :worker,
      # Only restart if the DocumentSupervisor crashes.
      restart: :transient,
      shutdown: 5000
    }
  end

  @impl true
  def terminate(_reason, state) do
    # Specifically stop the SharedDoc first, which sends a flush_and_stop
    # message to the PersistenceWriter. So we usually don't need to stop the
    # PersistenceWriter if the SharedDoc is exiting normally, but just in case
    # we try to stop it gracefully.

    if state.shared_doc_ref,
      do: Process.demonitor(state.shared_doc_ref, [:flush])

    if state.shared_doc_pid do
      try do
        GenServer.stop(state.shared_doc_pid, :normal, 5000)
      catch
        :exit, _ -> :ok
      end
    end

    Logger.debug("Stopping PersistenceWriter")

    if state.persistence_writer_ref,
      do: Process.demonitor(state.persistence_writer_ref, [:flush])

    if state.persistence_writer_pid do
      try do
        GenServer.stop(state.persistence_writer_pid, :normal, 5000)
      catch
        :exit, _ -> :ok
      end
    end

    :ok
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, reason}, state) do
    key =
      [:persistence_writer_ref, :shared_doc_ref]
      |> Enum.find(fn key -> ref == state[key] end)

    Logger.debug("DOWN: #{inspect(key)} reason: #{inspect(reason)}")

    Process.demonitor(ref, [:flush])

    # We're not going to stop the children here, we handle that in terminate.

    {:stop, :normal, state |> Map.put(key, nil)}
  end

  # Supervisor.start_link(children, strategy: :one_for_all)
  defp register_shared_doc_with_pg(document_name, shared_doc_pid) do
    :pg.join(@pg_scope, document_name, shared_doc_pid)
  end
end
