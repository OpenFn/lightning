defmodule Lightning.Invocation.Event do
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
