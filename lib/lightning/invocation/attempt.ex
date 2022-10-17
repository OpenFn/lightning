defmodule Lightning.Attempt do
  @moduledoc """
  Ecto model for Attempts.


  """
  use Ecto.Schema
  import Ecto.Changeset
  alias Lightning.InvocationReason

  @type t :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: Ecto.UUID.t() | nil,
          reason: InvocationReason.t() | Ecto.Association.NotLoaded.t()
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "attempts" do
    belongs_to :reason, InvocationReason

    timestamps()
  end

  @doc false
  def changeset(attempt, attrs) do
    attempt
    |> cast(attrs, [:reason_id])
    |> validate_required([:reason_id])
    |> assoc_constraint(:reason)
  end
end
