defmodule Lightning.Collections.Item do
  @moduledoc """
  A key value entry of a collection bound to a project.
  """
  use Lightning.Schema

  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: Ecto.UUID.t(),
          collection_name: String.t(),
          key: String.t(),
          value: String.t(),
          inserted_at: NaiveDateTime.t(),
          updated_at: NaiveDateTime.t()
        }

  schema "collections_items" do
    belongs_to :collection, Lightning.Collections.Collection,
      foreign_key: :collection_name,
      references: :name,
      type: :string

    field :value, :string
    field :key, :string

    timestamps()
  end

  @doc false
  def changeset(entry, attrs) do
    entry
    |> cast(attrs, [:collection_name, :key, :value])
    |> validate_required([:collection_name, :key, :value])
    |> unique_constraint([:collection_name, :key])
    |> foreign_key_constraint(:collection_name)
  end
end
