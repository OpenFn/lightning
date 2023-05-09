defmodule Lightning.Projects.Project do
  @moduledoc """
  Project model
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Lightning.Projects.{ProjectUser, ProjectCredential}
  alias Lightning.Workflows.Workflow

  @type t :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: Ecto.UUID.t() | nil,
          project_users: [ProjectUser.t()] | Ecto.Association.NotLoaded.t()
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "projects" do
    field :name, :string
    field :description, :string
    has_many :project_users, ProjectUser
    has_many :users, through: [:project_users, :user]
    has_many :project_credentials, ProjectCredential
    has_many :credentials, through: [:project_credentials, :credential]

    has_many :workflows, Workflow
    has_many :jobs, through: [:workflows, :jobs]

    timestamps()
  end

  @doc false
  def changeset(project, attrs) do
    project
    |> cast(attrs, [:name, :description])
    |> cast_assoc(:project_users)
    |> validate()
  end

  def changeset_for_import(project, attrs) do
    project
    |> cast(attrs, [:id, :name, :description])
    |> validate_required([:id])
    |> validate()
  end

  def validate(changeset) do
    changeset
    |> validate_length(:description, max: 240)
    |> validate_required([:name])
    |> validate_format(:name, ~r/^[a-z\-\d]+$/)
  end
end
