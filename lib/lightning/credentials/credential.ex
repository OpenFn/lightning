defmodule Lightning.Credentials.Credential do
  @moduledoc """
  The Credential model.
  """
  @type t :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: Ecto.UUID.t() | nil,
          body: nil | %{}
        }

  use Ecto.Schema
  alias Lightning.Accounts.User
  alias Lightning.Projects.ProjectCredential
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "credentials" do
    field :name, :string

    field :body, Lightning.Encrypted.Map
    field :production, :boolean, default: false
    field :schema, :string
    belongs_to :user, User
    has_many :project_credentials, ProjectCredential
    has_many :projects, through: [:project_credentials, :project]

    timestamps()
  end

  @doc false
  def changeset(credential, attrs) do
    credential
    |> cast(attrs, [:name, :body, :production, :user_id, :schema])
    |> cast_assoc(:project_credentials)
    |> validate_required([:name, :body, :user_id, :schema])
    |> assoc_constraint(:user)
  end
end
