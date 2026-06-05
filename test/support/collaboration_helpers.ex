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

  An `on_exit` net for `async: false` collaboration suites, where no document
  should outlive a serial test. See `ensure_doc_supervisor_stopped/1`.
  """
  def stop_all_collaboration_documents do
    Lightning.Collaboration.Registry.doc_supervisor_names()
    |> Enum.each(&Lightning.Collaborate.stop_document/1)
  end
end
