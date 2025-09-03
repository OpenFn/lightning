defmodule Lightning.Collaborate do
  alias Lightning.Collaboration.DocumentSupervisor
  alias Lightning.Collaboration.Registry
  alias Lightning.Collaboration.Session
  alias Lightning.Collaboration.Supervisor, as: SessionSupervisor

  require Logger

  @pg_scope :workflow_collaboration

  def start(opts) do
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

    # We don't register the session in the Registry as it may be started
    # more than once for the same workflow and user.
    # Think different clients or browser tabs.
    {:ok, _session_pid} =
      SessionSupervisor.start_child({
        Session,
        [workflow_id: workflow_id, user: user, parent_pid: parent_pid]
      })
  end

  def start_document(workflow_id) do
    {:ok, doc_supervisor_pid} =
      SessionSupervisor.start_child(
        {DocumentSupervisor, workflow_id: workflow_id}
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
