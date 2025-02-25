defmodule Lightning.Credentials.OauthToken do
  @moduledoc """
  Schema and functions for managing OAuth tokens. This module handles the storage and
  validation of OAuth tokens, allowing multiple credentials to share the same token
  when they have identical scope sets.
  """
  use Lightning.Schema
  import Ecto.Query
  alias Lightning.Credentials.{Credential, OauthClient}
  alias Lightning.Accounts.User

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
    # |> validate_oauth_body()
    |> assoc_constraint(:oauth_client)
    |> assoc_constraint(:user)
  end

  @doc """
  Creates a changeset for updating token data.
  """
  def update_token_changeset(oauth_token, new_token) do
    cast(oauth_token, %{body: new_token}, [:body])

    # |> validate_oauth_body()
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
        |> dbg()
        |> Lightning.Repo.insert()

      existing ->
        {:ok, existing}
    end
  end

  @doc """
  Finds an OAuth token by user, client ID and exact scope match.
  """
  def find_by_scopes(user_id, oauth_client_id, scopes)
      when is_list(scopes) do
    sorted_scopes = Enum.sort(scopes)

    Lightning.Repo.one(
      from t in __MODULE__,
        where:
          t.user_id == ^user_id and
            t.oauth_client_id == ^oauth_client_id and
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

  def extract_scopes(%{"scopes" => scopes}) when is_list(scopes) do
    {:ok, scopes}
  end

  def extract_scopes(_), do: :error

  # Private Functions

  # defp validate_oauth_body(changeset) do
  #   with {:ok, body} <- fetch_field(changeset, :body),
  #        true <- is_map(body) do
  #         body
  #     body = Enum.into(body, %{}, fn {k, v} -> {to_string(k), v} end)

  #     required_fields = ["access_token", "refresh_token"]
  #     expires_fields = ["expires_in", "expires_at"]

  #     cond do
  #       not Enum.all?(required_fields, &Map.has_key?(body, &1)) ->
  #         add_error(
  #           changeset,
  #           :body,
  #           "Missing required OAuth fields: access_token, refresh_token"
  #         )

  #       not Enum.any?(expires_fields, &Map.has_key?(body, &1)) ->
  #         add_error(
  #           changeset,
  #           :body,
  #           "Missing expiration field: either expires_in or expires_at is required"
  #         )

  #       true ->
  #         changeset
  #     end
  #   else
  #     _ -> add_error(changeset, :body, "Invalid OAuth token body")
  #   end
  # end
end
