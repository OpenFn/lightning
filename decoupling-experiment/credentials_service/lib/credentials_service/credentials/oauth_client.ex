defmodule CredentialsService.Credentials.OauthClient do
  @moduledoc """
  OAuth client registration (provider endpoints + app credentials).

  Faithful finding preserved from the monolith: `client_secret` is **plaintext
  at rest** today (unlike `credential_bodies.body`). Extraction is the natural
  moment to encrypt it; the slice keeps it plaintext to document the gap rather
  than silently "fixing" it.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "oauth_clients" do
    field :name, :string
    field :client_id, :string
    field :client_secret, :string
    field :authorization_endpoint, :string
    field :token_endpoint, :string
    field :revocation_endpoint, :string
    field :user_id, :binary_id

    timestamps()
  end

  @doc false
  def changeset(oauth_client, attrs) do
    oauth_client
    |> cast(attrs, [
      :name,
      :client_id,
      :client_secret,
      :authorization_endpoint,
      :token_endpoint,
      :revocation_endpoint,
      :user_id
    ])
    |> validate_required([:name, :client_id, :client_secret])
  end
end
