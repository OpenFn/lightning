defmodule Lightning.Workorders.SearchParams do
  use Ecto.Schema
  import Ecto.Changeset

  @moduledoc """
  This module is used to parse search parameters for workorders and provide
  a query to the database.
  """
  alias Lightning.Workorders.SearchParams

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
    field(:status, {:array, :string})
    field(:search_fields, {:array, :string})
    field(:search_term, :string)
    field(:workflow_id, :binary_id)
    field(:date_after, :utc_datetime)
    field(:date_before, :utc_datetime)
    field(:wo_date_after, :utc_datetime)
    field(:wo_date_before, :utc_datetime)
  end

  def new(params) do
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
    # |> apply_defaults()
    # |> validate_subset(:status, ~w[failure crash timeout])
    # |> validate_is_before_now([:wo_date_after])
    |> apply_action(:validate)
  end
end
