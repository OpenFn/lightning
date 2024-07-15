defmodule Lightning.Credentials.Credential do
  @moduledoc """
  The Credential model.
  """
  use Lightning.Schema

  alias Lightning.Accounts.User
  alias Lightning.Credentials.OauthClient
  alias Lightning.Projects.ProjectCredential

  @type t :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: Ecto.UUID.t() | nil,
          body: nil | %{}
        }

  schema "credentials" do
    field :name, :string
    field :body, Lightning.Encrypted.Map, redact: true
    field :production, :boolean, default: false
    field :schema, :string
    field :scheduled_deletion, :utc_datetime

    belongs_to :user, User
    belongs_to :oauth_client, OauthClient

    has_many :project_credentials, ProjectCredential
    has_many :projects, through: [:project_credentials, :project]

    timestamps()
  end

  @doc false
  def changeset(credential, attrs) do
    credential
    |> cast(attrs, [
      :name,
      :body,
      :production,
      :user_id,
      :oauth_client_id,
      :schema,
      :scheduled_deletion
    ])
    |> cast_assoc(:project_credentials)
    |> validate_required([:name, :body, :user_id])
    |> assoc_constraint(:user)
    |> assoc_constraint(:oauth_client)
    |> validate_oauth()
    |> validate_transfer_ownership()
  end

  defp validate_oauth(changeset) do
    if get_field(changeset, :schema) == "oauth" do
      body = get_field(changeset, :body) || %{}

      body = Enum.into(body, %{}, fn {k, v} -> {to_string(k), v} end)

      required_fields = ["access_token", "refresh_token"]
      expires_fields = ["expires_in", "expires_at"]

      has_required_fields? = Enum.all?(required_fields, &Map.has_key?(body, &1))
      has_expires_field? = Enum.any?(expires_fields, &Map.has_key?(body, &1))

      if has_required_fields? and has_expires_field? do
        changeset
      else
        add_error(
          changeset,
          :body,
          "Invalid OAuth token. Missing required fields: access_token, refresh_token, and either expires_in or expires_at."
        )
      end
    else
      changeset
    end
  end

  defp validate_transfer_ownership(changeset) do
    if changed?(changeset, :user_id) && get_field(changeset, :id) do
      user_id = get_field(changeset, :user_id)
      credential_id = get_field(changeset, :id)

      diff =
        Lightning.Credentials.invalid_projects_for_user(
          credential_id,
          user_id
        )

      if Enum.any?(diff) do
        owner = Lightning.Accounts.get_user!(user_id)

        diff_projects_names =
          diff
          |> Enum.map(fn project_id ->
            Lightning.Projects.get_project!(project_id).name
          end)

        add_error(
          changeset,
          :user_id,
          "Invalid owner: #{owner.first_name} #{owner.last_name} doesn't have access to #{Enum.join(diff_projects_names, ", ")}. Please grant them access or select another owner."
        )
      else
        changeset
      end
    else
      changeset
    end
  end
end
