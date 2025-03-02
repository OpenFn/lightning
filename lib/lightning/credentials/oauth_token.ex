defmodule Lightning.Credentials.OauthToken do
  @moduledoc """
  Schema and functions for managing OAuth tokens. This module handles the storage and
  validation of OAuth tokens, allowing multiple credentials to share the same token
  when they have identical scope sets.
  """
  use Lightning.Schema
  import Ecto.Query

  alias Lightning.Accounts.User
  alias Lightning.Credentials
  alias Lightning.Credentials.Credential
  alias Lightning.Credentials.OauthClient

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          body: map(),
          scopes: [String.t()],
          oauth_client_id: Ecto.UUID.t() | nil,
          oauth_client: OauthClient.t() | nil,
          user_id: Ecto.UUID.t() | nil,
          user: User.t() | nil,
          credentials: [Credential.t()] | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "oauth_tokens" do
    field :body, Lightning.Encrypted.Map, redact: true
    field :scopes, {:array, :string}

    belongs_to :oauth_client, OauthClient
    belongs_to :user, User
    has_many :credentials, Credential

    timestamps()
  end

  @doc """
  Creates a changeset for an OAuth token.
  """
  def changeset(oauth_token, attrs) do
    oauth_token
    |> cast(attrs, [:body, :scopes, :oauth_client_id, :user_id])
    |> validate_required([:body, :scopes, :oauth_client_id, :user_id])
    |> assoc_constraint(:oauth_client)
    |> assoc_constraint(:user)
    |> validate_oauth_body()
  end

  @doc """
  Creates a changeset for updating token data.
  """
  def update_token_changeset(oauth_token, new_token) do
    changeset = cast(oauth_token, %{body: new_token}, [:body])

    changeset =
      case extract_scopes(new_token) do
        {:ok, scopes} -> put_change(changeset, :scopes, scopes)
        :error -> add_error(changeset, :body, "Invalid OAuth token body")
      end

    validate_oauth_body(changeset)
  end

  @doc """
  Finds or creates an OAuth token for the given user, client and scope set.
  Returns {:ok, token} if successful, {:error, changeset} if validation fails.
  """
  def find_or_create_for_scopes(user_id, oauth_client_id, scopes, tokens)
      when is_list(scopes) do
    case find_by_scopes(user_id, oauth_client_id, scopes) do
      nil ->
        %__MODULE__{}
        |> changeset(%{
          user_id: user_id,
          oauth_client_id: oauth_client_id,
          scopes: Enum.sort(scopes),
          body: tokens
        })
        |> Lightning.Repo.insert()

      existing ->
        {:ok, existing}
    end
  end

  @doc """
  Finds an OAuth token by user and exact scope match.
  Considers all clients with the same client_id/client_secret as the given oauth_client_id.
  Uses a single query for efficiency.
  """
  def find_by_scopes(user_id, oauth_client_id, scopes)
      when is_list(scopes) do
    sorted_scopes = Enum.sort(scopes)

    Lightning.Repo.one(
      from t in __MODULE__,
        join: token_client in Lightning.Credentials.OauthClient,
        on: t.oauth_client_id == token_client.id,
        join: reference_client in Lightning.Credentials.OauthClient,
        on: reference_client.id == ^oauth_client_id,
        where:
          t.user_id == ^user_id and
            token_client.client_id == reference_client.client_id and
            token_client.client_secret == reference_client.client_secret and
            t.scopes == ^sorted_scopes
    )
  end

  @doc """
  Extracts scopes from OAuth token data.
  Returns {:ok, scopes} if successful, :error if scopes can't be determined.
  """
  def extract_scopes(%{"scope" => scope}) when is_binary(scope) do
    {:ok, String.split(scope, " ")}
  end

  def extract_scopes(%{scope: scope}) when is_binary(scope) do
    {:ok, String.split(scope, " ")}
  end

  def extract_scopes(%{"scopes" => scopes}) when is_list(scopes) do
    {:ok, scopes}
  end

  def extract_scopes(%{scopes: scopes}) when is_list(scopes) do
    {:ok, scopes}
  end

  def extract_scopes(_), do: :error

  defp validate_oauth_body(changeset) do
    with {_, body} <- fetch_field(changeset, :body), true <- is_map(body) do
      # Check if this is a new token or an update of an existing token
      oauth_token_id = get_field(changeset, :id)
      user_id = get_field(changeset, :user_id)
      oauth_client_id = get_field(changeset, :oauth_client_id)
      scopes = get_field(changeset, :scopes)

      # Use the shared validation function
      case Credentials.validate_oauth_token_data(
             body,
             user_id,
             oauth_client_id,
             scopes,
             not is_nil(oauth_token_id)
           ) do
        {:ok, _} -> changeset
        {:error, reason} -> add_error(changeset, :body, reason)
      end
    else
      _ -> add_error(changeset, :body, "Invalid OAuth token body")
    end
  end
end
