defmodule Lightning.CollaborationCase do
  @moduledoc """
  ExUnit case template for tests that exercise the collaboration GenServers
  (`SharedDoc`, `PersistenceWriter`, `DocumentSupervisor`, etc.).

  Each test gets its own `Lightning.Collaboration.Supervisor` started via
  `start_isolated_collaboration/0`, so the registry, dynamic supervisor, and
  `:pg` scope are isolated to that test. `Application.put_env/3` points
  `Lightning.Collaboration.Topology` at the per-test base for the duration of
  the test, so every process in the VM — including GenServer children spawned
  under the supervisor — resolves the right tree without any Mox plumbing.

  When the test exits, the collaboration supervisor is shut down (draining
  `DocumentSupervisor.terminate/2`'s flush) *before* the SQL Sandbox
  connection is checked back in — so any DB writes the `PersistenceWriter`
  does on the way out happen inside the test's sandbox.
  """
  use ExUnit.CaseTemplate

  alias Lightning.Collaboration.Registry
  alias Lightning.Collaboration.Topology

  using do
    quote do
      use Lightning.DataCase, async: false

      import Lightning.CollaborationCase
    end
  end

  setup _tags do
    {:ok, collaboration_base: start_isolated_collaboration()}
  end

  @doc """
  Starts an isolated `Lightning.Collaboration.Supervisor` for the current
  test, overrides `Lightning.Collaboration.Topology` in application config to
  point at it, and registers an `on_exit` hook that drains the supervisor
  before the SQL Sandbox connection is checked back in.

  Returns the base atom of the test's collaboration supervisor.

  This helper is callable directly from any test (e.g. channel tests) that
  needs an isolated collaboration tree without inheriting the full
  `Lightning.CollaborationCase` setup.
  """
  def start_isolated_collaboration do
    base =
      Module.concat([
        Lightning.Collaboration.Test,
        "T#{System.unique_integer([:positive])}"
      ])

    {:ok, sup_pid} =
      Lightning.Collaboration.Supervisor.start_link(name: base)

    # Tear the collaboration tree down via `on_exit` (rather than
    # `start_supervised!`) so the shutdown happens *before* the SQL Sandbox
    # connection is checked back in. ExUnit runs `on_exit` callbacks in
    # LIFO order, and DataCase/ChannelCase's Sandbox stop_owner is
    # registered first — registering ours here makes the collab tree
    # drain first, letting `PersistenceWriter`'s terminate-time DB writes
    # complete inside the test's sandbox.
    ExUnit.Callbacks.on_exit(fn ->
      ref = Process.monitor(sup_pid)
      Process.exit(sup_pid, :shutdown)

      receive do
        {:DOWN, ^ref, :process, ^sup_pid, _} -> :ok
      after
        5_000 -> :ok
      end
    end)

    base
  end

  @doc """
  Starts a `DocumentSupervisor` for the given workflow inside the test's
  isolated collaboration tree.

  Returns a map with `:document_supervisor`, `:persistence_writer`,
  `:shared_doc`, and `:document_name`.
  """
  def start_workflow_collab!(base, workflow, opts \\ []) do
    document_name =
      Keyword.get(opts, :document_name, "workflow:#{workflow.id}")

    {:ok, doc_sup_pid} =
      Lightning.Collaboration.Supervisor.start_child(
        base,
        {Lightning.Collaboration.DocumentSupervisor,
         workflow: workflow,
         document_name: document_name,
         base: base,
         name: Topology.via(base, {:doc_supervisor, document_name})}
      )

    %{shared_doc: sd, persistence_writer: pw} =
      Registry.get_group(base, document_name)

    %{
      document_supervisor: doc_sup_pid,
      persistence_writer: pw,
      shared_doc: sd,
      document_name: document_name
    }
  end
end
