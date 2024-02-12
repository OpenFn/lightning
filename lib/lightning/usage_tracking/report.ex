defmodule Lightning.UsageTracking.Report do
  @moduledoc """
  Report submitted to Usage Tracker

  """
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "usage_tracking_reports" do
    field :data, :map
    field :submitted, :boolean
    field :submitted_at, :utc_datetime_usec

    timestamps()
  end
end
