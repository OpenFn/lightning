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
  Start a collaboration document via the production entrypoint and bind its
  lifetime to the calling test.

  Passes `owner: self()` to `Lightning.Collaborate.start_document/3`, so the
  document tree monitors the test process and self-terminates when it exits —
  the owner-monitored seam from
  `.claude/guidelines/testable-supervision-trees.md` §3, so no `on_exit` wrapper
  is needed. Returns `Collaborate.start_document/3`'s result.

  Prefer this over a bare `Collaborate.start_document/3` in tests: documents
  started this way live under the global `DocSupervisor`, which ExUnit does
  not own, so an un-owned doc would otherwise outlive the test. The blanket
  `stop_all_collaboration_documents/0` `on_exit` net remains as belt-and-braces
  for serial suites.
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

  A belt-and-braces `on_exit` net for `async: false` collaboration suites: each
  doc should already be bound to its own test via `start_collaboration_document/2`
  (or `ensure_doc_supervisor_stopped/1`), so this only catches a future un-bound
  call site leaking a global doc into the next serial test.
  """
  def stop_all_collaboration_documents do
    Lightning.Collaboration.Registry.doc_supervisor_names()
    |> Enum.each(&Lightning.Collaborate.stop_document/1)
  end
end
