defmodule Lightning.Collaborate do
  alias Lightning.Collaboration.DocumentSupervisor
  alias Lightning.Collaboration.Registry
  alias Lightning.Collaboration.Session
  alias Lightning.Collaboration.Supervisor, as: SessionSupervisor

  require Logger

  @pg_scope :workflow_collaboration

  @spec start(opts :: Keyword.t()) :: GenServer.on_start()
  def start(opts) do
    session_id = Ecto.UUID.generate()
    parent_pid = Keyword.get(opts, :parent_pid, self())

    user = Keyword.fetch!(opts, :user)

    workflow_id = Keyword.fetch!(opts, :workflow_id)

    case lookup_shared_doc(workflow_id) do
      nil ->
        Logger.info("Starting document for workflow #{workflow_id}")
        {:ok, _doc_supervisor_pid} = start_document(workflow_id)

      shared_doc_pid when is_pid(shared_doc_pid) ->
        shared_doc_pid
    end

    # IDEA: Maybe we should link the parent process to the session?
    # Using Process.link/1?
    # Because we should be able to do something if the session crashes,
    # because the WorkflowChannel is expecting it's pid to be alive.
    SessionSupervisor.start_child({
      Session,
      workflow_id: workflow_id,
      user: user,
      parent_pid: parent_pid,
      name:
        Registry.via(
          {:session, "workflow:#{workflow_id}:#{session_id}", user.id}
        )
    })
  end

  def start_document(workflow_id) do
    {:ok, doc_supervisor_pid} =
      SessionSupervisor.start_child(
        {DocumentSupervisor,
         workflow_id: workflow_id,
         name: Registry.via({:doc_supervisor, "workflow:#{workflow_id}"})}
      )

    {:ok, doc_supervisor_pid}
  end

  defp lookup_shared_doc(workflow_id) do
    case :pg.get_members(@pg_scope, workflow_id) do
      [] -> nil
      [shared_doc_pid | _] -> shared_doc_pid
    end
  end

  defdelegate lookup(key), to: Registry
  defdelegate whereis(key), to: Registry
end
