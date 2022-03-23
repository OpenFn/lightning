defmodule Lightning.Invocation.Event do
  @moduledoc """
  Ecto model for Invocation Events.

  An event represents, that a trigger was invoked.
  By storing the data that arrived in a `Dataclip`, and pairing that with
  the corresponding Job we can maintain a detailed mapping of what happened
  in the lifetime of a Job or Dataclip.
  """
  use Ecto.Schema
  import Ecto.Changeset
  alias Lightning.Invocation.{Dataclip, Run}
  alias Lightning.Jobs.Job

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "invocation_events" do
    field :type, Ecto.Enum, values: [:webhook, :cron, :retry]
    belongs_to :dataclip, Dataclip
    belongs_to :job, Job
    has_one :run, Run

    timestamps(usec: true)
  end

  @doc false
  def changeset(event, attrs) do
    event
    |> cast(attrs, [:type, :dataclip_id, :job_id])
    |> validate_required([:type])
  end
end
