defmodule Lightning.Workorders.SearchParams do
  @moduledoc """
  This module is used to parse search parameters for workorders and provide
  a query to the database.
  """

  # What should be defaults

  use Ecto.Schema
  import Ecto.Changeset

  alias Lightning.Workorders.SearchParams

  @statuses ~w(success failure pending timeout crash)
  @search_fields ~w(body log)

  @type t :: %SearchParams{
          status: [String.t()],
          search_fields: [String.t()],
          search_term: String.t(),
          workflow_id: Ecto.UUID.t(),
          date_after: DateTime.t(),
          date_before: DateTime.t(),
          wo_date_after: DateTime.t(),
          wo_date_before: DateTime.t()
        }

  @primary_key false
  embedded_schema do
    field(:status, {:array, :string}, default: @statuses)
    field(:search_fields, {:array, :string}, default: @search_fields)
    field(:search_term, :string)
    field(:workflow_id, :binary_id)
    field(:date_after, :utc_datetime_usec)
    field(:date_before, :utc_datetime_usec)
    field(:wo_date_after, :utc_datetime_usec)
    field(:wo_date_before, :utc_datetime_usec)
  end

  def new(params) do
    params = from_uri(params)

    Ecto.Changeset.cast(%__MODULE__{}, params, [
      :status,
      :search_fields,
      :search_term,
      :workflow_id,
      :date_after,
      :date_before,
      :wo_date_after,
      :wo_date_before
    ])
    |> validate_subset(:status, @statuses)
    |> validate_subset(:search_fields, @search_fields)
    |> apply_action!(:validate)
    |> Map.update!(:status, fn statuses ->
      Enum.map(statuses, fn status -> String.to_existing_atom(status) end)
    end)
    |> Map.update!(:search_fields, fn search_fields ->
      Enum.map(search_fields, fn search_field ->
        String.to_existing_atom(search_field)
      end)
    end)
  end

  defp from_uri(params) do
    statuses =
      Enum.map(params, fn {key, value} ->
        if key in @statuses and value in [true, "true"] do
          key
        end
      end)
      |> Enum.filter(fn v -> v end)

    search_fields =
      Enum.map(params, fn {key, value} ->
        if key in @search_fields and value in [true, "true"] do
          key
        end
      end)
      |> Enum.filter(fn v -> v end)

    params
    |> Map.put_new("status", statuses)
    |> Map.put_new("search_fields", search_fields)
  end

  def to_uri_params(search_params) do
    search_params
    |> merge_fields(@statuses)
    |> merge_fields(@search_fields)
    |> dates_to_string()
  end

  defp merge_fields(search_params, defaults) do
    (defaults -- Map.keys(search_params))
    |> Enum.map(fn x -> {x, true} end)
    |> Enum.into(%{})
    |> Map.merge(search_params)
  end

  defp dates_to_string(search_params) do
    ~w(date_after date_before wo_date_after wo_date_before)a
    |> Enum.map(fn key ->
      key = Atom.to_string(key)
      value = Map.get(search_params, key)

      if value do
        {key, DateTime.to_string(value)}
      else
        {key, value}
      end
    end)
    |> Enum.into(%{})
    |> Map.merge(search_params, fn _key, v1, _v2 -> v1 end)
  end
end
