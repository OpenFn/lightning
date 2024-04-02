defmodule Lightning.Credentials.OauthClient do
  @moduledoc """
  The OAuthClient model.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Lightning.Accounts.User
  alias Lightning.Credentials.Credential
  alias Lightning.Projects.ProjectOauthClient

  @type t :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: Ecto.UUID.t() | nil,
          name: String.t()
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "oauth_clients" do
    field :name, :string
    field :client_id, :string
    field :client_secret, :string
    field :base_url, :string

    belongs_to :user, User

    has_many :credentials, Credential
    has_many :project_oauth_clients, ProjectOauthClient
    has_many :projects, through: [:project_oauth_clients, :project]

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(oauth_client, attrs) do
    oauth_client
    |> cast(attrs, [
      :name,
      :client_id,
      :client_secret,
      :base_url,
      :user_id
    ])
    |> validate_required([:name, :client_id, :client_secret, :base_url])
    |> cast_assoc(:project_oauth_clients)
    |> assoc_constraint(:user)
  end
end
