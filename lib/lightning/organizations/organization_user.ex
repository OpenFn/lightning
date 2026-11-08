defmodule Lightning.Organizations.OrganizationUser do
  @moduledoc """
  A person's membership of an organization, with their role in it: `:admin`,
  who manages the organization and its members, or `:member`, who reads them.
  """
  use Lightning.Schema

  alias Lightning.Accounts.User
  alias Lightning.Organizations.Organization

  @roles [:admin, :member]

  @type role :: :admin | :member

  @type t :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: Ecto.UUID.t() | nil,
          role: role() | nil,
          organization_id: Ecto.UUID.t() | nil,
          user_id: Ecto.UUID.t() | nil,
          organization: Organization.t() | Ecto.Association.NotLoaded.t() | nil,
          user: User.t() | Ecto.Association.NotLoaded.t() | nil
        }

  schema "organization_users" do
    field :role, Ecto.Enum, values: @roles

    belongs_to :organization, Organization
    belongs_to :user, User

    timestamps()
  end

  @spec roles() :: [role()]
  def roles, do: @roles

  @doc false
  def changeset(organization_user, attrs) do
    organization_user
    |> cast(attrs, [:role, :user_id])
    |> validate_required([:role, :user_id])
    |> unique_constraint([:organization_id, :user_id],
      message: "is already a member of the organization"
    )
  end
end
