defmodule Lightning.Invocation.LogLine do
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
          timestamp: integer(),
          run: Run.t() | Ecto.Association.NotLoaded.t() | nil
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "log_lines" do
    field :body, :string
    field :timestamp, :integer

    belongs_to :run, Run

    timestamps type: :utc_datetime_usec, updated_at: false
  end

  @doc false
  def changeset(run, attrs) do
    run
    |> cast(attrs, [:body, :timestamp, :run_id])
    |> assoc_constraint(:run)
  end
end
