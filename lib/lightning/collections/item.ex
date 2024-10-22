defmodule Lightning.Collections.Item do
  @moduledoc """
  A key value entry of a collection bound to a project.
  """
  use Lightning.Schema

  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: Ecto.UUID.t(),
          collection_id: Ecto.UUID.t(),
          key: String.t(),
          value: String.t(),
          inserted_at: NaiveDateTime.t(),
          updated_at: NaiveDateTime.t()
        }

  schema "collections_items" do
    field :key, :string
    field :value, :string

    belongs_to :collection, Lightning.Collections.Collection

    timestamps()
  end

  @doc false
  def changeset(entry, attrs) do
    entry
    |> cast(attrs, [:collection_id, :key, :value])
    |> validate_required([:collection_id, :key, :value])
    |> unique_constraint([:collection_id, :key])
    |> foreign_key_constraint(:collection_id)
  end
end
