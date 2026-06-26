defmodule Lightning.ConnectedSystems.ConnectedSystem do
  @moduledoc """
  A Connected System is a named, instance-wide entry in the Connected Systems
  registry: an organization's catalog of the external systems it works with
  (a DHIS2 instance, a Postgres database, a national ID system, Gmail, ...).

  An entry carries a human-readable `name` (unique within the instance) and a
  URL-safe `slug` derived from it. The `slug` is the stable identifier used
  when a reference travels with project configuration across instances; the
  `name` may change without breaking those references.

  Everything else is optional metadata so an entry can exist in the registry
  before anyone has attached credentials, documentation, or access details.
  """
  use Lightning.Schema

  import Ecto.Changeset

  alias Lightning.Helpers

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          name: String.t() | nil,
          slug: String.t() | nil,
          type: String.t() | nil,
          description: String.t() | nil,
          docs_url: String.t() | nil,
          contact: String.t() | nil,
          access_instructions: String.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @castable_fields [
    :name,
    :type,
    :description,
    :docs_url,
    :contact,
    :access_instructions
  ]

  schema "connected_systems" do
    field :name, :string
    field :slug, :string
    field :type, :string
    field :description, :string
    field :docs_url, :string
    field :contact, :string
    field :access_instructions, :string

    field :raw_name, :string, virtual: true

    has_many :credentials, Lightning.Credentials.Credential

    timestamps()
  end

  @doc false
  def changeset(connected_system, attrs) do
    connected_system
    |> cast(attrs, @castable_fields)
    |> validate_required([:name])
    |> put_slug()
    |> validate()
  end

  @doc """
  Changeset used by the create/edit form, where the user types a free-form
  `raw_name`. The canonical `name` and `slug` are derived from it.
  """
  def form_changeset(connected_system, attrs) do
    connected_system
    |> cast(attrs, [:raw_name | @castable_fields])
    |> validate_required([:raw_name])
    |> then(fn changeset ->
      case get_change(changeset, :raw_name) do
        nil -> changeset
        raw_name -> put_change(changeset, :name, String.trim(raw_name))
      end
    end)
    |> put_slug()
    |> validate()
  end

  @doc """
  Shared validations. Exposed so the provisioner can validate references.
  """
  def validate(changeset) do
    changeset
    |> validate_required([:slug])
    |> validate_length(:description, max: 240)
    |> validate_format(:slug, ~r/^[a-z0-9]+([\-_.][a-z0-9]+)*$/,
      message: "must be URL safe"
    )
    |> unique_constraint(:name,
      name: :connected_systems_name_index,
      message: "a connected system with this name already exists"
    )
    |> unique_constraint(:slug,
      name: :connected_systems_slug_index,
      message: "a connected system with this name already exists"
    )
  end

  defp put_slug(changeset) do
    case get_field(changeset, :name) do
      nil -> changeset
      name -> put_change(changeset, :slug, Helpers.url_safe_name(name))
    end
  end
end
