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
    |> validate_transfer_ownership()
  end

  defp validate_transfer_ownership(changeset) do
    user_id = get_field(changeset, :user_id)
    credential_id = get_field(changeset, :id)

    if credential_id != nil do
      diff =
        Lightning.Credentials.invalid_projects_for_user(
          credential_id,
          user_id
        )

      if Enum.empty?(diff) do
        changeset
      else
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
      end
    else
      changeset
    end
  end
end
