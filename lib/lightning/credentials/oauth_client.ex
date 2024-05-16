defmodule Lightning.Credentials.OauthClient do
  @moduledoc """
  Defines the Ecto schema for an OAuth client. This schema is responsible for representing
  OAuth client data in the database, including details such as client ID, client secret,
  and endpoints necessary for OAuth operations. It also links to associated users and
  projects through relational fields.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Lightning.Accounts.User
  alias Lightning.Credentials.Credential
  alias Lightning.Projects.ProjectOauthClient
  alias Lightning.Validators

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
    field :authorization_endpoint, :string
    field :token_endpoint, :string
    field :userinfo_endpoint, :string
    field :introspection_endpoint, :string
    field :global, :boolean, default: false
    field :mandatory_scopes, :string
    field :optional_scopes, :string
    field :scopes_doc_url, :string

    belongs_to :user, User

    has_many :credentials, Credential
    has_many :project_oauth_clients, ProjectOauthClient
    has_many :projects, through: [:project_oauth_clients, :project]

    timestamps(type: :utc_datetime)
  end

  @doc """
  Builds a changeset for an OAuth client based on the provided attributes.

  ## Parameters
  - oauth_client: The existing `%OauthClient{}` struct (or a new struct for creation).
  - attrs: A map of attributes to set on the OAuth client.

  ## Returns
  - An `%Ecto.Changeset{}` that can be used to create or update an OAuth client.

  This function validates the presence of essential fields, ensures that URLs are valid,
  and handles associations with projects through nested changesets.
  """
  def changeset(oauth_client, attrs) do
    oauth_client
    |> cast(attrs, [
      :name,
      :client_id,
      :client_secret,
      :authorization_endpoint,
      :token_endpoint,
      :userinfo_endpoint,
      :introspection_endpoint,
      :global,
      :user_id,
      :mandatory_scopes,
      :optional_scopes,
      :scopes_doc_url
    ])
    |> validate_required([
      :name,
      :client_id,
      :client_secret,
      :authorization_endpoint,
      :token_endpoint
    ])
    |> Validators.validate_url(:authorization_endpoint)
    |> Validators.validate_url(:token_endpoint)
    |> Validators.validate_url(:userinfo_endpoint)
    |> Validators.validate_url(:introspection_endpoint)
    |> Validators.validate_url(:scopes_doc_url)
    |> cast_assoc(:project_oauth_clients,
      with: &ProjectOauthClient.changeset/2
    )
    |> assoc_constraint(:user)
  end
end
