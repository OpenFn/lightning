defmodule Lightning.Organizations.Organization do
  @moduledoc """
  The institution above a set of projects. Every project belongs to one, and a
  person can belong to many, through `Lightning.Organizations.OrganizationUser`.
  Belonging to one gives no access to its projects.

  `role` is virtual: the role of whoever the organization was loaded for,
  `:admin` or `:member`, or nil when they aren't in it.
  """
  use Lightning.Schema

  alias Lightning.Organizations.OrganizationUser

  @type t :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: Ecto.UUID.t() | nil,
          name: String.t() | nil,
          role: OrganizationUser.role() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "organizations" do
    field :name, :string
    field :role, Ecto.Enum, values: OrganizationUser.roles(), virtual: true

    has_many :organization_users, OrganizationUser

    timestamps()
  end

  @doc false
  def changeset(organization, attrs) do
    organization
    |> cast(attrs, [:name])
    |> update_change(:name, &(&1 && String.trim(&1)))
    |> validate_required([:name])
    |> validate_length(:name, max: 160)
  end
end
