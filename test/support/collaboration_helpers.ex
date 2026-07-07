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
  Ensure the document supervisor is stopped for a given workflow id.

  This document supervisor has two children:
  - PersistenceWriter
  - SharedDoc

  When the parent process is stopped, the Session process is stopped.
  The SharedDoc auto exits when there are no more Session processes observing it.

  When the SharedDoc process is stopped, the PersistenceWriter process does
  it's own shutdown. This can take a millisecond or two, so to avoid
  test errors where the PersistenceWriter tries to write to the database
  after the test has finished, we wait for it's parent (DocumentSupervisor)
  to be stopped.
  """
  def ensure_doc_supervisor_stopped(workflow_id) do
    procs =
      Lightning.Collaboration.Registry.get_group("workflow:#{workflow_id}")

    if procs[:doc_supervisor] do
      eventually_stop(procs.doc_supervisor)
    end
  end

  defp eventually_stop(pid) do
    Eventually.eventually(fn -> Process.alive?(pid) end, false, 1000, 1)
  end
end
