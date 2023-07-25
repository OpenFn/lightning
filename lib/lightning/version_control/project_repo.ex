defmodule Lightning.VersionControl.ProjectRepo do
  @moduledoc """
  Ecto model for project repo connections
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Lightning.Projects.Project

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: Ecto.UUID.t() | nil,
          github_installation_id: String.t() | nil,
          target_id: String.t() | nil,
          repo: String.t() | nil,
          branch: String.t() | nil,
          project: nil | Project.t() | Ecto.Association.NotLoaded
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "project_repos" do
    field :github_installation_id, :string
    field :target_id, :string
    field :repo, :string
    field :branch, :string
    belongs_to :project, Project

    timestamps()
  end

  @fields ~w(github_installation_id target_id repo branch project_id)a
  def changeset(project_repo, attrs) do
    project_repo
    |> cast(attrs, @fields)
    |> validate_required(@fields)
  end
end
