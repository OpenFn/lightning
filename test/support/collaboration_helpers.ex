defmodule Lightning.CollaborationHelpers do
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
  Start a collaboration document via the production entrypoint and tie its
  lifetime to the calling test.

  Passes `owner: self()` to `Lightning.Collaborate.start_document/3`, so the
  document tree monitors the test process and shuts itself down when the test
  exits — the owner-monitored seam from
  `.claude/guidelines/testable-supervision-trees.md` §3. No `on_exit` wrapper
  needed. Returns whatever `Collaborate.start_document/3` returns.

  Prefer this over calling `Collaborate.start_document/3` directly in tests.
  Documents live under the global `DocSupervisor`, which ExUnit doesn't own, so
  one started without an owner would outlive the test that created it.
  `stop_all_collaboration_documents/0` still runs as a final sweep for the
  serial suites, in case a call site forgets.
  """
  def start_collaboration_document(
        %Lightning.Workflows.Workflow{} = workflow,
        document_name
      )
      when is_binary(document_name) do
    Lightning.Collaborate.start_document(workflow, document_name, owner: self())
  end

  @doc """
  Stop the document supervisor for a given workflow id.

  Thin wrapper over `Lightning.Collaborate.stop_document/1` (synchronous,
  idempotent, flush-inclusive). Safe in an `on_exit`: because the stop is
  synchronous, the PersistenceWriter's final DB flush has completed by the time
  it returns — see `Lightning.Collaborate.stop_document/1`.
  """
  def ensure_doc_supervisor_stopped(workflow_id) do
    Lightning.Collaborate.stop_document("workflow:#{workflow_id}")
  end

  @doc """
  Stop every collaboration document still running.

  A safety net for the `async: false` collaboration suites. Each document should
  already be tied to its own test via `start_collaboration_document/2` (or
  `ensure_doc_supervisor_stopped/1`); this only catches a stray document a call
  site left running, keeping it out of the next test.
  """
  def stop_all_collaboration_documents do
    Lightning.Collaboration.Registry.doc_supervisor_names()
    |> Enum.each(&Lightning.Collaborate.stop_document/1)
  end
end
