defmodule Lightning.Graph do
  @moduledoc """
  A graph model for workflows transversal.
  """
  defstruct nodes: MapSet.new(), edges: MapSet.new()
  @type t :: %__MODULE__{nodes: MapSet.t(), edges: MapSet.t()}

  @spec new() :: t()
  def new, do: %__MODULE__{nodes: MapSet.new(), edges: MapSet.new()}

  @spec add_edge(t(), atom, atom) :: t()
  def add_edge(graph, from, to) do
    %__MODULE__{
      nodes: MapSet.union(graph.nodes, MapSet.new([from, to])),
      edges: MapSet.put(graph.edges, {from, to})
    }
  end

  @spec remove_edges(t(), [{any(), any()}]) :: t()
  def remove_edges(graph, edges) do
    edges = MapSet.difference(graph.edges, edges |> MapSet.new())

    nodes =
      edges
      |> Enum.flat_map(fn {a, b} -> [a, b] end)
      |> MapSet.new()

    %__MODULE__{edges: edges, nodes: nodes}
  end

  @spec prune(t(), any) :: t()
  def prune(graph, node) do
    graph.edges
    |> Enum.filter(fn {from, to} -> node in [from, to] end)
    |> case do
      [] ->
        graph

      edges ->
        graph = remove_edges(graph, edges)

        edges
        |> Enum.reduce(graph, fn {_from, to}, graph ->
          graph |> prune(to)
        end)
    end
  end

  def nodes(graph, opts \\ [as: []]) do
    graph.nodes |> Enum.into(opts[:as])
  end
end
