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
  alias Lightning.Collaboration.Instance
  alias Lightning.Collaboration.Registry
  alias Lightning.Collaboration.Session
  alias Lightning.Collaboration.Supervisor, as: SessionSupervisor

  require Logger

  @spec start(opts :: Keyword.t()) :: GenServer.on_start()
  @spec start(instance :: Instance.t(), opts :: Keyword.t()) ::
          GenServer.on_start()
  def start(instance \\ Instance.default(), opts) do
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

    with {:ok, started_here?} <-
           ensure_document(instance, workflow, document_name) do
      case start_session(instance, document_name,
             workflow: workflow,
             user: user,
             parent_pid: parent_pid
           ) do
        {:ok, _session_pid} = ok ->
          ok

        error ->
          # Only tear down a document this call created: one we merely found may
          # have other sessions attached to it.
          if started_here?, do: stop_document(instance, document_name)
          error
      end
    end
  end

  # Ensures the document tree for `document_name` is running, reporting whether
  # THIS call created it. The answer can only come from the start attempt: `:pg`
  # membership is registered inside `DocumentSupervisor.init/1`, so a lookup
  # taken beforehand says "absent" for a document another caller is mid-start.
  @spec ensure_document(
          Instance.t(),
          Lightning.Workflows.Workflow.t(),
          String.t()
        ) :: {:ok, boolean()} | {:error, term()}
  defp ensure_document(instance, workflow, document_name) do
    case start_or_find_document(instance, workflow, document_name, []) do
      {:created, _pid} ->
        Logger.info("Starting document for #{document_name}")
        {:ok, true}

      {:found, _pid} ->
        Logger.info("Found existing document for #{document_name}")
        {:ok, false}

      {:error, _reason} = error ->
        error
    end
  end

  @spec start_session(Instance.t(), String.t(), Keyword.t()) ::
          GenServer.on_start()
  defp start_session(instance, document_name, opts) do
    session_id = Ecto.UUID.generate()
    user = Keyword.fetch!(opts, :user)

    SessionSupervisor.start_child(
      instance.dynamic_supervisor,
      {
        Session,
        workflow: Keyword.fetch!(opts, :workflow),
        user: user,
        parent_pid: Keyword.fetch!(opts, :parent_pid),
        document_name: document_name,
        registry: instance.registry,
        pg_scope: instance.pg_scope,
        name:
          Registry.via(
            instance.registry,
            {:session, "#{document_name}:#{session_id}", user.id}
          )
      }
    )
  end

  @doc """
  Deterministically stops the collaborative document for `document_name`.

  Tears down its DocumentSupervisor, SharedDoc and PersistenceWriter (with a
  final flush). Synchronous and idempotent: returns `:ok` whether or not a
  document is running. The symmetric partner to `start_document/2`.
  """
  @spec stop_document(instance :: Instance.t(), document_name :: String.t()) ::
          :ok
  def stop_document(instance \\ Instance.default(), document_name) do
    case Registry.whereis(instance.registry, {:doc_supervisor, document_name}) do
      nil ->
        :ok

      pid ->
        try do
          DocumentSupervisor.stop(pid)
          :ok
        catch
          :exit, _ -> :ok
        end
    end
  end

  @doc """
  Starts the collaborative document tree for `document_name`.

  `document_name` is a positional payload (domain identity); the registered name
  and the optional `owner` are process configuration and live in trailing `opts`,
  per `.claude/guidelines/testable-supervision-trees.md` §1.

  ## Options

  - `:owner` — a pid the document tree monitors. When that pid goes `:DOWN`, the
    tree stops `:normal` (running its flush via `terminate/2`; `:transient` means
    no restart). Lets any caller — a test, a request — get deterministic cleanup
    by passing `owner: self()`, with no wrapper. Defaults to `nil` (no monitor),
    so production documents outlive the LiveView that starts them.
  """
  @spec start_document(
          workflow :: Lightning.Workflows.Workflow.t(),
          document_name :: String.t()
        ) :: {:ok, pid()} | {:error, term()}
  @spec start_document(
          workflow :: Lightning.Workflows.Workflow.t(),
          document_name :: String.t(),
          opts :: Keyword.t()
        ) :: {:ok, pid()} | {:error, term()}
  @spec start_document(
          instance :: Instance.t(),
          workflow :: Lightning.Workflows.Workflow.t(),
          document_name :: String.t()
        ) :: {:ok, pid()} | {:error, term()}
  @spec start_document(
          instance :: Instance.t(),
          workflow :: Lightning.Workflows.Workflow.t(),
          document_name :: String.t(),
          opts :: Keyword.t()
        ) :: {:ok, pid()} | {:error, term()}
  def start_document(%Lightning.Workflows.Workflow{} = workflow, document_name) do
    start_document(Instance.default(), workflow, document_name, [])
  end

  def start_document(%Instance{} = instance, workflow, document_name) do
    start_document(instance, workflow, document_name, [])
  end

  def start_document(
        %Lightning.Workflows.Workflow{} = workflow,
        document_name,
        opts
      )
      when is_list(opts) do
    start_document(Instance.default(), workflow, document_name, opts)
  end

  def start_document(
        %Instance{} = instance,
        %Lightning.Workflows.Workflow{} = workflow,
        document_name,
        opts
      )
      when is_list(opts) do
    case start_or_find_document(instance, workflow, document_name, opts) do
      {:created, pid} -> {:ok, pid}
      {:found, pid} -> {:ok, pid}
      {:error, _reason} = error -> error
    end
  end

  # Starts the document tree, distinguishing a tree this call created from one
  # that was already running. Public only so the created/found distinction can
  # be asserted directly; `start/2`'s teardown correctness rests on it.
  @doc false
  @spec start_or_find_document(
          Instance.t(),
          Lightning.Workflows.Workflow.t(),
          String.t(),
          Keyword.t()
        ) :: {:created, pid()} | {:found, pid()} | {:error, term()}
  def start_or_find_document(instance, workflow, document_name, opts) do
    doc_opts =
      [
        workflow: workflow,
        document_name: document_name,
        owner: Keyword.get(opts, :owner),
        registry: instance.registry,
        pg_scope: instance.pg_scope,
        name: Registry.via(instance.registry, {:doc_supervisor, document_name})
      ]
      |> then(fn base ->
        # Only forward auto_exit when a caller supplied it, so the production
        # default (DocumentSupervisor's own `auto_exit: true`) is preserved.
        case Keyword.fetch(opts, :auto_exit) do
          {:ok, auto_exit} -> Keyword.put(base, :auto_exit, auto_exit)
          :error -> base
        end
      end)

    case SessionSupervisor.start_child(
           instance.dynamic_supervisor,
           {DocumentSupervisor, doc_opts}
         ) do
      {:ok, pid} -> {:created, pid}
      {:error, {:already_started, pid}} -> {:found, pid}
      {:error, _reason} = error -> error
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
