defmodule Lightning.CollaborationHelpers do
  @moduledoc """
  Test helpers for collaboration tests.
  """

  alias Lightning.Collaboration.Topology

  @doc """
  Ensures the `DocumentSupervisor` for `workflow_id` is stopped, polling
  briefly for it to clear from the registry.

  `Topology.base/0` is readable from any process (including `on_exit`
  handlers) because it reads `Application.get_env` rather than a
  process-scoped Mox stub.
  """
  def ensure_doc_supervisor_stopped(workflow_id) do
    registry = Topology.registry()

    case Process.whereis(registry) do
      nil ->
        :ok

      _pid ->
        case lookup_doc_supervisor(registry, "workflow:#{workflow_id}") do
          nil ->
            :ok

          pid ->
            Eventually.eventually(
              fn -> Process.alive?(pid) end,
              false,
              1000,
              1
            )
        end
    end
  end

  defp lookup_doc_supervisor(registry, key) do
    matches =
      Registry.select(registry, [
        {{{:"$1", :"$2"}, :"$3", :"$4"},
         [
           {:andalso, {:==, :"$1", :doc_supervisor},
            {:==, {:binary_part, :"$2", 0, byte_size(key)}, key}}
         ], [:"$3"]}
      ])

    List.first(matches)
  end
end
