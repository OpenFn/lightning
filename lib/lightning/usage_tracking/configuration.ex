defmodule Lightning.UsageTracking.Configuration do
  @moduledoc """
  Persistence of Usage Tracker submission configuration

  """
  use Ecto.Schema

  @primary_key false
  schema "usage_tracking_configurations" do
    field :instance_id, Ecto.UUID, autogenerate: true

    timestamps()
  end
end
