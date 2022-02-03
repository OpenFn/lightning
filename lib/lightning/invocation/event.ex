defmodule Lightning.Invocation.Event do
  use Ecto.Schema
  import Ecto.Changeset
  alias Lightning.Invocation.Dataclip

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "invocation_events" do
    field :type, Ecto.Enum, values: [:webhook, :cron, :retry]
    belongs_to :dataclip, Dataclip

    timestamps(usec: true)
  end

  @doc false
  def changeset(event, attrs) do
    event
    |> cast(attrs, [:type, :dataclip_id])
    |> validate_required([:type])
  end
end
