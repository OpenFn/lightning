defmodule Lightning.Invocation.Run do
  use Ecto.Schema
  import Ecto.Changeset
  alias Lightning.Invocation.Event

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "runs" do
    field :exit_code, :integer
    field :finished_at, :utc_datetime_usec
    field :log, {:array, :string}
    field :started_at, :utc_datetime_usec
    belongs_to :event, Event

    timestamps(usec: true)
  end

  @doc false
  def changeset(run, attrs) do
    run
    |> cast(attrs, [:log, :exit_code, :started_at, :finished_at, :event_id])
    |> foreign_key_constraint(:event_id)
    |> validate_required([:log, :exit_code, :started_at, :finished_at, :event_id])
  end
end
