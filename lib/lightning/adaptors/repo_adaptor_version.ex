defmodule Lightning.Adaptors.Repo.AdaptorVersion do
  @moduledoc """
  Ecto schema for one row of the `adaptor_versions` table — per-version
  metadata for an adaptor package (`integrity`, `tarball_url`,
  `size_bytes`, `dependencies`, `peer_dependencies`, `published_at`,
  `deprecated`).

  Belongs to `Lightning.Adaptors.Repo.Adaptor` and cascade-deletes with
  its parent. Mirrors `Lightning.Adaptors.Strategy.version_record` (see
  §6.1 and §6.4 in `.context/lightning/adaptors/REWRITE-2026-05.md`).
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Lightning.Adaptors.Repo.Adaptor

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          adaptor_id: Ecto.UUID.t() | nil,
          adaptor: Adaptor.t() | Ecto.Association.NotLoaded.t() | nil,
          version: String.t() | nil,
          integrity: String.t() | nil,
          tarball_url: String.t() | nil,
          size_bytes: integer() | nil,
          dependencies: map() | nil,
          peer_dependencies: map() | nil,
          published_at: DateTime.t() | nil,
          deprecated: boolean(),
          inserted_at: DateTime.t() | nil
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime_usec]

  schema "adaptor_versions" do
    field :version, :string
    field :integrity, :string
    field :tarball_url, :string
    field :size_bytes, :integer
    field :dependencies, :map
    field :peer_dependencies, :map
    field :published_at, :utc_datetime_usec
    field :deprecated, :boolean, default: false

    belongs_to :adaptor, Adaptor

    timestamps(updated_at: false)
  end

  @required ~w(adaptor_id version)a
  @optional ~w(integrity tarball_url size_bytes
               dependencies peer_dependencies
               published_at deprecated)a

  @doc """
  Build a changeset for inserting an `adaptor_versions` row.

  `Lightning.Adaptors.Repo.upsert_adaptor/1` replaces version rows with
  a delete-then-insert inside a transaction, so there is no separate
  update path.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(struct, attrs) do
    struct
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required)
    |> unique_constraint([:adaptor_id, :version])
    |> assoc_constraint(:adaptor)
  end
end
