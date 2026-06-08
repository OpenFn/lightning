defmodule Lightning.CollaborationHelpers do
  alias Lightning.Collaboration.Instance
  alias Lightning.Collaboration.Session

  @doc """
  Push a string-keyed map into a named Y.Doc array on the given session,
  as a `Yex.MapPrelim`. Used to inject job/trigger/edge payloads into the
  shared doc from tests.
  """
  def push_to_array(session_pid, array_name, %{} = string_map)
      when is_binary(array_name) do
    Session.update_doc(session_pid, fn doc ->
      Yex.Doc.get_array(doc, array_name)
      |> Yex.Array.push(Yex.MapPrelim.from(string_map))
    end)
  end

  @doc """
  Start an isolated collaboration supervision tree for the calling test and
  return its `%Lightning.Collaboration.Instance{}`.

  Each call builds a unique base name, so the started tree has its own Registry,
  DynamicSupervisor, and `:pg` scope — independent of the application-wide
  singletons and of any other test's tree. `start_supervised!/1` ties the tree's
  lifetime to the test, so it is torn down automatically on exit.

  Pass the returned instance to `start_collaboration_document/3`,
  `ensure_doc_supervisor_stopped/2`, and `stop_all_collaboration_documents/1` to
  drive documents under this isolated tree.
  """
  def start_collaboration_instance do
    base = :"col_#{System.unique_integer([:positive])}"

    ExUnit.Callbacks.start_supervised!(
      {Lightning.Collaboration.Supervisor, name: base}
    )

    Instance.derive(base)
  end

  @doc """
  Start a collaboration document via the production entrypoint and tie its
  lifetime to the calling test.

  Passes `owner: self()` to `Lightning.Collaborate.start_document/_`, so the
  document tree monitors the test process and shuts itself down when the test
  exits — the owner-monitored seam from
  `.claude/guidelines/testable-supervision-trees.md` §3. No `on_exit` wrapper
  needed. Returns whatever `Collaborate.start_document/_` returns.

  Pass an `%Instance{}` (from `start_collaboration_instance/0`) as the first
  argument to drive the document under a test-owned, isolated tree; the
  two-argument form uses the application-wide default instance.

  Prefer this over calling `Collaborate.start_document/_` directly in tests.
  Documents live under a `DocSupervisor` that ExUnit doesn't own (unless you
  started an isolated instance), so one started without an owner would outlive
  the test that created it.
  """
  def start_collaboration_document(
        %Lightning.Workflows.Workflow{} = workflow,
        document_name
      )
      when is_binary(document_name) do
    Lightning.Collaborate.start_document(workflow, document_name, owner: self())
  end

  def start_collaboration_document(
        %Instance{} = instance,
        %Lightning.Workflows.Workflow{} = workflow,
        document_name
      )
      when is_binary(document_name) do
    Lightning.Collaborate.start_document(instance, workflow, document_name,
      owner: self()
    )
  end

  @doc """
  Grant a collaboration process the same per-test access the owner-anchored
  startup hook grants the children it spawns.

  Tests that start a `Session` (or any other collaboration process) directly —
  rather than letting `DocumentSupervisor.init/1` spawn it under `owner: self()`
  — must call this on the returned pid so that process can reach the test's
  database connection and resolve its mocks.

  Runs the configured `:collaboration_process_allow` callback (a no-op outside
  the test env) for the database sandbox and the `Lightning` mock — the same
  seam the startup hook uses — and additionally grants the per-test mocks a
  `Session` resolves while saving (e.g. the usage limiter). Each `Mox.allow` is
  guarded so a test that never stubbed a given mock is unaffected.
  """
  def allow_collaboration_process(pid) when is_pid(pid) do
    allow =
      Application.get_env(
        :lightning,
        :collaboration_process_allow,
        fn _owner, _pid -> :ok end
      )

    allow.(self(), pid)

    # The save path also resolves these mocks from inside the Session process.
    # `set_mox_global` previously made every mock visible cross-process; under
    # private Mox we allow them explicitly. A bare allow is harmless when the
    # test set no expectations on the mock.
    Enum.each(
      [
        Lightning.Extensions.MockUsageLimiter,
        Lightning.Extensions.MockProjectHook,
        Lightning.Extensions.MockAccountHook,
        Lightning.Extensions.MockCollectionHook,
        Lightning.MockConfig
      ],
      fn mock -> safe_mox_allow(mock, pid) end
    )

    pid
  end

  defp safe_mox_allow(mock, pid) do
    Mox.allow(mock, self(), pid)
  rescue
    ArgumentError -> :ok
  end

  @doc """
  Stop the document supervisor for a given workflow id.

  Thin wrapper over `Lightning.Collaborate.stop_document/_` (synchronous,
  idempotent, flush-inclusive). Safe in an `on_exit`: because the stop is
  synchronous, the PersistenceWriter's final DB flush has completed by the time
  it returns — see `Lightning.Collaborate.stop_document/_`.

  Pass an `%Instance{}` to stop a document under a test-owned isolated tree; the
  single-argument form targets the application-wide default instance.
  """
  def ensure_doc_supervisor_stopped(workflow_id) do
    Lightning.Collaborate.stop_document("workflow:#{workflow_id}")
  end

  def ensure_doc_supervisor_stopped(%Instance{} = instance, workflow_id) do
    Lightning.Collaborate.stop_document(instance, "workflow:#{workflow_id}")
  end

  @doc """
  Stop every collaboration document still running.

  A safety net for the `async: false` collaboration suites. Each document should
  already be tied to its own test via `start_collaboration_document/_` (or
  `ensure_doc_supervisor_stopped/_`); this only catches a stray document a call
  site left running, keeping it out of the next test.

  Pass an `%Instance{}` to sweep only that test-owned tree. A test that drives
  its own isolated instance does not need this sweep at all: the instance's
  supervisor is `start_supervised!`-owned and `owner: self()` monitoring already
  tears every document down on exit.
  """
  def stop_all_collaboration_documents do
    stop_all_collaboration_documents(Instance.default())
  end

  def stop_all_collaboration_documents(%Instance{} = instance) do
    Lightning.Collaboration.Registry.doc_supervisor_names(instance.registry)
    |> Enum.each(&Lightning.Collaborate.stop_document(instance, &1))
  end
end
