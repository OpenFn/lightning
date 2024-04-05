defmodule Lightning.VersionControl.ProjectRepoConnection do
  @moduledoc """
  Ecto model for project repo connections
  """

  use Ecto.Schema
  use Joken.Config

  import Ecto.Changeset

  alias Lightning.Projects.Project

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: Ecto.UUID.t() | nil,
          github_installation_id: String.t() | nil,
          repo: String.t() | nil,
          branch: String.t() | nil,
          project: nil | Project.t() | Ecto.Association.NotLoaded
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "project_repo_connections" do
    field :github_installation_id, :string
    field :repo, :string
    field :branch, :string
    field :access_token, :binary
    field :config_path, :string
    field :accept, :boolean, virtual: true
    field :sync_direction, Ecto.Enum, values: [:deploy, :pull], virtual: true
    belongs_to :project, Project

    timestamps()
  end

  @required_fields ~w(github_installation_id repo branch project_id)a
  @other_fields ~w(config_path)a

  def changeset(project_repo_connection, attrs) do
    project_repo_connection
    |> cast(attrs, @required_fields ++ @other_fields)
    |> validate_required(@required_fields)
    |> unique_constraint(:project_id,
      message: "project already has a repo connection"
    )
  end

  def configure_changeset(project_repo_connection, attrs) do
    project_repo_connection
    |> changeset(attrs)
    |> cast(attrs, [:sync_direction, :accept])
    |> validate_required([:sync_direction, :accept])
    |> validate_change(:accept, fn :accept, accept ->
      if accept do
        []
      else
        [accept: "please tick the box"]
      end
    end)
  end

  def reconfigure_changeset(project_repo_connection, attrs) do
    project_repo_connection
    |> cast(attrs, [:sync_direction, :accept])
    |> validate_required([:sync_direction, :accept])
  end

  def create_changeset(project_repo_connection, attrs) do
    changeset = configure_changeset(project_repo_connection, attrs)

    if changeset.valid? do
      project_id = get_field(changeset, :project_id)

      token = "prc_" <> generate_access_token(project_id)

      put_change(changeset, :access_token, token)
    else
      changeset
    end
  end

  defp generate_access_token(project_id) do
    Joken.generate_and_sign!(default_claims(skip: [:exp]), %{
      "project_id" => project_id
    })
  end

  def config_path(repo_connection) do
    repo_connection.config_path ||
      "./openfn-#{repo_connection.project_id}-config.json"
  end
end
