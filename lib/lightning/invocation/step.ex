defmodule Lightning.Invocation.Step do
  @moduledoc """
  Ecto model for Steps.

  A step is part of a run and represents the work initiated for a single
  Job with a single `input_dataclip`.

  Once completed (successfully) it will have an `output_dataclip` associated
  with it as well.

  When a step finishes, it's `:exit_reason` is set to one of following strings:

  -  `"success"`
  -  `"fail"`
  -  `"crash"`
  -  `"cancel"`
  -  `"kill"`
  -  `"exception"`
  -  `"lost"`
  """
  use Lightning.Schema

  alias Lightning.Credentials.Credential
  alias Lightning.Invocation.Dataclip
  alias Lightning.Invocation.LogLine
  alias Lightning.Run
  alias Lightning.RunStep
  alias Lightning.Workflows.Job
  alias Lightning.Workflows.Snapshot

  @type t :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: Ecto.UUID.t() | nil,
          exit_reason: String.t() | nil,
          job: Job.t() | Ecto.Association.NotLoaded.t() | nil
        }

  schema "steps" do
    field :exit_reason, :string
    field :error_type, :string
    # TODO: add now, later, or never?
    # field :error_message, :string
    field :finished_at, :utc_datetime_usec
    field :started_at, :utc_datetime_usec
    belongs_to :job, Job
    belongs_to :snapshot, Snapshot
    belongs_to :credential, Credential

    belongs_to :input_dataclip, Dataclip
    belongs_to :output_dataclip, Dataclip

    has_many :log_lines, LogLine, preload_order: [asc: :timestamp]

    many_to_many :runs, Run, join_through: RunStep

    timestamps(type: :utc_datetime_usec)
  end

  def new(attrs \\ %{}) do
    change(%__MODULE__{id: Ecto.UUID.generate()}, %{})
    |> change(attrs)
    |> validate()
  end

  def finished(step, params) do
    step
    |> cast(params, [
      :output_dataclip_id,
      :exit_reason,
      :error_type,
      :finished_at
    ])
    |> validate_required([:finished_at, :exit_reason])
  end

  @doc false
  def changeset(step, attrs) do
    step
    |> cast(attrs, [
      :id,
      :exit_reason,
      :error_type,
      :started_at,
      :finished_at,
      :job_id,
      :credential_id,
      :input_dataclip_id,
      :output_dataclip_id
    ])
    |> cast_assoc(:output_dataclip, with: &Dataclip.changeset/2, required: false)
    |> validate_required([:job_id, :input_dataclip_id, :snapshot_id])
    |> validate()
  end

  def validate(changeset) do
    changeset
    |> assoc_constraint(:input_dataclip)
    |> assoc_constraint(:output_dataclip)
    |> assoc_constraint(:job)
    |> assoc_constraint(:snapshot)
  end
end
