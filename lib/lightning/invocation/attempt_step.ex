defmodule Lightning.AttemptStep do
  @moduledoc """
  Ecto model for an the Steps in an Attempt.
  """
  use Ecto.Schema
  import Ecto.Changeset
  alias Lightning.Attempt
  alias Lightning.Invocation.Step

  @type t :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: Ecto.UUID.t() | nil,
          attempt: Attempt.t() | Ecto.Association.NotLoaded.t(),
          step: Step.t() | Ecto.Association.NotLoaded.t()
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "attempt_steps" do
    belongs_to :attempt, Attempt
    belongs_to :step, Step

    timestamps type: :utc_datetime_usec, updated_at: false
  end

  def new(attrs \\ %{}) do
    change(%__MODULE__{id: Ecto.UUID.generate()}, attrs)
    |> validate()
  end

  @spec new(
          attempt :: Attempt.t() | Ecto.Changeset.t(Attempt.t()),
          step :: Step.t() | Ecto.Changeset.t(Step.t())
        ) :: Ecto.Changeset.t(__MODULE__.t())
  def new(attempt, step) do
    change(%__MODULE__{}, %{id: Ecto.UUID.generate()})
    |> put_assoc(:attempt, attempt)
    |> put_assoc(:step, step)
    |> validate()
  end

  @doc false
  def changeset(attempt_step, attrs) do
    attempt_step
    |> cast(attrs, [:attempt_id, :step_id])
    |> cast_assoc(:step, required: false)
    |> cast_assoc(:attempt, required: false)
    |> validate()
  end

  defp validate(changeset) do
    changeset
    |> assoc_constraint(:step)
    |> assoc_constraint(:attempt)
  end
end
