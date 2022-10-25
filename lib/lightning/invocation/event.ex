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
  alias Lightning.Projects.Project

  @type t :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: Ecto.UUID.t() | nil,
          type: atom(),
          dataclip: Dataclip.t() | Ecto.Association.NotLoaded.t() | nil,
          job: Job.t() | Ecto.Association.NotLoaded.t() | nil
        }

  @source_types [:webhook, :cron, :retry, :flow]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "invocation_events" do
    field :type, Ecto.Enum, values: @source_types
    belongs_to :source, __MODULE__
    belongs_to :dataclip, Dataclip

    has_one :result_dataclip, Dataclip,
      where: [type: :run_result],
      foreign_key: :source_event_id

    belongs_to :job, Job
    belongs_to :project, Project

    timestamps(usec: true)
  end

  @doc false
  def changeset(event, attrs) do
    event
    |> cast(attrs, [:type, :dataclip_id, :job_id, :source_id, :project_id])
    |> validate_required([:type, :job_id, :project_id])
    |> validate_inclusion(:type, @source_types)
    |> assoc_constraint(:job)
    |> assoc_constraint(:project)
    |> validate_by_type()
  end

  @doc """
  Append validations based on the type of the Event.

  - `:flow` must have an associated Event source model.
  """
  def validate_by_type(changeset) do
    changeset
    |> fetch_field!(:type)
    |> case do
      :flow ->
        changeset
        |> assoc_constraint(:source)

      _ ->
        changeset
    end
  end
end
