defmodule Lightning.Adaptors.Repo.Adaptor do
  @moduledoc """
  Ecto schema for one row of the `adaptors` table — the per-package
  metadata projection used by the picker and Scheduler.

  Source-tagged via `:source` (`:npm | :local`) so the same package
  name can coexist across sources; the unique index is `[:name, :source]`
  (see §4.4 source-tagging invariant in
  `.context/lightning/adaptors/REWRITE-2026-05.md`).

  Mirrors `Lightning.Adaptors.Strategy.adaptor_record` minus `:versions`,
  which lives on `Lightning.Adaptors.Repo.AdaptorVersion`.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          name: String.t() | nil,
          source: :npm | :local | nil,
          description: String.t() | nil,
          homepage: String.t() | nil,
          repository: String.t() | nil,
          license: String.t() | nil,
          latest_version: String.t() | nil,
          deprecated: boolean(),
          schema_data: map() | nil,
          schema_sha256: String.t() | nil,
          icon_square_ext: String.t() | nil,
          icon_rectangle_ext: String.t() | nil,
          icon_square_sha256: binary() | nil,
          icon_rectangle_sha256: binary() | nil,
          checked_at: DateTime.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime_usec]

  schema "adaptors" do
    field :name, :string
    field :source, Ecto.Enum, values: [:npm, :local]
    field :description, :string
    field :homepage, :string
    field :repository, :string
    field :license, :string
    field :latest_version, :string
    field :deprecated, :boolean, default: false
    field :schema_data, :map
    field :schema_sha256, :string
    field :icon_square_ext, :string
    field :icon_rectangle_ext, :string
    field :icon_square_sha256, :binary
    field :icon_rectangle_sha256, :binary
    field :checked_at, :utc_datetime_usec

    timestamps()
  end

  @required ~w(name source latest_version checked_at)a
  @optional ~w(description homepage repository license deprecated
               schema_data schema_sha256
               icon_square_ext icon_rectangle_ext
               icon_square_sha256 icon_rectangle_sha256)a

  @doc """
  Build a changeset for upserting a single adaptor row.

  This is the single clause used by every write path on
  `Lightning.Adaptors.Repo` — there is no separate update path because
  the writer always rewrites the full row.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(struct, attrs) do
    struct
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required)
    |> validate_length(:name, max: 214)
    |> validate_inclusion(:icon_square_ext, ~w(png svg))
    |> validate_inclusion(:icon_rectangle_ext, ~w(png svg))
    |> validate_icon_sha256_pair(:icon_square)
    |> validate_icon_sha256_pair(:icon_rectangle)
    |> unique_constraint([:name, :source])
  end

  # Enforces the §6.4 invariant: a non-nil `icon_<shape>_ext` requires a
  # non-nil `icon_<shape>_sha256`, and vice versa. Either both fields
  # are set or both are nil — half-populated pairs fail the changeset.
  @spec validate_icon_sha256_pair(
          Ecto.Changeset.t(),
          :icon_square | :icon_rectangle
        ) :: Ecto.Changeset.t()
  defp validate_icon_sha256_pair(changeset, shape) do
    ext_field = :"#{shape}_ext"
    sha_field = :"#{shape}_sha256"

    case {get_field(changeset, ext_field), get_field(changeset, sha_field)} do
      {nil, nil} ->
        changeset

      {nil, _sha} ->
        add_error(
          changeset,
          sha_field,
          "must be nil when #{ext_field} is nil"
        )

      {_ext, nil} ->
        add_error(
          changeset,
          sha_field,
          "must not be nil when #{ext_field} is set"
        )

      {_ext, _sha} ->
        changeset
    end
  end
end
