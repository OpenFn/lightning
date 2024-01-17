defmodule Lightning.VersionControl.ProjectRepoConnection do
  @moduledoc """
  Ecto model for project repo connections
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Lightning.Accounts.User
  alias Lightning.Projects.Project

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: Ecto.UUID.t() | nil,
          github_installation_id: String.t() | nil,
          repo: String.t() | nil,
          branch: String.t() | nil,
          project: nil | Project.t() | Ecto.Association.NotLoaded,
          user: nil | User.t() | Ecto.Association.NotLoaded
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "project_repo_connections" do
    field :github_installation_id, :string
    field :repo, :string
    field :branch, :string
    belongs_to :project, Project
    belongs_to :user, User

    timestamps()
  end

  @fields ~w(github_installation_id repo branch)a
  @required_fields ~w(user_id  project_id)a
  def changeset(project_repo_connection, attrs) do
    project_repo_connection
    |> cast(attrs, @fields ++ @required_fields)
    |> validate_required(@required_fields)
    |> unique_constraint(:project_id,
      message: "project already has a repo connection"
    )
  end
end
