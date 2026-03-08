defmodule Lightning.AdaptorData.CacheEntry do
  @moduledoc """
  Schema for adaptor cache entries stored in the database.

  Each entry is identified by a `kind` (e.g., "registry", "schema", "icon")
  and a `key` (e.g., adaptor name or path). The `data` field holds the raw
  binary content and `content_type` describes its format.
  """
  use Lightning.Schema

  @type t :: %__MODULE__{
          id: Ecto.UUID.t(),
          kind: String.t(),
          key: String.t(),
          data: binary(),
          content_type: String.t(),
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  schema "adaptor_cache_entries" do
    field :kind, :string
    field :key, :string
    field :data, :binary
    field :content_type, :string, default: "application/json"

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(entry, attrs) do
    entry
    |> cast(attrs, [:kind, :key, :data, :content_type])
    |> validate_required([:kind, :key, :data])
    |> unique_constraint([:kind, :key])
  end
end
