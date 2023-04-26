defmodule LightningWeb.WorkflowNewLive.WorkflowParams do
  @moduledoc """
  Various function for reconciling changes to a workflow params map.

  The front end editor uses JSON patches to represent changes to the workflow.
  """

  @doc """
  Produce a new set of params by applying the given patches to the current parms
  """
  def apply_patches(current_params, patches) do
    Jsonpatch.apply_patch(
      patches |> Enum.map(&Jsonpatch.Mapper.from_map/1),
      current_params
    )
  end

  @doc """
  Produce a set of patches that represent the difference between the initial
  params and the target params.

  This usually is used to produce a set of patches that represent the changes
  introduced by a changeset.
  """
  def to_patches(initial_params, target_params) do
    Jsonpatch.diff(initial_params, target_params)
    |> Jsonpatch.Mapper.to_map()
  end

  @doc """
  Convert a changeset to a serializable map of workflow params, suitable for
  sending to the front end editor.

  It uses `Lightning.Helpers.json_safe/1` to ensure that the map is safe to
  serialize to JSON. This is necessary because the underlying model may
  contain atom values.
  """
  def to_map(changeset), do: to_serializable(changeset)

  defp to_serializable(changeset) do
    %{
      jobs:
        changeset
        |> Ecto.Changeset.get_change(:jobs)
        |> to_serializable([:id, :name]),
      triggers:
        changeset
        |> Ecto.Changeset.get_change(:triggers)
        |> to_serializable([:id, :type]),
      edges:
        changeset
        |> Ecto.Changeset.get_change(:edges)
        |> to_serializable([
          :id,
          :source_trigger_id,
          :source_job_id,
          :condition,
          :target_job_id
        ])
    }
    |> Lightning.Helpers.json_safe()
  end

  defp to_serializable(changesets, fields) when is_list(changesets) do
    changesets
    |> Enum.map(fn changeset ->
      changeset
      |> Ecto.Changeset.apply_changes()
      |> Map.take(fields)
      |> Map.put(
        :errors,
        Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)
      )
    end)
  end
end
