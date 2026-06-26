defmodule Lightning.ConnectedSystems.ConnectedSystem do
  @moduledoc """
  A Connected System is a named entry in the organization-wide Connected Systems
  registry: a catalog of the external systems an organization works with (e.g. a
  DHIS2 instance, a Postgres database, a national ID system, Gmail).

  An entry carries no secrets. It records only:

    * a `name`, unique within the deployment, and
    * a `type`, which links to the relevant adaptor and its documentation.

  Credentials, documentation and access instructions can be organised around an
  entry, but the entry can exist in the registry before any of these are added,
  which is what makes the registry itself easy to set up and share.
  """

  use Lightning.Schema

  alias Lightning.Accounts.User
  alias Lightning.Credentials.Credential

  @type t :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: Ecto.UUID.t() | nil,
          name: String.t() | nil,
          type: String.t() | nil,
          created_by: User.t() | Ecto.Association.NotLoaded.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "connected_systems" do
    field :name, :string
    field :type, :string

    belongs_to :created_by, User

    has_many :credentials, Credential

    timestamps()
  end

  @doc false
  def changeset(connected_system, attrs) do
    connected_system
    |> cast(attrs, [:name, :type, :created_by_id])
    |> validate_required([:name, :type])
    |> validate_length(:name, min: 1, max: 255)
    |> validate_length(:type, min: 1, max: 255)
    |> validate_format(:name, ~r/^[a-zA-Z0-9_\-. ]*$/,
      message: "system name has invalid format"
    )
    |> unique_constraint(:name,
      message: "a connected system with this name already exists"
    )
    |> assoc_constraint(:created_by)
  end
end
