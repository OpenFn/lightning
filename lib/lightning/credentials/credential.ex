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
    belongs_to :user, User
    has_many :project_credentials, ProjectCredential
    has_many :projects, through: [:project_credentials, :project]

    timestamps()
  end

  @doc false
  def changeset(credential, attrs) do
    credential
    |> cast(attrs, [:name, :body, :production, :user_id])
    |> cast_assoc(:project_credentials)
    |> validate_required([:name, :body, :user_id])
    |> assoc_constraint(:user)
  end

  def validate_transfer_ownership(changeset, field, options \\ []) do
    validate_change(changeset, field, fn _, user ->

      case String.starts_with?(url, @our_url) do
        true -> []
        false -> [{field, options[:message] || "Unexpected URL"}]
      end
    end)
  end
end
