defmodule Lightning.Workflows.GraphRules do
  @moduledoc """
  Rules for a workflow's jobs, triggers and edges, on top of
  `Lightning.Workflows.Workflow.changeset/2`.

  - Every job and trigger the request sends carries its id, since edges name
    them by it.
  - A request that sends triggers removes none of the stored ones, and leaves
    at most one enabled.
  - Exactly one enabled edge leaves a trigger, and no trigger has two targets.
  - The edges form no cycle.

  Each broken rule is a coded error on the changeset, on the item at fault for a
  missing id or a cycle and on the list otherwise.
  """
  import Ecto.Changeset, only: [add_error: 4, get_field: 2, validate_required: 2]

  alias Ecto.Changeset
  alias Lightning.Workflows.Workflow

  @spec validate(Changeset.t(Workflow.t())) :: Changeset.t(Workflow.t())
  def validate(%Changeset{data: %Workflow{}} = changeset) do
    changeset
    |> update_sent(:jobs, &require_id/2)
    |> update_sent(:triggers, &require_id/2)
    |> validate_triggers()
    |> validate_trigger_edges()
    |> validate_no_cycle()
  end

  defp validate_triggers(%Changeset{changes: %{triggers: triggers}} = changeset) do
    enabled = changeset |> field_list(:triggers) |> Enum.count(& &1.enabled)

    changeset =
      if Enum.any?(triggers, &(&1.action == :replace)),
        do:
          add_error(
            changeset,
            :triggers,
            "a trigger cannot be removed, only edited or added",
            code: :trigger_removed
          ),
        else: changeset

    if enabled > 1,
      do:
        add_error(changeset, :triggers, "only one trigger may be enabled",
          code: :one_enabled
        ),
      else: changeset
  end

  defp validate_triggers(changeset), do: changeset

  defp validate_trigger_edges(changeset) do
    trigger_ids =
      changeset
      |> field_list(:triggers)
      |> Enum.map(& &1.id)
      |> Enum.reject(&is_nil/1)
      |> MapSet.new()

    from_triggers =
      changeset
      |> edges()
      |> Enum.filter(&MapSet.member?(trigger_ids, &1.from))

    many_targets? =
      from_triggers
      |> Enum.frequencies_by(& &1.from)
      |> Enum.any?(fn {_trigger_id, count} -> count > 1 end)

    # An edge that names a trigger as its source job counts toward the trigger's
    # targets but not toward its enabled edges.
    enabled_flags =
      for edge <- from_triggers, edge.source_trigger_id, do: edge.enabled

    changeset = refuse_trigger_edges(changeset, enabled_flags)

    if many_targets?,
      do:
        add_error(changeset, :edges, "a trigger must have a single target",
          code: :single_target
        ),
      else: changeset
  end

  # A lone edge from a trigger counts whatever its enabled flag says: saving
  # enables it (Edge.changeset/2).
  defp refuse_trigger_edges(changeset, [_one]), do: changeset

  defp refuse_trigger_edges(changeset, enabled_flags) do
    case Enum.count(enabled_flags, & &1) do
      0 ->
        add_error(changeset, :edges, "needs an enabled edge from a trigger",
          code: :missing_trigger_edge
        )

      1 ->
        changeset

      _more ->
        add_error(
          changeset,
          :edges,
          "only one edge from a trigger may be enabled",
          code: :one_enabled_edge
        )
    end
  end

  defp validate_no_cycle(changeset) do
    {sent, stored} =
      changeset
      |> edges()
      |> closing_edges()
      |> Enum.split_with(&is_integer(&1.index))

    sent_indexes = MapSet.new(sent, & &1.index)

    changeset =
      update_sent(changeset, :edges, fn edge, index ->
        if MapSet.member?(sent_indexes, index),
          do:
            add_error(edge, :target_job_id, "is part of a cycle", code: :cycle),
          else: edge
      end)

    # Only true when the request leaves the edges alone and the stored ones
    # already loop, so no edge of the request is at fault.
    if stored != [],
      do: add_error(changeset, :edges, "is part of a cycle", code: :cycle),
      else: changeset
  end

  # Depth-first from every node, in edge order: an edge that reaches a node
  # still on the walk's path closes a cycle. An edge from a job to itself is
  # Edge.changeset/2's to report.
  defp closing_edges(edges) do
    out =
      edges
      |> Enum.reject(&(&1.from == &1.to or is_nil(&1.from) or is_nil(&1.to)))
      |> Enum.group_by(& &1.from)

    {_states, closing} =
      edges
      |> Enum.map(& &1.from)
      |> Enum.uniq()
      |> Enum.reduce({%{}, []}, fn node, acc -> visit(node, out, acc) end)

    Enum.reverse(closing)
  end

  defp visit(node, out, {states, closing}) do
    if Map.has_key?(states, node) do
      {states, closing}
    else
      {states, closing} =
        out
        |> Map.get(node, [])
        |> Enum.reduce(
          {Map.put(states, node, :on_path), closing},
          &follow(&1, out, &2)
        )

      {Map.put(states, node, :done), closing}
    end
  end

  defp follow(edge, out, {states, closing}) do
    case Map.get(states, edge.to) do
      :on_path -> {states, [edge | closing]}
      :done -> {states, closing}
      nil -> visit(edge.to, out, {states, closing})
    end
  end

  # The workflow's edges once this change applies. `index` is an edge's position
  # among the changeset's edges, or nil for a stored edge the change didn't
  # touch.
  defp edges(%Changeset{changes: %{edges: edges}}) do
    edges
    |> Enum.with_index()
    |> Enum.reject(fn {edge, _index} -> edge.action == :replace end)
    |> Enum.map(fn {edge, index} ->
      edge(index, &get_field(edge, &1))
    end)
  end

  defp edges(%Changeset{data: %Workflow{edges: edges}}) when is_list(edges),
    do: Enum.map(edges, &edge(nil, fn field -> Map.fetch!(&1, field) end))

  defp edges(_changeset), do: []

  defp edge(index, field) do
    %{
      index: index,
      from: field.(:source_trigger_id) || field.(:source_job_id),
      to: field.(:target_job_id),
      source_trigger_id: field.(:source_trigger_id),
      enabled: field.(:enabled)
    }
  end

  defp require_id(child, _index), do: validate_required(child, :id)

  defp field_list(changeset, field) do
    case get_field(changeset, field) do
      list when is_list(list) -> list
      %Ecto.Association.NotLoaded{} -> []
    end
  end

  # Applies `fun` to each child the request sent, with its position in the
  # changeset's list, and marks the parent invalid when a child becomes so.
  defp update_sent(%Changeset{changes: changes} = changeset, field, fun) do
    case Map.fetch(changes, field) do
      {:ok, children} ->
        children =
          children
          |> Enum.with_index()
          |> Enum.map(fn
            {%Changeset{params: nil} = child, _index} -> child
            {%Changeset{action: :replace} = child, _index} -> child
            {child, index} -> fun.(child, index)
          end)

        %{
          changeset
          | changes: Map.put(changes, field, children),
            valid?: changeset.valid? and Enum.all?(children, & &1.valid?)
        }

      :error ->
        changeset
    end
  end
end
