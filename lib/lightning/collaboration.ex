defmodule Lightning.Collaborate do
  @moduledoc """
  Public API for starting collaborative workflow editing sessions.

  This module serves as the main entry point for collaborative editing,
  coordinating the creation and management of document and session processes
  for workflow collaboration.

  All collaborative sessions require a workflow struct.

  ## Example

      # Existing workflow
      workflow = Lightning.Workflows.get_workflow(workflow_id)

      Collaborate.start(user: user, workflow: workflow)

      # New workflow
      workflow = %Lightning.Workflows.Workflow{
        id: workflow_id,
        project_id: project_id,
        name: "",
        positions: %{}
      }

      Collaborate.start(user: user, workflow: workflow)
  """
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
    workflow = Keyword.fetch!(opts, :workflow)

    case lookup_shared_doc(workflow.id) do
      nil ->
        Logger.info("Starting document for workflow #{workflow.id}")
        {:ok, _doc_supervisor_pid} = start_document(workflow)

      shared_doc_pid when is_pid(shared_doc_pid) ->
        shared_doc_pid
    end

    SessionSupervisor.start_child({
      Session,
      workflow: workflow,
      user: user,
      parent_pid: parent_pid,
      name:
        Registry.via(
          {:session, "workflow:#{workflow.id}:#{session_id}", user.id}
        )
    })
  end

  def start_document(%Lightning.Workflows.Workflow{} = workflow) do
    {:ok, doc_supervisor_pid} =
      SessionSupervisor.start_child(
        {DocumentSupervisor,
         workflow: workflow,
         name: Registry.via({:doc_supervisor, "workflow:#{workflow.id}"})}
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
