defmodule Lightning.Invocation.Run do
  @moduledoc """
  Ecto model for Runs.

  A run represents the work initiated for a Job with an input dataclip.
  Once completed (successfully) it will have an `output_dataclip` associated
  with it as well.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Lightning.Invocation.Dataclip
  alias Lightning.Jobs.Job
  alias Lightning.Credentials.Credential
  alias Lightning.{AttemptRun, Attempt}
  alias Lightning.Invocation.LogLine

  @type t :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: Ecto.UUID.t() | nil,
          job: Job.t() | Ecto.Association.NotLoaded.t() | nil
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "runs" do
    field :exit_code, :integer
    field :finished_at, :utc_datetime_usec
    field :started_at, :utc_datetime_usec
    belongs_to :job, Job
    belongs_to :credential, Credential

    belongs_to :input_dataclip, Dataclip
    belongs_to :output_dataclip, Dataclip

    belongs_to :previous, __MODULE__

    has_many :log_lines, LogLine

    many_to_many :attempts, Attempt, join_through: AttemptRun

    timestamps(type: :utc_datetime_usec)
  end

  def new(attrs \\ %{}) do
    change(%__MODULE__{}, %{id: Ecto.UUID.generate()})
    |> change(attrs)
    |> validate()
  end

  @doc """
  Creates a new Run changeset, but copies over certain fields.
  This is used to create new runs for retrys.
  """
  @spec new_from(run :: __MODULE__.t()) :: Ecto.Changeset.t(__MODULE__.t())
  def new_from(%__MODULE__{} = run) do
    attrs =
      [:job_id, :input_dataclip_id, :previous_id]
      |> Enum.reduce(%{}, fn key, acc ->
        Map.put(acc, key, Map.get(run, key))
      end)

    new(attrs)
  end

  @doc false
  def changeset(run, attrs) do
    run
    |> cast(attrs, [
      :exit_code,
      :started_at,
      :finished_at,
      :job_id,
      :credential_id,
      :input_dataclip_id,
      :output_dataclip_id
    ])
    |> cast_assoc(:output_dataclip, with: &Dataclip.changeset/2, required: false)
    |> cast_assoc(:log_lines, with: &LogLine.changeset/2, required: false)
    |> validate_required([:job_id, :input_dataclip_id])
    |> validate()
  end

  defp validate(changeset) do
    changeset
    |> assoc_constraint(:input_dataclip)
    |> assoc_constraint(:output_dataclip)
    |> assoc_constraint(:job)
  end
end
