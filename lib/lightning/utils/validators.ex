defmodule Lightning.Validators do
  @moduledoc """
  Extra validators for Ecto.Changeset.
  """

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
    |> then(fn f ->
      if length(f) > 1 do
        error_field =
          fields
          |> Enum.map(&[&1, fetch_field(changeset, &1)])
          |> Enum.find(fn [_, {kind, _}] -> kind == :changes end)
          |> List.first()

        add_error(changeset, error_field, message)
      else
        changeset
      end
    end)
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

      _any ->
        changeset
    end
  end

  @doc """
  Validate that an association is present

  > **NOTE**
  > This should only be used when using `put_assoc`, not `cast_assoc`.
  > `cast_assoc` provides a `required: true` option.
  > Unlike `validate_required`, this does not add the field to the `required`
  > list in the schema.
  """
  @spec validate_required_assoc(Ecto.Changeset.t(), atom(), String.t()) ::
          Ecto.Changeset.t()
  def validate_required_assoc(changeset, assoc, message \\ "is required") do
    changeset
    |> get_field(assoc)
    |> case do
      nil ->
        add_error(changeset, assoc, message)

      _any ->
        changeset
    end
  end

  @doc """
  Validate that a field is a valid URL.
  """
  @spec validate_url(Ecto.Changeset.t(), atom()) :: Ecto.Changeset.t()
  def validate_url(changeset, field) do
    validate_change(changeset, field, fn _, value ->
      with url when is_binary(url) <- value,
           true <-
             Regex.match?(
               ~r/^(https?:\/\/)?([\da-z\.-]+)\.([a-z\.]{2,6})([\/\w \.-]*)*\/?$/i,
               url
             ) do
        []
      else
        _ -> [{field, "must be a valid URL"}]
      end
    end)
  end
end
