defmodule Lightning.ImpactTracking.Configuration do
  @moduledoc """
  Persistence of Impact Tracker submission configuration

  """
  use Ecto.Schema

  @primary_key false
  schema "impact_tracking_configurations" do
    field :instance_id, Ecto.UUID, autogenerate: true

    timestamps()
  end
end
