defmodule Lightning.Invocation.Run do
  @moduledoc """
  Ecto model for Runs.

  A run represents the results of an Invocation.Event, where the Event
  stores what triggered the Run, the Run itself represents the execution.
  """
  use Ecto.Schema
  import Ecto.Changeset
  alias Lightning.Invocation.{Event, Dataclip}
  alias Lightning.Projects.Project
  alias Lightning.Jobs.Job

  @type t :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: Ecto.UUID.t() | nil,
          event: Event.t() | Ecto.Association.NotLoaded.t() | nil,
          project: Project.t() | Ecto.Association.NotLoaded.t() | nil,
          job: Job.t() | Ecto.Association.NotLoaded.t() | nil
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "runs" do
    field :exit_code, :integer
    field :finished_at, :utc_datetime_usec
    field :log, {:array, :string}
    field :started_at, :utc_datetime_usec
    belongs_to :event, Event

    belongs_to :project, Project
    belongs_to :job, Job

    belongs_to :input_dataclip, Dataclip

    # has_one :source_dataclip, through: [:event, :dataclip]
    has_one :result_dataclip, through: [:event, :result_dataclip]

    timestamps(usec: true)
  end

  @doc false
  def changeset(run, attrs) do
    run
    |> cast(attrs, [
      :log,
      :exit_code,
      :started_at,
      :finished_at,
      :event_id,
      :project_id,
      :job_id,
      :input_dataclip_id
    ])
    |> foreign_key_constraint(:event_id)
    |> validate_required([:event_id, :project_id, :job_id, :input_dataclip_id])
  end
end
