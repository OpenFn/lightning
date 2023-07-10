defmodule Lightning.Validators do
  import Ecto.Changeset

  @doc """
  Validate that only one of the fields is set at a time.

  Example:

  ```
  changeset
  |> validate_exclusive(
    [:source_job_id, :source_trigger_id],
    "source_job_id and source_trigger_id are mutually exclusive"
  )
  ```
  """
  @spec validate_exclusive(Ecto.Changeset.t(), [atom()], String.t()) ::
          Ecto.Changeset.t()
  def validate_exclusive(changeset, fields, message) do
    fields
    |> Enum.map(&get_field(changeset, &1))
    |> Enum.reject(&is_nil/1)
    |> case do
      f when length(f) > 1 ->
        error_field =
          fields
          |> Enum.map(&[&1, fetch_field(changeset, &1)])
          |> Enum.find(fn [_, {kind, _}] -> kind == :changes end)
          |> List.first()

        add_error(changeset, error_field, message)

      _ ->
        changeset
    end
  end

  @doc """
  Validate that at least one of the fields is set.
  """
  @spec validate_one_required(Ecto.Changeset.t(), [atom()], String.t()) ::
          Ecto.Changeset.t()
  def validate_one_required(changeset, fields, message) do
    fields
    |> Enum.map(&get_field(changeset, &1))
    |> Enum.reject(&is_nil/1)
    |> case do
      [] ->
        add_error(changeset, fields |> List.first(), message)

      _ ->
        changeset
    end
  end
end
