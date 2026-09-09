defmodule Lightning.Projects.ProjectCredential do
  @moduledoc """
  Join table to assign credentials to a project.

  Carries the grant: which of the credential's bodies this project may read. A
  project used to assert an environment *name* and resolution matched that name
  against the credential's bodies at run time, which meant a name typed on the
  project settings screen decided which secret a job received. The grant records
  the decision on the share instead, so it cannot be widened by renaming
  anything.

  `credential_body_id` is nullable and nil means no grant, which resolves
  nothing. A composite foreign key ties the pair to `credential_bodies`, so a
  share can only ever grant a body belonging to the credential it was given.
  """
  use Lightning.Schema

  alias Lightning.Credentials.Credential
  alias Lightning.Credentials.CredentialBody
  alias Lightning.Projects.Project

  @type t :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: Ecto.UUID.t() | nil,
          credential: Credential.t() | Ecto.Association.NotLoaded.t() | nil,
          credential_body:
            CredentialBody.t() | Ecto.Association.NotLoaded.t() | nil,
          project: Project.t() | Ecto.Association.NotLoaded.t() | nil
        }

  schema "project_credentials" do
    belongs_to :credential, Credential
    belongs_to :credential_body, CredentialBody
    belongs_to :project, Project
    field :delete, :boolean, virtual: true, default: false

    timestamps()
  end

  def changeset(project_credential, %{"delete" => "true"}) do
    %{change(project_credential, delete: true) | action: :delete}
  end

  @doc false
  def changeset(project_credential, attrs) do
    project_credential
    |> cast(attrs, [:credential_id, :project_id, :credential_body_id])
    # Not credential_id: cast_assoc sets it from the parent credential after
    # this runs, so requiring it here refuses every credential-creation path.
    # The column is NOT NULL, which is the honest place for that rule.
    |> validate_required([:project_id])
    |> unique_constraint([:project_id, :credential_id],
      message: "credential already added to this project."
    )
    |> foreign_key_constraint(:credential_body_id,
      name: :project_credentials_credential_body_fkey,
      message: "does not belong to this credential"
    )
  end
end
