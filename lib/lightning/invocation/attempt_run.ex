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

    timestamps(type: :utc_datetime_usec)
  end

  def new(attrs \\ %{}) do
    change(%__MODULE__{}, %{id: Ecto.UUID.generate()})
    |> changeset(attrs)
  end

  @doc false
  def changeset(attempt, attrs) do
    attempt
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
