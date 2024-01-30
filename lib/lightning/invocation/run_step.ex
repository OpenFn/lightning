defmodule Lightning.RunStep do
  @moduledoc """
  Ecto model for an the Steps in a Run.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Lightning.Invocation.Step
  alias Lightning.Run

  @type t :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: Ecto.UUID.t() | nil,
          run: Run.t() | Ecto.Association.NotLoaded.t(),
          step: Step.t() | Ecto.Association.NotLoaded.t()
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "run_steps" do
    belongs_to :run, Run
    belongs_to :step, Step

    timestamps type: :utc_datetime_usec, updated_at: false
  end

  def new(attrs \\ %{}) do
    change(%__MODULE__{id: Ecto.UUID.generate()}, attrs)
    |> validate()
  end

  @spec new(
          run :: Run.t() | Ecto.Changeset.t(Run.t()),
          step :: Step.t() | Ecto.Changeset.t(Step.t())
        ) :: Ecto.Changeset.t(__MODULE__.t())
  def new(run, step) do
    change(%__MODULE__{}, %{id: Ecto.UUID.generate()})
    |> put_assoc(:run, run)
    |> put_assoc(:step, step)
    |> validate()
  end

  @doc false
  def changeset(run_step, attrs) do
    run_step
    |> cast(attrs, [:run_id, :step_id])
    |> cast_assoc(:step, required: false)
    |> cast_assoc(:run, required: false)
    |> validate()
  end

  defp validate(changeset) do
    changeset
    |> assoc_constraint(:step)
    |> assoc_constraint(:run)
  end
end
