defmodule CredentialsService.Credentials.Credential do
  @moduledoc """
  Credential metadata. Secret values live in `CredentialBody`, never here.

  Note the two **cross-context foreign keys** that become an extraction seam:
  `user_id` (owned by Accounts) and, via `project_credentials`, `project_id`
  (owned by Projects). In this standalone service they are opaque `:binary_id`
  columns, not `belongs_to` associations, because those tables live in other
  services. See `docs/migration-analysis.md`.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias CredentialsService.Credentials.{CredentialBody, OauthClient}
  alias CredentialsService.Projects.ProjectCredential

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "credentials" do
    field :name, :string
    field :external_id, :string
    field :schema, :string
    field :scheduled_deletion, :utc_datetime
    field :transfer_status, Ecto.Enum, values: [:pending, :completed]

    # Cross-context FK to Accounts.User. Opaque id at the service boundary.
    field :user_id, :binary_id

    belongs_to :oauth_client, OauthClient

    has_many :project_credentials, ProjectCredential
    has_many :credential_bodies, CredentialBody

    timestamps()
  end

  @doc false
  def changeset(credential, attrs) do
    credential
    |> cast(attrs, [
      :name,
      :external_id,
      :user_id,
      :oauth_client_id,
      :schema,
      :scheduled_deletion,
      :transfer_status
    ])
    |> normalize_external_id()
    |> cast_assoc(:credential_bodies)
    |> cast_assoc(:project_credentials)
    |> validate_required([:name, :user_id])
    |> unique_constraint([:name, :user_id],
      message: "you have another credential with the same name"
    )
    |> validate_format(:name, ~r/^[a-zA-Z0-9_\- ]*$/,
      message: "credential name has invalid format"
    )
  end

  defp normalize_external_id(changeset) do
    case get_change(changeset, :external_id) do
      "" -> put_change(changeset, :external_id, nil)
      _ -> changeset
    end
  end
end
