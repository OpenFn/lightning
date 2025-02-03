defmodule Lightning.Collections.Item do
  @moduledoc """
  A key value entry of a collection bound to a project.
  """
  use Lightning.Schema

  import Ecto.Changeset

  @type t :: %__MODULE__{
          collection_id: Ecto.UUID.t(),
          key: String.t(),
          value: String.t(),
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  @primary_key false
  schema "collection_items" do
    field :id, :integer, primary_key: true
    # The collection belongs to the primary key for pagination purposes.
    # The next node on the BTREE belongs to the collection.
    belongs_to :collection, Lightning.Collections.Collection, primary_key: true

    # Note: The value type is a string because Lightning doesn't need to decode it to a map and
    #       encode it again to send to Postgres on every write. This is applicable also to all
    #       Collection read operations from Runtime worker or external API calls.
    #       Notice that the CPU + memory saved cost becomes meaningful once the JSON value
    #       max length is 1MB.
    field :key, :string
    field :value, :string

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(entry, attrs) do
    entry
    |> cast(attrs, [:collection_id, :key, :value])
    |> validate_required([:collection_id, :key, :value])
    |> validate_length(:value, max: 1_000_000)
    |> unique_constraint([:collection_id, :key])
    |> foreign_key_constraint(:collection_id)
  end

  defimpl Jason.Encoder, for: __MODULE__ do
    def encode(item, opts) do
      Jason.Encode.map(
        %{
          key: item.key,
          value: item.value,
          created: item.inserted_at,
          updated: item.updated_at
        },
        opts
      )
    end
  end
end
