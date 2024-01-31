defmodule Lightning.ImpactTracking.Report do
  @moduledoc """
  Report submitted to ImpactTracker

  """
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "impact_tracking_reports" do
    field :data, :map
    field :submitted, :boolean
    field :submitted_at, :utc_datetime_usec

    timestamps()
  end
end
