defmodule Lightning.Graph do
  @moduledoc """
  A graph model for workflows transversal.
  """
  defstruct nodes: MapSet.new(), edges: MapSet.new()
  @type t :: %__MODULE__{nodes: MapSet.t(), edges: MapSet.t()}

  @spec new() :: t()
  def new, do: %__MODULE__{nodes: MapSet.new(), edges: MapSet.new()}

  @spec add_edge(t(), Lightning.Workflows.Edge.t()) :: t()
  def add_edge(graph, %{
        source_trigger_id: source_trigger_id,
        source_job_id: source_job_id,
        target_job_id: target_job_id
      }) do
    from = source_trigger_id || source_job_id
    to = target_job_id

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

  def traverse(%{edges: edges}, trigger_id) do
    edges
    |> Enum.reduce(Map.new(), fn {from, to}, dag_edges ->
      Map.update(dag_edges, from, [to], &[to | &1])
    end)
    |> then(fn dag_edges ->
      case Map.get(dag_edges, trigger_id) do
        [] ->
          :ok

        nil ->
          {:error, :no_target_for_trigger}

        [initial_job_id] ->
          traverse(initial_job_id, dag_edges, MapSet.new())

        _multiple ->
          {:error, :multiple_targets_for_trigger}
      end
    end)
  end

  defp traverse(node_id, dag_edges, visited_nodes) do
    cond do
      not Map.has_key?(dag_edges, node_id) ->
        :ok

      MapSet.member?(visited_nodes, node_id) ->
        {:error, :graph_has_a_cycle, node_id}

      :else ->
        visited_nodes = MapSet.put(visited_nodes, node_id)

        dag_edges
        |> Map.get(node_id)
        |> Enum.find_value(:ok, fn dest_node_id ->
          with :ok <- traverse(dest_node_id, dag_edges, visited_nodes), do: nil
        end)
    end
  end
end
