defmodule Lightning.VersionControl.ProjectRepoConnection do
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
    field :access_token, Lightning.Encrypted.Binary
    belongs_to :project, Project

    timestamps()
  end

  @fields ~w(github_installation_id repo branch project_id)a

  def changeset(project_repo_connection, attrs) do
    project_repo_connection
    |> cast(attrs, @fields)
    |> validate_required(@fields)
    |> unique_constraint(:project_id,
      message: "project already has a repo connection"
    )
  end

  def create_changeset(project_repo_connection, attrs) do
    changeset = changeset(project_repo_connection, attrs)

    if changeset.valid? do
      token = generate_access_token(32)
      put_change(changeset, :access_token, token)
    else
      changeset
    end
  end

  defp generate_access_token(length) do
    length
    |> :crypto.strong_rand_bytes()
    |> Base.encode64()
    |> binary_part(0, length)
    |> String.replace_prefix("", "prc_")
  end
end
