defmodule Lightning.Projects.Project do
  @moduledoc """
  Project model
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Lightning.Projects.{ProjectUser, ProjectCredential}
  alias Lightning.Jobs.Job

  @type t :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: Ecto.UUID.t() | nil,
          project_users: [ProjectUser.t()] | Ecto.Association.NotLoaded.t()
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "projects" do
    field :name, :string
    has_many :project_users, ProjectUser
    has_many :project_credentials, ProjectCredential
    has_many :credentials, through: [:project_credentials, :credential]

    has_many :jobs, Job

    timestamps()
  end

  @doc false
  def changeset(project, attrs) do
    project
    |> cast(attrs, [:name])
    |> cast_assoc(:project_users)
    |> validate_required([:name])
    |> validate_format(:name, ~r/^[a-z\-\d]+$/)
  end
end
