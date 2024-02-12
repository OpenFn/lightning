defmodule Lightning.Projects.ProjectCredential do
  @moduledoc """
  Join table to assign credentials to a project
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Lightning.Credentials.Credential
  alias Lightning.Projects.Project

  @type t :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: Ecto.UUID.t() | nil,
          credential: Credential.t() | Ecto.Association.NotLoaded.t() | nil,
          project: Project.t() | Ecto.Association.NotLoaded.t() | nil
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "project_credentials" do
    belongs_to :credential, Credential
    belongs_to :project, Project
    field :delete, :boolean, virtual: true, default: false

    timestamps()
  end

  def changeset(comment, %{"delete" => "true"}) do
    %{change(comment, delete: true) | action: :delete}
  end

  @doc false
  def changeset(project_credential, attrs) do
    project_credential
    |> cast(attrs, [:credential_id, :project_id])
    |> validate_required([:project_id])
    |> unique_constraint([:project_id, :credential_id],
      message: "credential already added to this project."
    )
  end
end
