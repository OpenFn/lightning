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
    room_topic = Keyword.get(opts, :room_topic, "workflow:#{workflow.id}")

    # Extract document name from room topic
    # "workflow:collaborate:123" -> "workflow:123"
    # "workflow:collaborate:123:v22" -> "workflow:123:v22"
    document_name = extract_document_name(room_topic)

    Logger.info(
      "Starting collaboration for document: #{document_name} (workflow: #{workflow.id})"
    )

    # Ensure document supervisor exists for this document
    case lookup_shared_doc(document_name) do
      nil ->
        Logger.info("Starting document for #{document_name}")
        {:ok, _doc_supervisor_pid} = start_document(workflow, document_name)

      _shared_doc_pid ->
        Logger.info("Found existing document for #{document_name}")
        :ok
    end

    # Start session for this user
    SessionSupervisor.start_child({
      Session,
      workflow: workflow,
      user: user,
      parent_pid: parent_pid,
      document_name: document_name,
      name: Registry.via({:session, "#{document_name}:#{session_id}", user.id})
    })
  end

  def start_document(
        %Lightning.Workflows.Workflow{} = workflow,
        document_name
      ) do
    {:ok, doc_supervisor_pid} =
      SessionSupervisor.start_child(
        {DocumentSupervisor,
         workflow: workflow,
         document_name: document_name,
         name: Registry.via({:doc_supervisor, document_name})}
      )

    {:ok, doc_supervisor_pid}
  end

  defp lookup_shared_doc(document_name) do
    case :pg.get_members(@pg_scope, document_name) do
      [] -> nil
      [shared_doc_pid | _] -> shared_doc_pid
    end
  end

  # Extracts document name from room topic.
  #
  # Examples:
  #   "workflow:collaborate:123" -> "workflow:123"
  #   "workflow:collaborate:123:v22" -> "workflow:123:v22"
  #   "workflow:123" -> "workflow:123"
  @spec extract_document_name(String.t()) :: String.t()
  defp extract_document_name("workflow:collaborate:" <> rest) do
    case String.split(rest, ":v", parts: 2) do
      [workflow_id, version] -> "workflow:#{workflow_id}:v#{version}"
      [workflow_id] -> "workflow:#{workflow_id}"
    end
  end

  # Fallback for topics that don't match "workflow:collaborate:" pattern
  defp extract_document_name(topic), do: topic

  defdelegate lookup(key), to: Registry
  defdelegate whereis(key), to: Registry
end
