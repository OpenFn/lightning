defmodule Lightning.UsageTracking.Report do
  @moduledoc """
  Report submitted to Usage Tracker

  """
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "usage_tracking_reports" do
    field :data, :map
    field :submitted, :boolean
    field :submitted_at, :utc_datetime_usec
    field :report_date, :date
    field :submission_status, Ecto.Enum, values: [:pending, :success, :failure]

    timestamps()
  end

  def changeset(report, params) do
    report
    |> cast(params, [:data, :report_date, :submitted, :submitted_at])
    |> validate_required([:data, :report_date, :submitted])
    |> unique_constraint(:report_date)
  end
end
