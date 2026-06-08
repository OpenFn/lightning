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

  Optionally monitors an `:owner` pid (passed through the child spec). When that
  owner goes `:DOWN`, the supervisor stops `:normal` — running `terminate/2`'s
  flush, and not restarting (transient). This is the owner-monitored
  self-cleanup seam from
  `.claude/guidelines/testable-supervision-trees.md` §3: any caller gets
  deterministic teardown by passing `owner: self()`. With no owner (the
  production default) the document outlives its starter as before.
  """
  use GenServer

  alias Lightning.Collaboration.Persistence
  alias Lightning.Collaboration.PersistenceWriter
  alias Lightning.Collaboration.Registry

  require Logger

  def start_link(args, opts \\ []) do
    GenServer.start_link(__MODULE__, args, opts)
  end

  @doc """
  Gracefully stops the DocumentSupervisor and its children.

  Synchronous: returns only once `terminate/2` has run, which flushes the
  PersistenceWriter (via the SharedDoc) and stops both children. Because the
  child spec uses `restart: :transient`, a `:normal` stop is not restarted by
  the DynamicSupervisor.
  """
  def stop(pid, timeout \\ 5_000) when is_pid(pid) do
    GenServer.stop(pid, :normal, timeout)
  end

  @impl true
  def init(opts) do
    workflow = Keyword.fetch!(opts, :workflow)
    document_name = Keyword.fetch!(opts, :document_name)
    registry = Keyword.get(opts, :registry, Registry)
    pg_scope = Keyword.get(opts, :pg_scope, :workflow_collaboration)

    owner = Keyword.get(opts, :owner)

    # Optionally monitor an owner pid; when it goes :DOWN we stop :normal so the
    # document tree dies with its owner. nil (production default) → no monitor.
    owner_ref = if is_pid(owner), do: Process.monitor(owner), else: nil

    {:ok, persistence_writer_pid} =
      PersistenceWriter.start_link(
        document_name: document_name,
        workflow_id: workflow.id,
        registry: registry,
        name: Registry.via(registry, {:persistence_writer, document_name})
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
        name: Registry.via(registry, {:shared_doc, document_name})
      )

    # Register with :pg using document_name so versioned rooms are isolated
    :ok = register_shared_doc_with_pg(pg_scope, document_name, shared_doc_pid)

    shared_doc_ref = Process.monitor(shared_doc_pid)

    # When started on behalf of an owner pid, give that owner a chance to grant
    # the freshly spawned children whatever process-scoped access they'll need
    # to do their work (the two children below both write through their own
    # processes). The default is a no-op, so production wiring is untouched; a
    # real callback is only configured under the test environment. We run this
    # synchronously here, before the SharedDoc begins flushing, so the children
    # are set up before they touch any shared resource.
    if is_pid(owner) do
      allow = grant_process_access_fun()
      allow.(owner, persistence_writer_pid)
      allow.(owner, shared_doc_pid)
    end

    {:ok,
     %{
       workflow: workflow,
       owner_ref: owner_ref,
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
    # Drop the owner monitor if it's still live (e.g. stopped via stop/2 while
    # the owner is alive) so no stray :DOWN is delivered after we're gone.
    if state[:owner_ref], do: Process.demonitor(state.owner_ref, [:flush])

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
  def handle_info(
        {:DOWN, ref, :process, _pid, reason},
        %{owner_ref: ref} = state
      ) do
    Logger.debug("Owner DOWN, stopping document. reason: #{inspect(reason)}")

    Process.demonitor(ref, [:flush])

    # Stop :normal so terminate/2 runs the flush; :transient => no restart.
    {:stop, :normal, %{state | owner_ref: nil}}
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, state) do
    key =
      [:persistence_writer_ref, :shared_doc_ref]
      |> Enum.find(fn key -> ref == state[key] end)

    Logger.debug("DOWN: #{inspect(key)} reason: #{inspect(reason)}")

    Process.demonitor(ref, [:flush])

    # We're not going to stop the children here, we handle that in terminate.

    {:stop, :normal, state |> Map.put(key, nil)}
  end

  defp register_shared_doc_with_pg(pg_scope, document_name, shared_doc_pid) do
    :pg.join(pg_scope, document_name, shared_doc_pid)
  end

  defp grant_process_access_fun do
    Application.get_env(
      :lightning,
      :collaboration_process_allow,
      fn _owner, _pid -> :ok end
    )
  end
end
