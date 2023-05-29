defmodule Lightning.Invocation.RunLog do
  @moduledoc """
  Ecto model for run logs.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Lightning.Invocation.Run

  @type t :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: Ecto.UUID.t() | nil,
          body: String.t(),
          timestamp: Integer.t(),
          run: Run.t() | Ecto.Association.NotLoaded.t() | nil
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "run_logs" do
    field :body, :string
    field :timestamp, :integer

    belongs_to :run, Run

    timestamps type: :utc_datetime_usec
  end

  def new(attrs \\ %{}) do
    change(%__MODULE__{}, %{id: Ecto.UUID.generate()})
    |> change(attrs)
    |> assoc_constraint(:run)
  end

  @doc false
  def changeset(run, attrs) do
    run
    |> cast(attrs, [:body, :timestamp, :run_id])
    |> validate_required([:run_id])
    |> assoc_constraint(:run)
  end
end
