defmodule Lightning.Workflows.Graph do
  @moduledoc """
  Utility to construct and manipulate a graph/plan made out of Jobs
  """
  alias Lightning.Workflows.Workflow
  defstruct [:digraph, :root, :jobs]

  @type vertex :: {Ecto.UUID.t()}

  @type t :: %__MODULE__{
          digraph: :digraph.graph(),
          root: vertex(),
          jobs: [Lightning.Workflows.Job.t()]
        }

  @spec new(workflow :: Workflow.t()) :: __MODULE__.t()
  def new(%Workflow{} = workflow) do
    g = :digraph.new()

    for j <- workflow.jobs do
      :digraph.add_vertex(g, to_vertex(j))
    end

    for e <- workflow.edges do
      if e.condition in [:on_job_failure, :on_job_success] do
        :digraph.add_edge(
          g,
          to_vertex(%{id: e.source_job_id}),
          to_vertex(%{id: e.target_job_id})
        )
      end
    end

    root =
      if workflow.edges == [] do
        nil
      else
        get_root(g)
      end

    %__MODULE__{digraph: g, root: root, jobs: workflow.jobs}
  end

  @spec remove(__MODULE__.t(), Ecto.UUID.t()) :: __MODULE__.t()
  def remove(%__MODULE__{digraph: g} = graph, job_id) do
    vertex =
      :digraph.vertices(g)
      |> Enum.find(fn {id} -> id == job_id end)

    :digraph.del_vertex(g, vertex)
    prune(graph)

    %{graph | jobs: vertices(graph)}
  end

  @spec vertices(__MODULE__.t()) :: [Lightning.Workflows.Job.t()]
  def vertices(%__MODULE__{digraph: g, jobs: jobs}) do
    :digraph_utils.topsort(g)
    |> Enum.map(fn {id} ->
      Enum.find(jobs, &match?(%{id: ^id}, &1))
    end)
  end

  defp get_root(g) do
    {:yes, root} = :digraph_utils.arborescence_root(g)
    root
  end

  defp get_reachable(%__MODULE__{} = graph) do
    [graph.root] ++
      :digraph_utils.reachable_neighbours([graph.root], graph.digraph)
  end

  defp prune(%__MODULE__{} = graph) do
    reachable = get_reachable(graph)

    unreachable =
      :digraph.vertices(graph.digraph)
      |> Enum.filter(fn v -> v not in reachable end)

    true = :digraph.del_vertices(graph.digraph, unreachable)
  end

  defp to_vertex(%{id: id}) do
    {id}
  end
end
