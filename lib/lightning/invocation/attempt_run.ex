defmodule Lightning.AttemptRun do
  @moduledoc """
  Ecto model for an Attempts Runs.
  """
  use Ecto.Schema
  import Ecto.Changeset
  alias Lightning.Attempt
  alias Lightning.Invocation.Run

  @type t :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: Ecto.UUID.t() | nil,
          attempt: Attempt.t() | Ecto.Association.NotLoaded.t(),
          run: Run.t() | Ecto.Association.NotLoaded.t()
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "attempt_runs" do
    belongs_to :attempt, Attempt
    belongs_to :run, Run

    timestamps type: :utc_datetime_usec, updated_at: false
  end

  def new(attrs \\ %{}) do
    change(%__MODULE__{}, %{id: Ecto.UUID.generate()} |> Map.merge(attrs))
    |> validate()
  end

  # make a changeset,
  # then use the internal style function like put_change, put_assoc,
  # and validate it when you need

  # or

  # make a changeset with _cast_ and do your validation right then

  @spec new(
          attempt :: Attempt.t() | Ecto.Changeset.t(Attempt.t()),
          run :: Run.t() | Ecto.Changeset.t(Run.t())
        ) :: Ecto.Changeset.t(__MODULE__.t())
  def new(attempt, run) do
    change(%__MODULE__{}, %{id: Ecto.UUID.generate()})
    |> put_assoc(:attempt, attempt)
    |> put_assoc(:run, run)
    |> validate()
  end

  @doc false
  def changeset(attempt_run, attrs) do
    attempt_run
    |> cast(attrs, [:attempt_id, :run_id])
    |> cast_assoc(:run, required: false)
    |> cast_assoc(:attempt, required: false)
    |> validate()
  end

  defp validate(changeset) do
    changeset
    |> assoc_constraint(:run)
    |> assoc_constraint(:attempt)
  end
end
