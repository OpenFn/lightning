defmodule Lightning.Invocation.Run do
  @moduledoc """
  Ecto model for Runs.

  A run represents the results of an Invocation.Event, where the Event
  stores what triggered the Run, the Run itself represents the execution.
  """

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          event: nil | %{job_id: Ecto.UUID.t()}
        }

  use Ecto.Schema
  import Ecto.Changeset
  alias Lightning.Invocation.{Event, Dataclip}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "runs" do
    field :exit_code, :integer
    field :finished_at, :utc_datetime_usec
    field :log, {:array, :string}
    field :started_at, :utc_datetime_usec
    belongs_to :event, Event
    has_one :dataclip, through: [:event, :dataclip]
    has_one :result_dataclip, Dataclip, where: [type: :run_result]

    timestamps(usec: true)
  end

  @doc false
  def changeset(run, attrs) do
    run
    |> cast(attrs, [:log, :exit_code, :started_at, :finished_at, :event_id])
    |> foreign_key_constraint(:event_id)
    |> validate_required([:event_id])
  end
end
