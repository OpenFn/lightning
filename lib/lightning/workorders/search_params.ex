defmodule Lightning.WorkOrders.SearchParams do
  @moduledoc """
  This module is used to parse search parameters for work orders and provide
  a query to the database.
  """

  # What should be defaults

  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(pending running success failed crashed killed cancelled lost exception)
  @statuses_set MapSet.new(@statuses, fn x -> String.to_existing_atom(x) end)
  @search_fields ~w(id body log)

  defmacro status_list do
    quote do
      unquote(@statuses)
    end
  end

  @type t :: %__MODULE__{
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
    field(:status, {:array, :string})
    field(:search_fields, {:array, :string}, default: @search_fields)
    field(:search_term, :string)
    field(:workflow_id, :binary_id)
    field(:workorder_id, :binary_id)
    field(:date_after, :utc_datetime_usec)
    field(:date_before, :utc_datetime_usec)
    field(:wo_date_after, :utc_datetime_usec)
    field(:wo_date_before, :utc_datetime_usec)
  end

  def new(params) do
    params = from_uri(params)

    %__MODULE__{}
    |> cast(params, [
      :status,
      :search_fields,
      :search_term,
      :workflow_id,
      :workorder_id,
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

  def all_statuses_set?(%{status: status_list}) do
    MapSet.equal?(@statuses_set, MapSet.new(status_list))
  end

  defp from_uri(params) do
    statuses =
      Enum.map(params, fn {key, value} ->
        if key in @statuses and value in [true, "true"] do
          key
        end
      end)
      |> Enum.reject(&is_nil/1)

    search_fields =
      Enum.map(params, fn {key, value} ->
        if key in @search_fields and value in [true, "true"] do
          key
        end
      end)
      |> Enum.reject(&is_nil/1)

    params
    |> Map.put_new("status", statuses)
    |> Map.put_new("search_fields", search_fields)
  end

  def to_uri_params(search_params) do
    search_params
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
