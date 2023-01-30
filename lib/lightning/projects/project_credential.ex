defmodule Lightning.Projects.ProjectCredential do
  @moduledoc """
  Join table to assign credentials to a project
  """
  use Ecto.Schema
  import Ecto.Changeset
  alias Lightning.Projects.Project
  alias Lightning.Credentials.Credential

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
    field :delete, :boolean, virtual: true

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
      message: "Credential already added to this project."
    )
  end

  def import_changeset(project_credential, attrs, %{
        project_id: project_id,
        user_id: user_id
      }) do
    IO.inspect(project_credential, label: "PROJECT_CREDENTIAL")
    IO.inspect(attrs, label: "ATTRS")

    # credential_id = Ecto.UUID.generate()

    # change =
    #   workflow
    #   |> cast(
    #     Map.put(attrs, :id, ),
    #     [:name, :project_id, :id]
    #   )

    # workflow_id = change |> get_field(:id)

    # project_credential
    # |> cast(attrs, [:project_id])
    # |> cast_assoc(:credential, with: &Credential.changeset/2) |> IO.inspect()
  end
end
