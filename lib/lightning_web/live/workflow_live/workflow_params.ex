defmodule LightningWeb.WorkflowNewLive.WorkflowParams do
  @moduledoc """
  Various function for reconciling changes to a workflow params map.

  The front end editor uses JSON patches to represent changes to the workflow.
  """
  import LightningWeb.CoreComponents, only: [translate_errors: 1]

  @doc """
  Produce a new set of params by applying the given form params to the current
  params.
  """
  def apply_form_params(current_params, form_params) do
    Map.merge(current_params, form_params, fn _key, current, next ->
      case {current, next} do
        {current, next} when is_list(current) and is_map(next) ->
          merge_list_params(current, next)

        {current, next} when is_map(current) and is_map(next) ->
          Map.merge(current, next)

        _ ->
          next
      end
    end)
  end

  defp merge_list_params(source, new) when is_list(source) do
    new
    |> Enum.reduce(source, fn {index, val}, acc ->
      acc |> List.update_at(index |> key_as_int(), &Map.merge(&1, val))
    end)
  end

  defp key_as_int(key) when is_binary(key) do
    case Integer.parse(key) do
      {key, ""} -> key
      _ -> key
    end
  end

  @doc """
  Produce a new set of params by applying the given patches to the current parms
  """
  def apply_patches(current_params, patches) do
    Jsonpatch.apply_patch(
      patches,
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
  end

  @doc """
  Convert a changeset to a serializable map of workflow params, suitable for
  sending to the front end editor.

  It uses `Lightning.Helpers.json_safe/1` to ensure that the map is safe to
  serialize to JSON. This is necessary because the underlying model may
  contain atom values.
  """
  @spec to_map(Ecto.Changeset.t()) :: %{String.t() => any()}
  def to_map(%Ecto.Changeset{} = changeset) do
    changeset |> to_serializable(embed_or_assoc_getter(changeset))
  end

  defp embed_or_assoc_getter(%Ecto.Changeset{
         data: %Lightning.Workflows.Snapshot{}
       }),
       do: &Ecto.Changeset.get_embed/2

  defp embed_or_assoc_getter(%Ecto.Changeset{
         data: %Lightning.Workflows.Workflow{}
       }),
       do: &Ecto.Changeset.get_assoc/2

  defp to_serializable(%Ecto.Changeset{} = changeset, accessor)
       when is_function(accessor) do
    Map.merge(
      changeset
      |> to_serializable([
        :project_id,
        :name,
        :concurrency,
        :enable_job_logs,
        :positions
      ]),
      %{
        jobs:
          changeset
          |> accessor.(:jobs)
          |> Enum.reject(&match?(%{action: :replace}, &1))
          |> to_serializable([
            :id,
            :name,
            :adaptor,
            :body,
            :project_credential_id,
            :keychain_credential_id
          ]),
        triggers:
          changeset
          |> accessor.(:triggers)
          |> to_serializable([
            :id,
            :type,
            :cron_expression,
            :has_auth_method,
            :enabled
          ]),
        edges:
          changeset
          |> accessor.(:edges)
          |> Enum.reject(&match?(%{action: :replace}, &1))
          |> to_serializable([
            :id,
            :source_trigger_id,
            :source_job_id,
            :enabled,
            :condition_type,
            :condition_label,
            :condition_expression,
            :target_job_id
          ])
      }
    )
    |> Lightning.Helpers.json_safe()
  end

  defp to_serializable(changesets, fields)
       when is_list(changesets) and is_list(fields) do
    changesets |> Enum.map(&to_serializable(&1, fields))
  end

  defp to_serializable(%Ecto.Changeset{} = changeset, fields)
       when is_list(fields) do
    model = changeset |> Ecto.Changeset.apply_changes()

    required_fields = changeset.required |> Enum.map(&to_string/1)

    # validate_required drops changes when they invalid, we need to maintain
    # them so that our form doesn't forget the changes made by the user.
    fields_dropped_by_required =
      (changeset.params || %{})
      |> Map.filter(fn {skey, _val} ->
        skey in required_fields
      end)

    to_serializable(model, fields)
    |> Map.put(:errors, translate_errors(changeset))
    |> Map.merge(fields_dropped_by_required)
  end

  defp to_serializable(%{__struct__: model} = data, fields)
       when is_list(fields) do
    data
    |> Map.take(fields)
    |> Enum.map(fn {key, val} ->
      val = cast_value(model, key, val)

      {key, val}
    end)
    |> Enum.into(%{})
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
