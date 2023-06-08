defmodule LightningWeb.WorkflowNewLive.WorkflowParams do
  @moduledoc """
  Various function for reconciling changes to a workflow params map.

  The front end editor uses JSON patches to represent changes to the workflow.
  """

  @doc """
  Produce a new set of params by applying the given form params to the current
  params.
  """
  def apply_form_params(current_params, form_params) do
    Map.merge(current_params, form_params, fn _key, current, next ->
      case {current, next} do
        {current, next} when is_list(current) and is_map(next) ->
          merge_list_params(current, next)

        {current, next} when is_map(current) ->
          Map.merge(current, next)

        _ ->
          next
      end
    end)
  end

  defp merge_list_params(source, new) when is_list(source) do
    new
    |> Enum.map(&key_as_int/1)
    |> Enum.reduce(source, fn {index, val}, acc ->
      acc |> List.update_at(index, &Map.merge(&1, val))
    end)
  end

  defp key_as_int({key, val}) when is_binary(key) do
    case Integer.parse(key) do
      {key, ""} -> {key, val}
      _ -> {key, val}
    end
  end

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
    Map.merge(
      changeset |> to_serializable([:project_id, :name]),
      %{
        jobs:
          changeset
          |> Ecto.Changeset.get_change(:jobs)
          |> to_serializable([:id, :name, :adaptor, :body, :enabled]),
        triggers:
          changeset
          |> Ecto.Changeset.get_change(:triggers)
          |> to_serializable([:id, :type, :cron_expression]),
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
    )
    |> Lightning.Helpers.json_safe()
  end

  defp to_serializable(changesets, fields) when is_list(changesets) do
    changesets |> Enum.map(&to_serializable(&1, fields))
  end

  defp to_serializable(changeset, fields) do
    %{__struct__: model} =
      changeset
      |> Ecto.Changeset.apply_changes()

    changeset
    |> Ecto.Changeset.apply_changes()
    |> Map.take(fields)
    |> Enum.map(fn {key, val} ->
      val = cast_value(model, key, val)

      {key, val}
    end)
    |> Enum.into(%{})
    |> Map.put(
      :errors,
      Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)
      |> Map.take(fields)
    )
  end

  defp cast_value(model, field, value) do
    {model.__schema__(:type, field), value}
    |> case do
      {:string, nil} -> ""
      {:string, val} -> val
      {_, val} -> val
    end
  end
end
