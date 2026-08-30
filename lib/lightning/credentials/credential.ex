defmodule Lightning.Credentials.Credential do
  @moduledoc """
  The Credential model.
  Stores metadata about credentials. Actual credential data lives in credential_bodies.
  """
  use Lightning.Schema

  alias Lightning.Accounts.User
  alias Lightning.Credentials.OauthClient
  alias Lightning.Projects.ProjectCredential
  alias Lightning.Validators

  @type t :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: Ecto.UUID.t() | nil,
          name: String.t(),
          schema: String.t() | nil
        }

  schema "credentials" do
    field :name, :string
    field :external_id, :string
    field :schema, :string
    field :scheduled_deletion, :utc_datetime
    field :transfer_status, Ecto.Enum, values: [:pending, :completed]

    belongs_to :user, User
    belongs_to :oauth_client, OauthClient

    has_many :project_credentials, ProjectCredential
    has_many :projects, through: [:project_credentials, :project]
    has_many :credential_bodies, Lightning.Credentials.CredentialBody

    timestamps()
  end

  @doc false
  def changeset(credential, attrs) do
    credential
    |> cast(attrs, [
      :name,
      :external_id,
      :oauth_client_id,
      :schema,
      :scheduled_deletion
    ])
    |> shared_validations()
  end

  @doc "Changeset for creating a credential; owner (:user_id) is settable only at creation."
  def create_changeset(credential, attrs) do
    credential
    |> cast(attrs, [
      :name,
      :external_id,
      :oauth_client_id,
      :schema,
      :scheduled_deletion,
      :user_id
    ])
    |> shared_validations()
  end

  @doc "Changeset for the guarded credential-transfer flow. Wraps the generic changeset so it keeps all validations/constraints, and additionally allows :user_id and :transfer_status."
  def transfer_changeset(credential, attrs) do
    credential
    |> changeset(attrs)
    |> cast(attrs, [:user_id, :transfer_status])
  end

  defp shared_validations(changeset) do
    changeset
    |> normalize_external_id()
    |> cast_assoc(:project_credentials)
    |> validate_required([:name, :user_id])
    |> unique_constraint([:name, :user_id],
      message: "you have another credential with the same name"
    )
    |> unique_constraint([:external_id, :user_id],
      message: "you already have a credential with the same external ID"
    )
    |> assoc_constraint(:user)
    |> assoc_constraint(:oauth_client)
    |> Validators.validate_name(
      :name,
      "credential name can't contain control characters"
    )
    |> Validators.validate_name_fits_column(
      :name,
      "credential name is too long, please use a shorter one"
    )
    # Two more fields on the same cast/3 with no length guard at all. schema is
    # varchar(40), not 255, so a 41 character schema was a 500 on plain ASCII
    # through POST /api/credentials.
    |> Validators.validate_name_fits_column(
      :schema,
      "credential schema is too long, please use a shorter one",
      40
    )
    |> Validators.validate_name_fits_column(
      :external_id,
      "credential external ID is too long, please use a shorter one"
    )
  end

  defp normalize_external_id(changeset) do
    case get_change(changeset, :external_id) do
      "" -> put_change(changeset, :external_id, nil)
      _ -> changeset
    end
  end
end
