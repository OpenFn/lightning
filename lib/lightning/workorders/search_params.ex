defmodule Lightning.WorkOrders.SearchParams do
  @moduledoc """
  This module is used to parse search parameters for work orders and provide
  a query to the database.
  """

  use Lightning.Schema

  @fields [
    :status,
    :search_fields,
    :search_term,
    :workflow_id,
    :workorder_id,
    :date_after,
    :date_before,
    :wo_date_after,
    :wo_date_before,
    :sort_by,
    :sort_direction
  ]

  @derive {Jason.Encoder, only: @fields}
  # Also implement the built-in JSON.Encoder: the history-export path serialises
  # this struct (audit metadata and the Oban job args) through it, and without
  # this every export raised instead of running.
  @derive {JSON.Encoder, only: @fields}

  @status_values Lightning.WorkOrder.states()
  @search_field_values [:id, :body, :log, :dataclip_name]

  # String forms for the URI/flag params new/1 receives from the UI.
  @statuses Enum.map(@status_values, &Atom.to_string/1)
  @search_fields Enum.map(@search_field_values, &Atom.to_string/1)
  @statuses_set MapSet.new(@status_values)

  defmacro status_list do
    quote do
      unquote(@statuses)
    end
  end

  @type t :: %__MODULE__{
          status: [atom()],
          search_fields: [atom()],
          search_term: String.t(),
          workflow_id: Ecto.UUID.t(),
          workorder_id: Ecto.UUID.t(),
          date_after: DateTime.t(),
          date_before: DateTime.t(),
          wo_date_after: DateTime.t(),
          wo_date_before: DateTime.t(),
          sort_by: String.t(),
          sort_direction: String.t()
        }

  @primary_key false
  embedded_schema do
    field(:status, {:array, Ecto.Enum}, values: @status_values, default: [])

    field(:search_fields, {:array, Ecto.Enum},
      values: @search_field_values,
      default: @search_field_values
    )

    field(:search_term, :string)
    field(:workflow_id, :binary_id)
    field(:workorder_id, :binary_id)
    field(:date_after, :utc_datetime_usec)
    field(:date_before, :utc_datetime_usec)
    field(:wo_date_after, :utc_datetime_usec)
    field(:wo_date_before, :utc_datetime_usec)
    field(:sort_by, :string)
    field(:sort_direction, :string)
  end

  # Raises on invalid input. A malformed filter is only reachable by hand-editing
  # the query string, and failing loud (500) is safer here than silently
  # dropping the bad filter, which would widen the results/export. from_map/1
  # handles the untrusted serialized args for the worker, and fails closed.
  def new(params) do
    params
    |> from_uri()
    |> changeset()
    |> apply_action!(:validate)
  end

  defp changeset(params) do
    %__MODULE__{}
    |> cast(params, @fields)
    |> validate_inclusion(:sort_by, ["inserted_at", "last_activity"],
      allow_nil: true
    )
    |> validate_inclusion(:sort_direction, ["asc", "desc"], allow_nil: true)
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

  # Oban args (JSON): rebuilds the struct new/1 validated before enqueue. Runs
  # in the export worker, so it returns {:error, _} rather than raising on a
  # stale or malformed arg, letting the worker fail the export cleanly instead
  # of crashing or exporting the wrong rows.
  def from_map(map) when is_map(map) do
    map
    |> changeset()
    |> apply_action(:validate)
  end

  def from_map(_), do: {:error, :invalid_search_params}
end
